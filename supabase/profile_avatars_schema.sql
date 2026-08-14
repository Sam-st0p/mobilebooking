-- ============================================================================
-- Avatar storage for the profile screen (lib/screens/account/profile_screen.dart).
--
-- ASSUMPTION: bucket name 'avatars' — not confirmed against the real
-- website schema (same caveat as booking-documents earlier in this
-- project). If the website already has a differently-named bucket for
-- profile photos, tell me the real name — it's a one-line change in
-- lib/services/profile_service.dart, nothing else depends on this file.
--
-- Safe to re-run: every statement is idempotent.
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- Anyone can view avatars (they're rendered as public NetworkImage URLs in
-- the app), but a user may only upload/replace/delete their own — enforced
-- by requiring the file path's first folder segment to match their uid,
-- same pattern as booking-documents.
drop policy if exists "avatars are publicly readable" on storage.objects;
create policy "avatars are publicly readable"
  on storage.objects for select
  using (bucket_id = 'avatars');

drop policy if exists "users manage their own avatar" on storage.objects;
create policy "users manage their own avatar"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "users update their own avatar" on storage.objects;
create policy "users update their own avatar"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );