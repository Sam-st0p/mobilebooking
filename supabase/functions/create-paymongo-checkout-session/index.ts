// supabase/functions/create-paymongo-checkout-session/index.ts
//
// Called by the Flutter app (via supabase.functions.invoke) right after a
// booking is created. Never called with the PayMongo secret key on the
// client — that key lives only in this function's environment
// (`supabase secrets set PAYMONGO_SECRET_KEY=...`).
//
// Input:  { "booking_id": "uuid" }
// Output: { "checkout_url": "...", "session_id": "..." }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const PAYMONGO_SECRET_KEY = Deno.env.get('PAYMONGO_SECRET_KEY')!;
const PAYMONGO_PAYMENT_METHODS = (Deno.env.get('PAYMONGO_PAYMENT_METHODS') ?? 'gcash,card,qrph')
  .split(',')
  .map((m) => m.trim())
  .filter(Boolean);

// Same values as NEXT_PUBLIC_APP_URL in the website's .env — PayMongo
// redirects the browser here after payment. These don't need to be a
// custom URL scheme; the app re-checks the booking's payment_status via
// Realtime once the user switches back, independent of this redirect.
const SUCCESS_URL = Deno.env.get('APP_PAYMENT_SUCCESS_URL') ?? 'https://rentals.example.com/payment-complete';
const CANCEL_URL = Deno.env.get('APP_PAYMENT_CANCEL_URL') ?? 'https://rentals.example.com/payment-cancelled';

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  const jwt = authHeader.replace(/^Bearer\s+/i, '');
  if (!jwt) return json({ error: 'Missing Authorization header' }, 401);

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data: userData, error: userErr } = await supabase.auth.getUser(jwt);
  if (userErr || !userData?.user) return json({ error: 'Invalid session' }, 401);
  const uid = userData.user.id;

  let body: { booking_id?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid JSON body' }, 400);
  }
  const bookingId = body.booking_id;
  if (!bookingId) return json({ error: 'booking_id is required' }, 400);

  const { data: booking, error: bookingErr } = await supabase
    .from('bookings')
    .select('id, user_id, total_amount, payment_status, products(name)')
    .eq('id', bookingId)
    .single();

  if (bookingErr || !booking) return json({ error: 'Booking not found' }, 404);
  if (booking.user_id !== uid) return json({ error: 'Not your booking' }, 403);
  if (booking.payment_status === 'paid') return json({ error: 'Booking is already paid' }, 409);

  // PayMongo amounts are integer centavos.
  const amountCentavos = Math.round(Number(booking.total_amount) * 100);
  // deno-lint-ignore no-explicit-any
  const productName = (booking as any).products?.name ?? 'Rental booking';

  const paymongoRes = await fetch('https://api.paymongo.com/v1/checkout_sessions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: 'Basic ' + btoa(`${PAYMONGO_SECRET_KEY}:`),
    },
    body: JSON.stringify({
      data: {
        attributes: {
          send_email_receipt: false,
          show_description: true,
          show_line_items: true,
          success_url: `${SUCCESS_URL}?booking_id=${bookingId}`,
          cancel_url: `${CANCEL_URL}?booking_id=${bookingId}`,
          payment_method_types: PAYMONGO_PAYMENT_METHODS,
          description: `Booking ${bookingId.slice(0, 8).toUpperCase()}`,
          line_items: [
            {
              name: productName,
              amount: amountCentavos,
              currency: 'PHP',
              quantity: 1,
            },
          ],
          metadata: { booking_id: bookingId },
        },
      },
    }),
  });

  if (!paymongoRes.ok) {
    const detail = await paymongoRes.text();
    console.error('PayMongo checkout session error', detail);
    return json({ error: 'Could not create PayMongo checkout session' }, 502);
  }

  const paymongoData = await paymongoRes.json();
  const checkoutUrl = paymongoData?.data?.attributes?.checkout_url;
  const sessionId = paymongoData?.data?.id;

  if (!checkoutUrl) {
    return json({ error: 'PayMongo did not return a checkout URL' }, 502);
  }

  await supabase
    .from('bookings')
    .update({ paymongo_checkout_session_id: sessionId })
    .eq('id', bookingId);

  return json({ checkout_url: checkoutUrl, session_id: sessionId });
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}