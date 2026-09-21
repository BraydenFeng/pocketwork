# Pocketwork launch checklist

Status: release preparation, not permission to submit. Vercel deployment alone does not make this App Store-ready. Public publisher/support details were deliberately deferred by the owner.

## Product and rollout

- Pages contain routines (actions/conditions/controls) and data (values, entries, displays). Existing `routine` MCP tool names and JSON keys remain compatible.
- Free: three pages at a time, MCP, sync, and on-device permissions. Delete a page to reuse a slot. Pro: up to 50 pages, proposed US price $5.99/month. Configure the actual price in App Store Connect; the app displays StoreKit's localized price.
- Cancellation preserves all existing pages and their controls. Only new pages over the free allowance are prevented. This is enforced on the phone, web, and database, including MCP writes.
- Apple 4.10 prohibits monetizing built-in capabilities including Screen Time APIs. A general page allowance is not a guarantee of approval. Explain the full productivity workspace and pricing honestly; review this unresolved issue before submission. Do not hide or rename Screen Time charges to evade review.
- New format-4 primitives have native source support, but cloud release is gated by `NEXT_PUBLIC_NATIVE_FORMAT4_ENABLED=false`. Keep it false until a compatible phone build is installed/available to every syncing user. The flag is build-time for the website: redeploy when enabling it. Do not enable just because simulator compilation passes.
- Generic connected logic runs while its page is open. Timers track elapsed wall time while away, but completion actions evaluate on reopening. Native focus/schedule/home-allowance presets have separate background support. Never advertise arbitrary always-on background workflows.

## Vercel and database

1. Import this Next.js repo into Vercel. Set the variables from `.env.example`; no private key may use a `NEXT_PUBLIC_` prefix. Store `.p8` contents as secret values, with real newlines or escaped `\n`. Do not commit `.env` or private keys.
2. Use a stable public HTTPS origin for `SITE_URL`. Add `PUBLIC_PUBLISHER_NAME` and `PUBLIC_SUPPORT_EMAIL` before public release. Privacy, terms, and support pages visibly identify missing details while unset.
3. Apply `supabase/schema.sql` in the intended Supabase project after taking a database backup. This task does not apply it remotely. The added tables have RLS and no client write privileges. The library trigger enforces the page limit. Existing over-limit rows remain editable; inserts/added IDs require a free slot or a freshly verified subscription.
4. Test quota with authenticated test accounts through PostgREST directly as well as MCP: 3 succeeds; 4 fails; another user's rows are inaccessible; writing `page_subscriptions` is forbidden; deletion frees a slot; expired Pro can edit/delete old pages but cannot add a fourth. SQL has not been exercised against a live database here.
5. Configure Supabase Apple OAuth and redirect allowlists for the Vercel origin and `com.braydenfeng.pocketwork://auth/callback`. Google remains opt-in; configure its credentials and consent screen before enabling its web/native flags.
6. In the same Apple Services ID used by Supabase, register the website domain and the exact return URL `https://YOUR_DOMAIN/api/account/apple-callback`. Set `APPLE_SIGNIN_*` for token exchange/revocation. Team ID is the Sign in with Apple issuer; it is not the App Store Connect issuer UUID.
7. Set `NEXT_PUBLIC_SUBSCRIPTIONS_ENABLED=true` only after the subscription backend and SQL policies work. `APP_STORE_ENVIRONMENT=Sandbox` is for an isolated staging deployment/test database; production must use `Production`. Never let Sandbox transactions grant production entitlements.
8. Plan status refreshes via Apple's server API. Database additions above the free limit require a verification no older than five minutes; ordinary clients refresh before adding. Refund/expiry changes are reflected on refresh, not by an unverified client receipt. No server-notification endpoint is currently deployed. Retest refund and offline recovery behavior before launch.
9. Run `npm run check:release`. It checks presence and safe shapes, not live credentials or approval. Do not publish until manual items below are complete.

## Apple product and phone build

- Create the monthly auto-renewing product `com.braydenfeng.pocketwork.pro.monthly`, subscription group, display name, review screenshot, availability, and price. Complete paid-app agreement, tax, and banking setup. Submit the initial subscription with the app version as required by App Store Connect.
- Configure a server In-App Purchase API key in `APP_STORE_*`. Native transactions carry an `appAccountToken` tied to the signed-in Supabase UUID; purchases cannot be claimed by another account. Restore must use the original Pocketwork account. Subscription transfer after account deletion is not automated; cancelling before deletion is clearly disclosed.
- Supply `POCKETWORK_WEBSITE_URL` when generating/building the phone project. Turn on `PocketworkSubscriptionsEnabled` in the generated Info properties only for a configured, tested release. The source defaults to false; a product that fails to load cannot be purchased.
- Verify Family Controls distribution entitlements for both the app and FocusMonitor, matching App Groups and provisioning profiles for all targets. Existing successful TestFlight uploads do not prove this launch's setup or App Review acceptance.
- CI only runs native tests when dispatched with `ios=true` or a commit contains `[ios]`. After the first run, the user authorized further verification builds. This does not authorize TestFlight upload or App Store submission. Avoid `[ios]` in the commit when using dispatch so it does not run twice.

## Account deletion verification

- In Account, confirm deletion; Apple-linked accounts reauthenticate with the matching Apple identity. The server consumes a hashed single-use, ten-minute state, checks the nonce/subject/signature, revokes Apple's token, then deletes the Supabase user. Failed revocation does not claim successful deletion.
- Verify Apple and Google test accounts; cancellation, wrong Apple identity, expired/replayed state, network failure, and retry. Confirm cloud library/status/subscription rows cascade away and auth no longer works. Device cleanup releases restrictions, clears saved sign-in and that account's library/progress. Verify these behaviors on a physical phone.
- Other devices and exported files are not remotely erased. Check sign-out/removal on them separately. Deleting Pocketwork does not cancel Apple billing; both web and phone expose Manage subscriptions and warn about this.
- Follow-up cleanup also clears this phone's shared saved location/geofence, home ledger/policy, and current account's app-group selections/plans. Other accounts' cached libraries are left alone. Cleanup attempts continue when one device service fails; the app signs out and reports incomplete cleanup instead of claiming everything was removed. Test recovery from local storage/keychain errors on a physical phone.

## Privacy / review metadata

- Publisher name and monitored support email: REQUIRED, deferred by owner.
- Public privacy URL, support URL, terms URL: populate from the deployed stable domain, not localhost.
- Privacy manifest includes required reasons for app/shared UserDefaults and elapsed-time use. Confirm the archived app and extensions contain their manifests and review Xcode's privacy report.
- App Privacy labels must match actual configuration: email, user ID, synced page definitions/app-group names, optional status/minute history, subscription identifiers/status. These are used for app functionality, linked to the account, not advertising tracking. Health readings, selected app tokens, and saved location are processed on-device; user-entered page text is synced and may itself contain sensitive content.
- Inspect Vercel/Supabase logging and backup retention, SDK manifests, age rating, export compliance, screenshots, accurate App Store description, and reviewer access. The supplied privacy/terms text is a launch draft, not a legal-compliance certification.
- Reviewer notes: this is a declarative productivity workspace, not arbitrary downloaded executable code. Include exact steps for creating a page, choosing apps, granting permissions, enabling a native schedule, emergency unblocking, testing connected foreground logic, restoring purchases, and deleting the account. Provide a usable review account/setup where required.

## Physical-device release gate (all pending for these changes)

- Selected apps only; outside every active window and away from the selected location, this routine adds no blocker. Check other routines separately. Test window start/end, overnight, DST/time-zone changes, reboot, lock, and force-quit.
- Page app gates release on pause, navigation away, background, missing input, permission loss, or failure. Native schedules remain independently active. Emergency Clear all focus restrictions always works regardless of plan.
- Timer pause/resume/stop/reset, record save-once, variable edits, changing connected targets, and old-format migration. Health denial/unavailable values do not become fake zero measurements or stuck gates.
- Three free pages, delete/recreate, paid fourth page, cross-device sync, wrong-account restore, pending purchase, user cancellation, renewal, expiration, billing grace, refund, and offline/retry recovery.
- Apple sign-in, Google if enabled, deletion + Apple revocation + local cleanup. No real personal account should be used for destructive testing.
- VoiceOver, Dynamic Type, contrast, keyboard controls, small iPhone/iPad layouts, no clipped purchase/legal controls.

## References

[App Review 4.10](https://developer.apple.com/app-store/review/guidelines/#monetizing-built-in-capabilities), [account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/), [Apple token revocation](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple), [subscription status API](https://developer.apple.com/documentation/appstoreserverapi/get-all-subscription-statuses), [Family Controls distribution](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement).
