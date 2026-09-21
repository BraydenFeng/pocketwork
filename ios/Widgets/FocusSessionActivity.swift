import ActivityKit
import SwiftUI
import WidgetKit

// The running session on the lock screen and in the Dynamic Island, with an End button that works without unlocking.
struct FocusSessionActivity: Widget {
	var body: some WidgetConfiguration {
		ActivityConfiguration(for: FocusActivityAttributes.self) { context in
			lock_screen(context)
		} dynamicIsland: { context in
			DynamicIsland {
				DynamicIslandExpandedRegion(.leading) {
					VStack(alignment: .leading, spacing: 2) {
						Text(context.attributes.routine_name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
						Text(context.state.blocks_apps ? "Apps locked" : "Focusing").font(.system(size: 12)).foregroundStyle(.secondary)
					}
				}
				DynamicIslandExpandedRegion(.trailing) {
					Text(timerInterval: Date.now...max(Date.now, context.state.ends_at), countsDown: true).font(.system(size: 24, weight: .medium, design: .monospaced)).monospacedDigit().frame(width: 92, alignment: .trailing)
				}
				DynamicIslandExpandedRegion(.bottom) {
					Button(intent: EndFocusSessionIntent()) { Label("End session", systemImage: "stop.fill").frame(maxWidth: .infinity) }.buttonStyle(.bordered).tint(.primary)
				}
			} compactLeading: {
				Image(systemName: context.state.blocks_apps ? "shield.fill" : "timer").foregroundStyle(WidgetTheme.accent)
			} compactTrailing: {
				Text(timerInterval: Date.now...max(Date.now, context.state.ends_at), countsDown: true).monospacedDigit().frame(width: 52)
			} minimal: {
				Image(systemName: "timer").foregroundStyle(WidgetTheme.accent)
			}
		}
	}

	private func lock_screen(_ context: ActivityViewContext<FocusActivityAttributes>) -> some View {
		HStack(alignment: .center, spacing: 14) {
			VStack(alignment: .leading, spacing: 4) {
				Text(context.attributes.caption.uppercased()).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(0.8).foregroundStyle(WidgetTheme.text_faint)
				Text(context.attributes.routine_name).font(.system(size: 17, weight: .semibold)).tracking(-0.3).foregroundStyle(WidgetTheme.text).lineLimit(1)
				Text(context.state.blocks_apps ? "Your chosen apps stay locked until this ends." : "One thing at a time.").font(.system(size: 12)).foregroundStyle(WidgetTheme.text_dim).lineLimit(2)
			}
			Spacer(minLength: 0)
			VStack(alignment: .trailing, spacing: 8) {
				Text(timerInterval: Date.now...max(Date.now, context.state.ends_at), countsDown: true).font(.system(size: 28, weight: .medium, design: .monospaced)).monospacedDigit().foregroundStyle(WidgetTheme.text).frame(width: 104, alignment: .trailing)
				Button(intent: EndFocusSessionIntent()) { Label("End", systemImage: "stop.fill").font(.system(size: 13, weight: .medium)) }.buttonStyle(.bordered).tint(WidgetTheme.text)
			}
		}
		.padding(16)
		.activityBackgroundTint(WidgetTheme.surface)
		.activitySystemActionForegroundColor(WidgetTheme.text)
	}
}
