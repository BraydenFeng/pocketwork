import AppIntents
import SwiftUI
import WidgetKit

// One routine per widget. The person picks which routine when they add the widget; the tile deep-links straight into it.
struct RoutineEntity: AppEntity {
	static var typeDisplayRepresentation: TypeDisplayRepresentation = "Routine"
	static var defaultQuery = RoutineQuery()
	var id: String
	var name: String
	var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct RoutineQuery: EntityQuery {
	func entities(for identifiers: [String]) async throws -> [RoutineEntity] {
		tiles().filter { identifiers.contains($0.id) }.map { RoutineEntity(id: $0.id, name: $0.name) }
	}
	func suggestedEntities() async throws -> [RoutineEntity] { tiles().map { RoutineEntity(id: $0.id, name: $0.name) } }
	func defaultResult() async -> RoutineEntity? { tiles().first.map { RoutineEntity(id: $0.id, name: $0.name) } }
	private func tiles() -> [RoutineTile] { WidgetSnapshot.load()?.tiles ?? [] }
}

struct RoutineWidgetIntent: WidgetConfigurationIntent {
	static var title: LocalizedStringResource = "Routine"
	static var description = IntentDescription("Show one of your routines on the home screen.")
	@Parameter(title: "Routine") var routine: RoutineEntity?
}

struct RoutineEntry: TimelineEntry {
	let date: Date
	let tile: RoutineTile?
	let placeholder: Bool
}

struct RoutineProvider: AppIntentTimelineProvider {
	func placeholder(in context: Context) -> RoutineEntry {
		RoutineEntry(date: .now, tile: RoutineTile(id: "sample", name: "Deep work", summary: "90 min session · blocks Distractions", status: "Ready · tap to start", standing: false, enabled: false, running: false, ends_at: nil), placeholder: true)
	}

	func snapshot(for configuration: RoutineWidgetIntent, in context: Context) async -> RoutineEntry {
		RoutineEntry(date: .now, tile: resolve(configuration), placeholder: false)
	}

	func timeline(for configuration: RoutineWidgetIntent, in context: Context) async -> Timeline<RoutineEntry> {
		let tile = resolve(configuration)
		let entry = RoutineEntry(date: .now, tile: tile, placeholder: false)
		// A running session ends at a known time; ask to be redrawn then. Otherwise the app reloads us whenever something changes.
		if var after = tile, let ends_at = tile?.ends_at, ends_at > .now {
			after.running = false; after.ends_at = nil; after.status = "Ready · tap to start"
			return Timeline(entries: [entry, RoutineEntry(date: ends_at, tile: after, placeholder: false)], policy: .atEnd)
		}
		return Timeline(entries: [entry], policy: .never)
	}

	private func resolve(_ configuration: RoutineWidgetIntent) -> RoutineTile? {
		let tiles = WidgetSnapshot.load()?.tiles ?? []
		if let chosen = configuration.routine { return tiles.first { $0.id == chosen.id } }
		return tiles.first
	}
}

struct RoutineWidgetView: View {
	@Environment(\.widgetFamily) private var family
	let entry: RoutineEntry

	var body: some View {
		Group {
			if let tile = entry.tile { tile_view(tile) } else { empty }
		}
		.containerBackground(WidgetTheme.surface, for: .widget)
		.widgetURL(entry.tile.flatMap { WidgetSnapshot.url(for: $0.id) })
	}

	private var empty: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("POCKETWORK").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(WidgetTheme.text_faint)
			Text("No routines yet").font(.system(size: 15, weight: .semibold)).foregroundStyle(WidgetTheme.text)
			Text("Open the app to make one.").font(.system(size: 12)).foregroundStyle(WidgetTheme.text_faint)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
	}

	private func tile_view(_ tile: RoutineTile) -> some View {
		let small = family == .systemSmall
		return VStack(alignment: .leading, spacing: small ? 4 : 6) {
			HStack(spacing: 6) {
				Circle().fill(tile.running ? WidgetTheme.success : (tile.standing && tile.enabled ? WidgetTheme.accent : WidgetTheme.border)).frame(width: 6, height: 6)
				Text(tile.summary.uppercased()).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(0.8).foregroundStyle(WidgetTheme.text_faint).lineLimit(1)
			}
			Text(tile.name).font(.system(size: small ? 17 : 20, weight: .semibold)).tracking(-0.4).foregroundStyle(WidgetTheme.text).lineLimit(2).minimumScaleFactor(0.8)
			Spacer(minLength: 0)
			if tile.running, let ends_at = tile.ends_at, ends_at > .now {
				Text(timerInterval: Date.now...ends_at, countsDown: true).font(.system(size: small ? 26 : 32, weight: .medium, design: .monospaced)).monospacedDigit().foregroundStyle(WidgetTheme.text).lineLimit(1).minimumScaleFactor(0.6)
				Text("Running").font(.system(size: 11)).foregroundStyle(WidgetTheme.success)
			} else {
				Text(tile.status).font(.system(size: 11)).foregroundStyle(WidgetTheme.text_dim).lineLimit(2)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.redacted(reason: entry.placeholder ? .placeholder : [])
	}
}

struct RoutineWidget: Widget {
	var body: some WidgetConfiguration {
		AppIntentConfiguration(kind: "com.braydenfeng.pocketwork.routine", intent: RoutineWidgetIntent.self, provider: RoutineProvider()) { entry in
			RoutineWidgetView(entry: entry)
		}
		.configurationDisplayName("Routine")
		.description("One of your routines, a tap away. Shows the countdown while it runs.")
		.supportedFamilies([.systemSmall, .systemMedium])
	}
}
