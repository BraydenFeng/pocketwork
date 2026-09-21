# Pocketwork iPhone app

Pocketwork is already used on a physical iPhone through signed TestFlight builds. The latest upload checked during this work was run [35419265206](https://github.com/BraydenFeng/pocketwork/actions/runs/35419265206), commit `d38b914`, September 19, 2026. That verifies the upload, not the new release-preparation code or App Store approval.

The host supports on-phone page editing, Supabase Apple sign-in, cloud sync, native focus sessions, weekly schedules and home allowance, app groups, Health inputs, connected foreground behaviors, widgets, and a Live Activity. Documents are validated declarative JSON, not downloaded executable code. The current source adds format-4 timers, variable actions, independent time windows, records, and connected numeric targets, plus account deletion and StoreKit subscription support.

## Build and test

On a Mac with Xcode and XcodeGen, run `xcodegen generate` in `ios/`, then test the Pocketwork scheme on an installed simulator. Device builds use the configured bundle identifiers, Apple development team, matching App Group, Family Controls entitlements, and provisioning profiles. End users do not need developer accounts.

The CI workflow runs web checks on pushes; **macOS runs only on explicit dispatch or a commit containing `[ios]`**. Do not accidentally run both. The TestFlight workflow is a separate, manual signed upload.

Set `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `POCKETWORK_WEBSITE_URL` in build settings. Billing stays disabled until `PocketworkSubscriptionsEnabled` is deliberately enabled after configuring and testing the server and monthly product. No service-role key or Apple private key belongs in the iPhone bundle.

## Safety boundaries

- Screen Time requires on-device consent and private app selection. A simulator cannot prove real enforcement.
- Native schedules and home allowance use DeviceActivity and OS location callbacks, which are not guaranteed exact wall-clock alarms.
- Generic connected routines run only while their page is open. Page app gates release when paused, backgrounded, or closed. Native schedules are independent. General timers retain elapsed time while away; their actions evaluate on reopening.
- End session and **Clear all focus restrictions** remain available without Pro. Page limits never disable existing pages or their stop controls.
- App selections, saved location, Health readings, and detailed behavior progress stay on-device. Page definitions and optional status summaries sync through the account.
- New format-4 cloud sync stays disabled until the compatible phone release is available to syncing users. The source support alone is not a rollout.

## Public release

Use [the release checklist](../RELEASE.md) for Vercel, database migration, purchase verification, deletion and Apple token revocation, privacy details, entitlements, App Review concerns, and physical-device QA. Publisher/support details are intentionally unfinished. This task does not submit to App Store.
