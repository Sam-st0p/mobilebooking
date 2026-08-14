// supabase/functions/paymongo-webhook/index.ts
//
// Configure this URL as a webhook endpoint in the PayMongo dashboard,
// subscribed to at least `checkout_session.payment.paid`. Set
// PAYMONGO_WEBHOOK_SECRET via `supabase secrets set` to the *webhook's*
// signing secret (not the API secret key — PayMongo issues those
// separately, same distinction as PAYMONGO_SECRET_KEY vs
// PAYMONGO_WEBHOOK_SECRET in the website's .env).
//
// IMPORTANT: verify this function against PayMongo's current webhook
// signature docs before relying on it in production — the header format
// below (`t=...,te=...,li=...`, HMAC-SHA256 of `{timestamp}.{raw_body}`)
// matches PayMongo's documented scheme as of this writing, but double
// check nothing has changed on their end.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const PAYMONGO_WEBHOOK_SECRET = Deno.env.get('PAYMONGO_WEBHOOK_SECRET')!;

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const rawBody = await req.text();
  const signatureHeader = req.headers.get('Paymongo-Signature') ?? '';

  const valid = await isValidSignature(rawBody, signatureHeader, PAYMONGO_WEBHOOK_SECRET);
  if (!valid) {
    console.error('PayMongo webhook: signature verification failed');
    return new Response('Invalid signature', { status: 401 });
  }

  let event: any;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return new Response('Invalid JSON', { status: 400 });
  }

  const eventType = event?.data?.attributes?.type;

  if (eventType === 'checkout_session.payment.paid') {
    const session = event.data.attributes.data;
    const bookingId: string | undefined = session?.attributes?.metadata?.booking_id;

    if (bookingId) {
      const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
      const { error } = await supabase
        .from('bookings')
        .update({ payment_status: 'paid' })
        .eq('id', bookingId);

      if (error) {
        console.error('Failed to mark booking paid', bookingId, error);
        // Still 200 — PayMongo will retry on non-2xx, but a DB write
        // failure here needs investigation, not a retry storm.
      }
    } else {
      console.error('PayMongo webhook: no booking_id in metadata', event?.data?.id);
    }
  }

  // Acknowledge everything else (payment.failed, etc.) without action for
  // now — extend here if you want to record failed attempts too.
  return new Response('ok', { status: 200 });
});

async function isValidSignature(rawBody: string, header: string, secret: string): Promise<boolean> {
  if (!header || !secret) return false;

  const parts = Object.fromEntries(
    header.split(',').map((kv) => {
      const [k, v] = kv.split('=');
      return [k, v];
    }),
  );
  const timestamp = parts['t'];
  // 'li' = live signature, 'te' = test signature — accept whichever is
  // present so this works against both PAYMONGO_SECRET_KEY test and live
  // webhook secrets.
  const signature = parts['li'] ?? parts['te'];
  if (!timestamp || !signature) return false;

  const signedPayload = `${timestamp}.${rawBody}`;
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sigBuffer = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(signedPayload));
  const computed = Array.from(new Uint8Array(sigBuffer))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');

  return timingSafeEqual(computed, signature);
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}