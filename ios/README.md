# Native host: development source, not a released app

The host is the iPhone app: a **My tools** list, the same five routines as the web editor, on-phone editing, and a runner for each tool with real timers, checklists, counters, and Screen Time. Tools are stored in the same library format the web editor uses. A phone that only had the old single imported tool sees it as its first tool. Each tool keeps its own private app selection; one focus session runs at a time.

The host renders the same version-1 JSON document as the web editor. It contains real Family Controls / Managed Settings integration and a Device Activity monitor extension. It has NOT been compiled, signed, approved by Apple, or device-tested in the Windows development environment. Do not advertise working device blocking until the checklist below passes on a physical iPhone.

## Build without a Mac

`.github/workflows/ci.yml` compiles this host and runs its XCTests on a GitHub-hosted macOS runner on every push. That proves the Swift builds and the model logic passes; it cannot prove Screen Time enforcement, which needs a signed build on a physical iPhone.

## Build on a Mac

1. Install Xcode with the iOS SDK and XcodeGen (`brew install xcodegen`).
2. In `project.yml`, replace all `com.example.pocketwork` identifiers with identifiers belonging to your developer team. Set `DEVELOPMENT_TEAM` under `settings.base` or select the same team for both targets in Xcode after generation.
3. Register an App Group and set `APP_GROUP` to its identifier. The host and extension must use the exact same group. Both need Family Controls and App Groups capabilities.
4. Run `xcodegen generate` in this directory, then open `Pocketwork.xcodeproj`.
5. Select the Pocketwork scheme and a physical iPhone running iOS 17 or newer. Build and run. Development testing needs valid provisioning; an App Store distribution entitlement is a separate step.
6. Pick a routine on the My tools screen, or use **Add from file** in the menu to bring in a `.pocketwork.json` export from the web editor (it is added as a new tool, never a replacement).
7. Open a tool and use **Choose apps privately** to authorize individual Screen Time access and select apps, categories, or websites for that tool. **Edit** changes its name, blocks, and rules on the phone. Notification authorization is requested only when starting a session whose rule enables it.

The developer needs the signing account; end users of a future App Store release would not need their own developer account. This source project does not provide sideloading, a public beta, or App Store distribution.

## Home screen widget and Live Activity

`PocketworkWidgets` is a WidgetKit extension with two pieces. The **Routine** widget (small and medium) shows one routine chosen when the widget is added: name, summary, status, and a live countdown while it runs; tapping opens that routine through `com.braydenfeng.pocketwork://routine/<id>`. The app writes a `WidgetSnapshot` into the App Group whenever the library or session changes (`HomeScreenBridge.publish`), so the widget never reads the library. The **Live Activity** shows a running session on the lock screen and Dynamic Island with an End button; `EndFocusSessionIntent` is a `LiveActivityIntent`, so it runs in the app process and calls `SessionController.shared.stop()`. Live Activities need `NSSupportsLiveActivities` (set in `project.yml`) and the person's permission under Settings → Pocketwork → Live Activities.

## Behavior and safety limits

- One focus session at a time, 15–120 minutes. No recurring schedules, calendar triggers, or arbitrary background code yet.
- Blocking uses a named ManagedSettings store. DeviceActivity schedules the end cleanup in a separate extension; callbacks occur when iOS delivers them, often when the device is next used, not a guaranteed wall-clock alarm.
- Session state and private app-selection tokens stay in the shared on-device App Group. Tokens never enter exported JSON or the browser.
- Unique activity names keep old callbacks from intentionally controlling a newer session. Starting a session rolls back shields, monitoring, and pending notification if setup fails.
- An explicit **End session** action and **Clear all focus restrictions** menu action remain available. This is self-directed focus support, not tamper-proof parental supervision.
- Checklists/counters persist on device per tool. Deleting a tool removes its progress and app selection. An active session must be stopped before editing that tool or changing its apps.
- No login, network calls, analytics, subscriptions, HealthKit, location, calendar, or MCP bridge.

## Required device checks

- [ ] Host and extension compile with the configured App Group and signing identities.
- [ ] Denying Screen Time authorization leaves no restrictions applied and gives a useful error.
- [ ] An empty app selection cannot start a blocking session.
- [ ] A real 15-minute session blocks ONLY the selected apps/sites/categories.
- [ ] End session and emergency clear both immediately release restrictions.
- [ ] Leave the app, lock the phone, and return after the deadline: no lingering shields.
- [ ] Force-quit the host during the session; verify monitor cleanup when the device is next used.
- [ ] Test across midnight, time-zone changes, reboot, and daylight-saving transitions.
- [ ] Rapidly stop/restart sessions; stale callbacks must not clear a newer session.
- [ ] Deny/revoke notification and Screen Time permissions; verify safe recovery.
- [ ] Notifications fire once on natural completion and are canceled on manual stop.
- [ ] Import malformed, oversized, duplicate-ID, and unsupported-version files; the current tool stays intact.

Run the included XCTest target with Product → Test, or `xcodebuild test -project Pocketwork.xcodeproj -scheme Pocketwork -destination 'platform=iOS Simulator,name=<installed simulator>'`. Simulator tests validate the model; they do not prove Screen Time enforcement.

## Distribution gate

Request [Family Controls distribution approval](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement) for the host and monitor extension. Describe the configurable-host model accurately during App Review; its acceptance is not implied by obtaining an entitlement. Do not expose arbitrary downloaded code or assume mini-app native API permission. Review [Apple's guidelines](https://developer.apple.com/app-store/review/guidelines/), including 4.7 and 4.10, before monetizing.

References: [DeviceActivityCenter callback behavior](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter), [minimum monitoring interval](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/intervaltooshort), [Screen Time architecture](https://developer.apple.com/videos/play/wwdc2021/10123/), [XcodeGen](https://github.com/yonaskolb/XcodeGen).
