# #ourbills 3.0 — Minimal / No Account

Static PWA for Vercel. Upload all files to the root of a GitHub repository, import in Vercel, choose Framework Preset: Other, and deploy. Open in Safari on iPhone and choose Share → Add to Home Screen.

## Features
- Existing v2 bills, people, equal/custom/percent/later splits, settlements and share summaries retained
- Bill Inbox: multi-photo upload, shop, place, date, amount, note, search and pending/cleared statuses
- Photo storage in IndexedDB (compressed), bill metadata in localStorage; no server or login
- Convert inbox item to bill expense; original inbox receipt retained
- Full JSON backup including inbox photos, restore v2/v3, clear local data

## Important
- Browser storage is device-local and may be deleted by browser or user. Export a backup regularly.
- Sharing a bill shares a summary, not a live synchronized bill.
- Online OCR, cloud sync, and shared editable links are intentionally not included.
- IndexedDB availability and storage quota depend on the browser.
