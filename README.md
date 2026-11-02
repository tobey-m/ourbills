# ourbills — local splits and shared books

Static mobile-first app deployed by Vercel from `main`.

## Entry points

- `/`: existing guest bills, multi-slip Inbox, local backups and settlements. No account required. Existing localStorage and IndexedDB identities are preserved.
- `/shared`: online shared books. Uses the existing **Wealth PWA** Supabase project, with separate `ourbills_*` tables, private invitations and a private receipt bucket. Existing Wealth tables, rows and RLS policies are unchanged.

## Using a shared book

1. Sign in with your Wealth PWA email and password, or create an account. If email confirmation is enabled, confirm the email and return to ourbills to sign in.
2. Create a book and choose your display name.
3. The owner generates a single-use invitation, valid for seven days. The recipient signs into their own account and joins. Generate a new link for each additional member (maximum 20 per book). Pending invitations can be revoked.
4. Add a receipt, confirm the detected amount, and enter a place. Payer defaults to the signed-in member; equal sharing defaults to all book members. Custom amounts and an “I am covering this” option are available.
5. See monthly expenses and cumulative outstanding balances. Record transfers only after money has actually moved. The app does not transfer funds.

## Data consistency and access

- All money is stored and calculated as integer satang.
- All shared reads enforce book membership through RLS. Guest clients have no access to the shared tables.
- All financial mutations use one transactional RPC. The server validates membership, shares, payer, total, receipt path and maximum outstanding settlement.
- A book-level lock serializes financial writes. Entry versions reject stale edits. Client-generated entry and settlement IDs prevent duplicate retries.
- Deletions are soft deletions. Audit rows preserve the actor, before/after records and timestamps. Earlier settlements remain recorded when an expense is edited.
- Receipt uploads are compressed, private and limited to 2 MB per image. Signed viewing URLs expire after two minutes.
- Invitations are hashed at rest and supplied in the URL fragment, not the query string. The page uses `no-referrer` and clears the invitation fragment after capture.
- Cloud records are fetched into memory; guest bills are not automatically uploaded. Shared sessions use their own browser storage key.
- Visible open books refresh approximately every 15 seconds; background refresh pauses while editing. Saving requires an internet connection. A failed form remains open for correction/retry.

## Receipt recognition

Tesseract.js 5.1.1 runs Thai/English recognition in the browser, downloading its runtime/language files on first use. Total labels are ranked above line-item amounts; subtotal, tax, tendered cash and change lines are excluded. Recognition can be wrong. Users must review amounts before saving. Manual entry remains available when recognition cannot load or find a total. JPG, PNG and WebP are accepted; HEIC needs conversion first.

The shared page pins `@supabase/supabase-js` 2.57.4 as a browser ESM dependency. `shared-config.js` contains only a browser-safe publishable key, never a service-role key.

## Deployment and database setup

Vercel uses the retained `vercel.json` (`cleanUrls: true`). Shared pages are static, with no Vercel secret needed. Supabase authorization lives in RLS and the checked RPC, not in the publishable key.

`db/ourbills-bootstrap.sql` documents the additive schema and private Storage policies. It is a one-time bootstrap for an empty ourbills schema, not a script to rerun against a database already configured. Production schema changes were applied through Supabase migration history. No separate Supabase project or paid upgrade was created.

Supabase Auth email delivery and confirmation settings are inherited from Wealth PWA. Email confirmation and password-based sign-in must be enabled/configured appropriately in that project. Default Supabase email delivery restrictions may require custom SMTP before inviting general public users. Existing Auth email templates and redirect configuration were preserved.

## Validation

- `node tests/test-core.mjs`: integer amounts, rounding, alternating payers, settlements, post-settlement adjustments, escaping and Thai/English OCR candidate ranking.
- `tests/test-db.sql`: runs a transaction with temporary synthetic users, tests book isolation, owner-only invitations, one-use invitations, direct-write denial, Wealth isolation, idempotency, stale-edit rejection, invalid participants and excessive/double settlements, then **rolls back all test records**.
- Browser QA with a local-only data fixture verified adding an expense, calculating its split, cumulative balance changes and clearing a recorded settlement. Fixture files are excluded from the repository and deployment.
- Real browser OCR on a synthetic receipt selected 800.00 instead of cash tendered 1,000.00 or change 200.00.
- Production-account sign-in and real email delivery were not exercised; no user's credentials or actual financial data were used for tests.
- The project's pre-existing leaked-password-protection warning remains an Auth configuration consideration: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection

Shared JSON export includes records and receipt paths, not image bytes. Account deletion, member removal, offline cloud edits and automated migration of guest bills are not implemented.
