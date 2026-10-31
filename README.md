# ReList

A student-only marketplace: any verified `.edu` student can buy, and every listing is location-checked to within 5 miles of a campus. Payments go through Stripe Connect: authorize at accept, capture on the in-person handoff scan.

**Stack:** Next.js (App Router, TypeScript) · Supabase (Postgres, Auth, Storage, Realtime) · PostGIS · Stripe Connect (test mode) · pgTAP + Vitest · GitHub Actions

## Run locally (Windows, macOS or Linux)
Needs Node 24 and Docker Desktop.

```bash
npm install
npx supabase start          # local Postgres/Auth/Mailpit in Docker; applies migrations
cp .env.example .env.local  # fill the key from `npx supabase status`
npm run dev                 # http://localhost:3000
```
Sign-up emails (6-digit codes) land in Mailpit at http://127.0.0.1:54324.

## Tests
| Command | What it checks |
|---|---|
| `npm run db:test` | pgTAP: RLS on every table, privacy suite (users can't see or write each other's rows), sign-up rules |
| `npm run db:advisors` | Supabase security + performance advisors, fails on warnings |
| `npm test` | Vitest unit tests |
| `npm run typecheck && npm run lint` | TypeScript and ESLint |

## How access control works
- Every table in `public` gets RLS on automatically (event trigger), and a catalog test fails CI if any table lacks RLS or a policy.
- Only `.edu` addresses can create an account (Supabase Before User Created hook).
- Membership (school, campus, 18+) is written only by `create_membership()`, which derives school and campus from the verified email domain on the server.
