-- ============================================================================
-- Booking schema for the customer mobile app's reservation flow.
--
-- ASSUMPTIONS (no existing booking schema was provided when this was
-- written — flag any mismatch with your real schema and only the mapping
-- code in lib/services/booking_service.dart + lib/models/booking.dart
-- needs to change, not this file's shape):
--   - `products` table has: id (uuid), daily_rate (numeric),
--     refundable_deposit (numeric), status (text)
--   - `get_product_availability(p_product_id, p_start_date, p_end_date)`
--     already exists (used by lib/services/product_service.dart) and
--     returns rows with total_units / available_units for that range.
--   - auth.uid() is the customer's id, matching profiles.id
--
-- Safe to re-run: every statement is idempotent (IF NOT EXISTS / OR REPLACE).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. bookings table
-- ---------------------------------------------------------------------------
create table if not exists public.bookings (
  id                          uuid primary key default gen_random_uuid(),
  user_id                     uuid not null references auth.users(id) on delete cascade,
  product_id                  uuid not null references public.products(id) on delete restrict,

  status                      text not null default 'pending_review'
                                check (status in (
                                  'pending_review', 'approved', 'rejected',
                                  'active', 'completed', 'cancelled'
                                )),

  start_date                  date not null,
  end_date                    date not null check (end_date >= start_date),
  quantity                    int not null default 1 check (quantity > 0),

  -- Snapshotted at booking time so later price changes on the product
  -- don't retroactively change what the customer agreed to pay.
  daily_rate_snapshot         numeric not null check (daily_rate_snapshot >= 0),
  refundable_deposit_snapshot numeric not null default 0 check (refundable_deposit_snapshot >= 0),
  subtotal                    numeric not null check (subtotal >= 0),
  total_amount                numeric not null check (total_amount >= 0),

  -- Rental requirements
  full_name                   text not null,
  phone_number                text not null,
  full_address                text not null,
  id_type                     text not null,
  id_photo_path                text not null,

  -- Agreement
  agreement_accepted_at       timestamptz not null,

  -- Payment (proof-of-payment model: GCash / bank transfer screenshot)
  -- Payment via PayMongo Checkout Sessions (see
  -- supabase/functions/create-paymongo-checkout-session and
  -- supabase/functions/paymongo-webhook). Booking rows are created
  -- unpaid; the webhook flips payment_status to 'paid' once PayMongo
  -- confirms the charge. payment_reference/payment_proof_path are kept
  -- for a possible manual/offline fallback later but aren't populated
  -- by the normal flow anymore.
  payment_status                text not null default 'unpaid'
                                check (payment_status in ('unpaid', 'paid', 'refunded', 'failed')),
  paymongo_checkout_session_id  text,
  payment_method                text,
  payment_reference             text,
  payment_proof_path            text,

  admin_notes                  text,
  created_at                   timestamptz not null default now(),
  updated_at                   timestamptz not null default now()
);

create index if not exists bookings_user_id_idx on public.bookings(user_id);
create index if not exists bookings_product_id_idx on public.bookings(product_id);
create index if not exists bookings_status_idx on public.bookings(status);

-- Migration guard: if you already ran an earlier version of this file
-- (proof-of-payment model), bring an existing table up to date rather
-- than relying on CREATE TABLE IF NOT EXISTS, which only applies to
-- brand-new tables.
alter table public.bookings
  add column if not exists payment_status text not null default 'unpaid';
alter table public.bookings
  drop constraint if exists bookings_payment_status_check;
alter table public.bookings
  add constraint bookings_payment_status_check
  check (payment_status in ('unpaid', 'paid', 'refunded', 'failed'));
alter table public.bookings
  add column if not exists paymongo_checkout_session_id text;
alter table public.bookings
  alter column payment_method drop not null;
alter table public.bookings
  alter column payment_method drop default;

-- Keep updated_at fresh.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists bookings_set_updated_at on public.bookings;
create trigger bookings_set_updated_at
  before update on public.bookings
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 2. Row Level Security
-- ---------------------------------------------------------------------------
alter table public.bookings enable row level security;

-- Customers can see only their own bookings.
drop policy if exists "customers select own bookings" on public.bookings;
create policy "customers select own bookings"
  on public.bookings for select
  using (auth.uid() = user_id);

-- Direct inserts are blocked — all creation must go through
-- create_booking() below, which validates availability and pricing
-- server-side (security definer) rather than trusting client-supplied
-- totals. No insert policy is created on purpose.

-- Customers may cancel their own booking, but only while it's still
-- pending review (once approved/active, changes should go through staff).
drop policy if exists "customers cancel own pending bookings" on public.bookings;
create policy "customers cancel own pending bookings"
  on public.bookings for update
  using (auth.uid() = user_id and status = 'pending_review')
  with check (auth.uid() = user_id and status = 'cancelled');

-- ---------------------------------------------------------------------------
-- 3. create_booking RPC — atomic availability check + insert.
--    Pricing is recomputed server-side from the live product row so a
--    tampered client payload can't under-report the total.
-- ---------------------------------------------------------------------------
-- Old signature (proof-of-payment model) — drop before recreating with the
-- new parameter list, since Postgres treats a differing param list as a
-- distinct overload rather than a replacement.
drop function if exists public.create_booking(
  uuid, date, date, int, text, text, text, text, text, text, text
);

create or replace function public.create_booking(
  p_product_id            uuid,
  p_start_date             date,
  p_end_date               date,
  p_quantity               int,
  p_full_name              text,
  p_phone_number           text,
  p_full_address           text,
  p_id_type                text,
  p_id_photo_path          text
)
returns public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_daily_rate numeric;
  v_deposit numeric;
  v_days int;
  v_subtotal numeric;
  v_total numeric;
  v_available int;
  v_booking public.bookings;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  if p_end_date < p_start_date then
    raise exception 'end date must be on or after start date';
  end if;

  -- Advisory lock on the product to reduce (not fully eliminate, without
  -- deeper access to the inventory schema) the race between the
  -- availability check and the insert below.
  perform pg_advisory_xact_lock(hashtext(p_product_id::text));

  select daily_rate, refundable_deposit
    into v_daily_rate, v_deposit
    from public.products
    where id = p_product_id and status = 'active';

  if v_daily_rate is null then
    raise exception 'Product not found or not available';
  end if;

  select coalesce(available_units, 0)
    into v_available
    from public.get_product_availability(p_product_id, p_start_date, p_end_date)
    limit 1;

  if v_available is null or v_available < p_quantity then
    raise exception 'Only % unit(s) available for those dates', coalesce(v_available, 0);
  end if;

  v_days := (p_end_date - p_start_date) + 1;
  v_subtotal := v_daily_rate * v_days * p_quantity;
  v_total := v_subtotal + (v_deposit * p_quantity);

  insert into public.bookings (
    user_id, product_id, start_date, end_date, quantity,
    daily_rate_snapshot, refundable_deposit_snapshot, subtotal, total_amount,
    full_name, phone_number, full_address, id_type, id_photo_path,
    agreement_accepted_at, payment_status
  ) values (
    v_uid, p_product_id, p_start_date, p_end_date, p_quantity,
    v_daily_rate, v_deposit, v_subtotal, v_total,
    p_full_name, p_phone_number, p_full_address, p_id_type, p_id_photo_path,
    now(), 'unpaid'
  )
  returning * into v_booking;

  return v_booking;
end;
$$;

grant execute on function public.create_booking(
  uuid, date, date, int, text, text, text, text, text
) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Realtime — lets the app watch a booking row and see payment_status
--    flip from 'unpaid' to 'paid' the moment the webhook processes it,
--    instead of polling.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'bookings'
  ) then
    alter publication supabase_realtime add table public.bookings;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Storage bucket for ID photos (private — not public, unlike
--    product-images). Payment proof uploads are no longer part of the
--    normal flow now that payment goes through PayMongo Checkout, but the
--    bucket name is kept generic in case a manual/offline fallback is
--    needed later.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('booking-documents', 'booking-documents', false)
on conflict (id) do nothing;

-- Customers may upload only into a folder named after their own uid, and
-- may read back only their own files.
drop policy if exists "customers upload own booking documents" on storage.objects;
create policy "customers upload own booking documents"
  on storage.objects for insert
  with check (
    bucket_id = 'booking-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "customers read own booking documents" on storage.objects;
create policy "customers read own booking documents"
  on storage.objects for select
  using (
    bucket_id = 'booking-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );