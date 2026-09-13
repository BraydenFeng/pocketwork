# Pocketwork

Small iPhone routines that hold you to what you decided. A local-first web editor plus a SwiftUI iPhone app that share one routine format. No AI inference, no tracking; an optional account only syncs your own routines.

## Run the editor

Use Node.js 24 LTS for the editor and its current test tooling.

```sh
npm ci
npm run dev
```

Open http://127.0.0.1:3210. The server binds to loopback only. Your routines are saved in this browser's localStorage (and to your account once you sign in); switching browser or port does not carry them with it unless you are signed in. Export backups before clearing browser data.

## What is built

- My routines is the front door: every saved routine as a card (open, duplicate, delete), app groups and a blank start. Picking one creates a routine and opens the editor; `?routine=<id>` in the URL means the browser back button returns to the list. A browser that only has a v1 single draft sees it as its first routine; the old key is left in place.
- Two kinds of routine. One-time: a Focus timer you start yourself. Standing: a Schedule block (days plus a window such as 22:00 to 07:00, may cross midnight, at least 15 minutes) with an On/Off switch on the card and in the preview; it locks the chosen apps by itself while the window is open. A routine has a timer or a schedule, never both, and a schedule always needs a Screen Time block with blocking on.
- App groups: named once in the library (Social, Work, Distractions), filled with real apps on each iPhone through Apple's picker, referenced by name from a routine's Screen Time block. Three functions: block the groups, allow only the groups (everything else locks), or limit the groups to so many minutes inside the routine's window. Renaming a group follows through every routine; a group in use cannot be deleted; a routine that mentions a new group creates it. With no groups a routine keeps its own private app selection.
- A skippable, replayable Quick start guide walks through customization, test mode, and the native iPhone setup boundary. Dismissal is remembered locally.
- Layout / Rules / Advanced separate visual editing from behavior and raw configuration; included native blocks open their settings. Narrow layouts bring settings into view and offer Back to preview.
- Add, edit, reorder (drag or keyboard-accessible move buttons), and remove heading, timer, schedule, checklist, counter, note, and Screen Time blocks.
- Switch between selecting blocks and interacting with the phone preview. The activity log explicitly labels native effects as simulations.
- Undo/redo up to 60 edits; validated import/export with a versioned, bounded schema.
- The SwiftUI iPhone app has the same My routines list and app groups; edits routines on the phone; and runs them with permission handling, session state, a DeviceActivity monitor extension, and on-device checklist/counter storage. Standing routines register one repeating DeviceActivity per chosen weekday and shield through their own ManagedSettings store; limits use DeviceActivity usage thresholds. `public/routines.pocketwork.json` (regenerate with `npm run routines`) is the shared routine fixture; a test keeps it identical to `lib/templates.ts`.
- GitHub Actions (`.github/workflows/ci.yml`) runs the web checks on Linux and compiles and tests the iPhone app on a macOS runner, uploading simulator screenshots, so the Swift is verified without a Mac.

**The browser does not block apps. Native source compiles and passes its tests on a simulator, but has not run on a physical iPhone.** Follow `ios/README.md` for signing, provisioning, physical-device checks, and Apple's approval requirements.

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

App Store release, subscriptions, a full drag-and-drop layout grid, calendar/location integrations, widgets, and MCP. The first MCP implementation should manipulate this same strict document schema with authenticated, user-approved edits, not expose arbitrary native execution.

## Web and iPhone cloud workflow

Use Sign in with Apple on the website and in the updated TestFlight app with the same Apple account. Start with New routine; the ready-made catalog is no longer shown. Existing personal routines are preserved. The website saves locally immediately and syncs after edits, on focus, and every 15 seconds while visible. The iPhone syncs after edits, on opening/foreground, or pull-to-refresh. iOS does not receive cloud changes while the app is closed; open it to apply updated schedules. Choose apps and grant Screen Time access on the phone. Ongoing timer progress and private app selections remain on device.

The existing Supabase libraries table and RLS policies work without another migration. Writes compare the server updated_at timestamp and retry after conflicts. Account libraries are stored separately on each device. iPhone refresh tokens live in Keychain. Google support is implemented but hidden until enabled (web: NEXT_PUBLIC_GOOGLE_ENABLED=true, iOS Info.plist: SupabaseGoogleEnabled=true).

Add com.braydenfeng.pocketwork://auth/callback to Supabase Authentication redirect URLs. iOS reads SupabaseURL and SupabaseAnonKey from build settings, supplied by the manual TestFlight workflow from the same public client settings as the website. No service-role key is bundled. Local iOS builds need SUPABASE_URL and SUPABASE_ANON_KEY build settings.

## Home allowance and MCP

The personal seed is available at `http://127.0.0.1:3210/?seed=home` after signing in. It calls the authenticated `seed_home_allowance` MCP tool, preserves an existing routine with the same ID, and starts disabled. The user must install the new TestFlight build, set home while physically there, allow Always location access, choose the Distractions apps, and enable the allowance. Routine format 2 prevents older builds from silently ignoring the home requirement.

Weekdays Mon–Thu share 30 minutes across 18:00–18:30 and 19:00–20:50; Friday gets 120 minutes in 14:30–20:20; each weekend day gets 180 minutes in 06:30–20:30. Outside windows, distractions are blocked only at home. Away use is unrestricted and uncounted. The allowance resets at midnight America/Los_Angeles. Home coordinates remain in the iPhone App Group, not Supabase. One home allowance per device is supported because iOS caps monitored activities.

The native meter uses whole-minute checkpoints and a fresh activity after returning home. The final partial minute can be lost on departure, and OS geofence/threshold callbacks may be delayed. This is not second-accurate metering, and simulator tests cannot prove background enforcement on a real iPhone. A physical-device leave/return test remains required. The geofence radius is 150 m; disabling location access leaves the home restriction inactive.

The signed-in website has Copy agent connection. This copies a short-lived Supabase bearer token into an MCP HTTP config for the current account. Keep that config private; it expires with the session, and there is no refresh/admin token in it. Copy again after expiration. The endpoint is `/api/mcp`, validates the token with Supabase, and supports list_routines, get_capabilities, save_routine, delete_routine, and the personal seed. Writes use the existing RLS-protected library row and optimistic revision checks. No AI service is invoked.

For stdio clients run `node tools/mcp-server.mjs` with POCKETWORK_MCP_URL and POCKETWORK_ACCESS_TOKEN supplied by your agent client. The local website server must remain running. This is a local developer connection, not a hosted OAuth discovery service; no Codex plugin or background service was installed.
