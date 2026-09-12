# Pocketwork

A local-first visual workbench for personal iPhone tools. Temporary product name; no accounts, AI inference, tracking, subscription billing, or public deployment.

## Run the editor

Use Node.js 24 LTS for the editor and its current test tooling.

```sh
npm ci
npm run dev
```

Open http://127.0.0.1:3210. The server binds to loopback only. Your tools are saved in this browser's localStorage; switching browser or port does not carry them with it. Export backups before clearing browser data.

## First slice

- My tools is the front door: every saved tool as a card (open, duplicate, delete), plus five ready-made routines (Deep work, Study sprints, Phone-free bedtime, Morning start, Reading time) and a blank start. Picking a routine creates a tool and opens the editor; `?tool=<id>` in the URL means the browser back button returns to the list. A browser that only has a v1 single draft sees it as its first tool; the old key is left in place.
- A skippable, replayable Quick start guide walks through customization, test mode, and the native iPhone setup boundary without replacing your draft. Dismissal is remembered locally.
- Layout / Rules / Advanced separate visual editing from behavior and raw configuration; included native blocks open their settings. Narrow layouts bring settings into view and offer Back to preview.
- Add, edit, reorder (drag or keyboard-accessible move buttons), and remove heading, timer, checklist, counter, note, and Screen Time blocks.
- Configure blocking-during-focus and completion-notification rules.
- Switch between selecting blocks and interacting with the phone preview. The activity log explicitly labels native effects as simulations.
- Undo/redo up to 60 edits; validated import/export with a versioned, bounded schema.
- The SwiftUI iPhone app has the same My tools list and routines, edits tools on the phone, and runs them with permission handling, per-tool private app selection, session state, a DeviceActivity monitor extension, and on-device checklist/counter storage. `public/routines.pocketwork.json` (regenerate with `npm run routines`) is the shared routine fixture; a test keeps it identical to `lib/templates.ts`.
- GitHub Actions (`.github/workflows/ci.yml`) runs the web checks on Linux and compiles and tests the iPhone app on a macOS runner, so the Swift is verified without a Mac.

**The browser does not block apps. Native source is included but has not been compiled or tested on an iPhone from this Windows machine.** Follow `ios/README.md` for signing, provisioning, physical-device checks, and Apple's approval requirements.

## Account and sync (optional)

Without a configured project everything stays on this browser. To turn on accounts: create a Supabase project, copy `.env.example` to `.env` with the Project URL and anon/publishable key, run `supabase/schema.sql` once in the SQL editor, enable the Google provider under Authentication → Providers, and add `http://127.0.0.1:3210` (and any deployed origin) to Authentication → URL Configuration. Sign in with Google appears in the top bar. The whole library is one JSON row per user; the browser stays local-first and reconciles on sign-in, on focus, and after every save (`lib/sync.ts`: newest edit wins, deletions are remembered for 30 days).

## Architecture

```text
Visual editor → validated v1 JSON → local draft / exported file
                                      ↓
                            SwiftUI native host
                                      ↓
                 preimplemented native capabilities + user consent
```

`lib/library.ts` is the collection of tools kept in this browser (`pocketwork.library.v1`), `lib/templates.ts` the routines. `lib/document.ts` is the editor schema. `ios/Shared/AppDocument.swift` validates the corresponding native boundary. `public/starter.pocketwork.json` is the shared fixture. There is no executable JS/Swift in a tool document. Screen Time selection tokens remain on device.

`lib/runtime.ts` is the deterministic browser simulator; it measures deadlines using absolute time rather than assuming intervals fire while a tab sleeps. Changing a configuration resets the preview session. The iOS host uses a separate monitor extension for blocking-session cleanup and local notifications for completion alerts.

## Checks

```sh
npm test
npm run typecheck
npm run verify:ui
npm run build
```

UI tokens and structural rules are in `DESIGN.md` and `app/tokens.css`. `tools/ui-lint.mjs` derives from the local ui-system skill and gates the build. Browser regression checks are documented in `tests/browser.spec.ts` and run with `npx playwright test` after installing a supported browser.

## Intentionally not built yet

Cloud sync, multi-device pairing, App Store release, subscriptions, a full drag-and-drop layout grid, recurring schedules, calendar/location integrations, widgets, and MCP. The first MCP implementation should manipulate this same strict document schema with authenticated, user-approved edits, not expose arbitrary native execution.
