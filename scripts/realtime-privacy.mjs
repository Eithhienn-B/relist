// Realtime privacy check against the local stack: who receives postgres_changes on a thread.
// Usage: npx supabase status -o env > .env.status (or export the vars), then
//   node --env-file=.env.status scripts/realtime-privacy.mjs <seller-email> <buyer-email> <third-email> <listing-id>
// Expects: seller gets the visible message only, buyer (sender) gets both incl. the held one, third member and anon get nothing.
import { createClient } from "@supabase/supabase-js";

const url = process.env.API_URL, pub = process.env.PUBLISHABLE_KEY, secret = process.env.SECRET_KEY;
const [sellerEmail, buyerEmail, thirdEmail, listingId] = process.argv.slice(2);
if (!url || !pub || !secret || !listingId) throw new Error("missing env or args");
if (!/^http:\/\/(127\.0\.0\.1|localhost)/.test(url)) throw new Error("local stack only");

const admin = createClient(url, secret, { auth: { persistSession: false } });
async function signIn(email) {
  const { data, error } = await admin.auth.admin.generateLink({ type: "magiclink", email });
  if (error) throw error;
  const c = createClient(url, pub, { auth: { persistSession: false } });
  const { error: e2 } = await c.auth.verifyOtp({ email, token: data.properties.email_otp, type: "email" });
  if (e2) throw e2;
  return c;
}

const seller = await signIn(sellerEmail), buyer = await signIn(buyerEmail), third = await signIn(thirdEmail);
const anon = createClient(url, pub, { auth: { persistSession: false } });
const { data: threadId, error } = await buyer.rpc("open_thread", { p_listing: listingId });
if (error) throw error;

const got = {}, status = {};
async function listen(name, c) {
  got[name] = [];
  if (name !== "anon") await c.realtime.setAuth();
  await new Promise((resolve) => {
    c.channel(`thread:${threadId}`)
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "messages", filter: `thread_id=eq.${threadId}` },
        (p) => got[name].push(p.new.body))
      .subscribe((s, err) => { status[name] = err ? `${s}: ${err.message}` : s; if (s !== "SUBSCRIBED" || name) resolve(); });
    setTimeout(resolve, 4000);
  });
}
await Promise.all([listen("seller", seller), listen("buyer", buyer), listen("third", third), listen("anon", anon)]);
await new Promise((r) => setTimeout(r, 1500));

const sender = (await buyer.auth.getUser()).data.user.id;
for (const [body, flags] of [["visible hello", []], ["held text", ["harassment"]]]) {
  const { error: e } = await admin.rpc("send_message", { p_sender: sender, p_thread: threadId, p_body: body, p_flags: flags, p_nudge: false });
  if (e) throw e;
}
await new Promise((r) => setTimeout(r, 3000));

const expect = { seller: ["visible hello"], buyer: ["visible hello", "held text"], third: [], anon: [] };
let failed = 0;
for (const [name, want] of Object.entries(expect)) {
  const ok = JSON.stringify(got[name]) === JSON.stringify(want);
  if (!ok) failed++;
  console.log(`${ok ? "PASS" : "FAIL"} ${name.padEnd(6)} join=${status[name]} received=${JSON.stringify(got[name])}`);
}
await Promise.all([seller, buyer, third, anon].map((c) => c.removeAllChannels()));
process.exit(failed ? 1 : 0);
