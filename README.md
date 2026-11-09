# ourbills 3.0 — one-time splits and a space for two

Static mobile-first app deployed by Vercel from `main`.

## Entry points

- `/`: two choices: หารครั้งเดียว / คู่รัก. This page does not write or migrate financial data.
- `/split`: the retained guest app, multi-slip Inbox, local backups and settlements. No account required. The original localStorage key `ourbills_v2_data` and IndexedDB database `ourbills_receipts_v3` stay on the same origin, so existing device data remains accessible.
- `/shared`: online couple spaces and all legacy shared books. Uses the existing **Wealth PWA** Supabase project, with separate `ourbills_*` tables, private invitations and a private receipt bucket. Existing Wealth tables, rows and RLS policies are unchanged.

The interface uses paper white, charcoal and sage, with Home / Bills / Settings navigation. Home shows the cumulative balance and separate Import receipt / Add expense actions. Receipt selection uses a custom, keyboard-accessible upload card and image preview. Recognition still runs in the browser without a paid API.

Sessions keep the original `ourbills_cloud_auth_v1` storage key. The last selected space is remembered separately for each authenticated user, validated against the RLS-filtered space list on return. A sole space opens automatically. Membership and display identity come from `ourbills_members`, not a device nickname. Sign-out or an account change clears the open financial form.

## Using a shared book

1. Sign in with your Wealth PWA email and password, or create an account. If email confirmation is enabled, confirm the email and return to ourbills to sign in.
2. Create a book and choose your display name.
3. New spaces created in 3.0 are couples, limited to two accounts by the database. The owner generates a single-use invitation, valid for seven days. The recipient signs into their own account and joins. Generating a new couple invitation invalidates earlier unused links. Pending invitations can be revoked. Existing shared books retain their original group behavior and records (maximum 20); they are not silently converted.
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

`db/ourbills-3-couple.sql` is the one-time additive 3.0 upgrade after bootstrap. It adds a `mode` column with `shared` as the legacy default and updates the existing checked RPC. It does not delete or migrate records. Couple invitation generation and joining lock the book before the token, serializing capacity checks and avoiding inverse lock order during rotation. Apply it before deploying the 3.0 frontend.

Supabase Auth email delivery and confirmation settings are inherited from Wealth PWA. Email confirmation and password-based sign-in must be enabled/configured appropriately in that project. Default Supabase email delivery restrictions may require custom SMTP before inviting general public users. Existing Auth email templates and redirect configuration were preserved.

## Validation

- `node tests/test-core.mjs`: integer amounts, rounding, alternating payers, settlements, post-settlement adjustments, escaping and Thai/English OCR candidate ranking.
- `node tests/test-pages.mjs`: parse inline page scripts and check entry routes, retained storage identities and the custom receipt picker.
- `tests/test-db.sql`: runs a transaction with temporary synthetic users, tests book isolation, owner-only invitations, one-use invitations, direct-write denial, Wealth isolation, idempotency, stale-edit rejection, invalid participants and excessive/double settlements, then **rolls back all test records**.
- Browser QA with a local-only data fixture verified adding an expense, calculating its split, cumulative balance changes and clearing a recorded settlement. Fixture files are excluded from the repository and deployment.
- Real browser OCR on a synthetic receipt selected 800.00 instead of cash tendered 1,000.00 or change 200.00.
- Production-account sign-in and real email delivery were not exercised; no user's credentials or actual financial data were used for tests.
- The project's pre-existing leaked-password-protection warning remains an Auth configuration consideration: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection

Shared JSON export includes records and receipt paths, not image bytes. Account deletion, member removal, offline cloud edits and automated migration of guest bills are not implemented.

### 3.0 verification (9 November 2026)

- Production migration applied successfully. Transactional SQL regressions passed, including two-member capacity with a separate still-valid token, token rotation, authenticated identity, anonymous denial and the existing financial/isolation cases. All synthetic test records rolled back.
- Hashes of existing books (excluding the added mode field), members, entries, settlements and audit records matched before and after the upgrade/tests.
- Local browser QA used synthetic records, never production account credentials: 800 paid by Alice, 200 paid by Bob, resulting in 300 owed to Alice; reload resumed the space and identity; Settings/history and return to the space list worked.
- The new import control opened the chooser, showed a receipt preview, read the synthetic receipt's 800 total rather than 1,000 cash / 200 change, and removed the image correctly. No console errors were observed during that flow.
- Guest bill creation and return through the new landing page retained the bill. Responsive QA covered 320 and 390 CSS-pixel viewports; the shared Home had no horizontal overflow at 320.
- Real email confirmation, real two-device sign-in and a physical iPhone camera remain unverified. The pre-existing leaked-password-protection warning remains; no paid service or Auth configuration change was introduced.
