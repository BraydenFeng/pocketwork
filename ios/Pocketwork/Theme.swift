import SwiftUI

// The web editor's tokens (app/tokens.css) carried over: cool near-white ground, hairlines instead of shadows, mono labels, one blue accent.
enum Theme {
	static let bg = Color(red: 0.949, green: 0.953, blue: 0.965)
	static let surface = Color(red: 0.988, green: 0.988, blue: 0.992)
	static let surface_hi = Color(red: 0.925, green: 0.929, blue: 0.945)
	static let border = Color(red: 0.851, green: 0.859, blue: 0.886)
	static let border_hi = Color(red: 0.663, green: 0.675, blue: 0.706)
	static let text = Color(red: 0.137, green: 0.153, blue: 0.188)
	static let text_dim = Color(red: 0.322, green: 0.341, blue: 0.376)
	static let text_faint = Color(red: 0.427, green: 0.443, blue: 0.478)
	static let accent = Color(red: 0.145, green: 0.373, blue: 0.702)
	static let danger = Color(red: 0.655, green: 0.196, blue: 0.157)
	static let success = Color(red: 0.204, green: 0.514, blue: 0.376)
	static let warning = Color(red: 0.702, green: 0.435, blue: 0.098)

	static let radius: CGFloat = 10
	static let radius_small: CGFloat = 4
	static let pad: CGFloat = 16
	static let gap: CGFloat = 12
}

// Small uppercase mono label with an optional number, like "01 · MY ROUTINES" on the web.
struct SectionLabel: View {
	var number: String? = nil
	let text: String
	var body: some View {
		HStack(spacing: 8) {
			if let number { Text(number).foregroundStyle(Theme.text_faint); Rectangle().fill(Theme.border).frame(width: 1, height: 10) }
			Text(text.uppercased()).foregroundStyle(Theme.text_faint)
		}
		.font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.2)
	}
}

struct Card<Content: View>: View {
	var tinted = false
	var dashed = false
	@ViewBuilder let content: Content
	var body: some View {
		content
			.padding(Theme.pad)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(tinted ? Theme.surface_hi : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
			.overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: dashed ? [4, 4] : [])))
	}
}

struct Hairline: View {
	var body: some View { Rectangle().fill(Theme.border).frame(height: 1) }
}

// Buttons: primary (dark, like the preview's Start focusing), accent (blue, like Use this routine), quiet (hairline).
struct PrimaryButtonStyle: ButtonStyle {
	var accent = false
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.system(size: 15, weight: .medium))
			.padding(.vertical, 12).padding(.horizontal, 16)
			.frame(maxWidth: .infinity)
			.background(accent ? Theme.accent : Theme.text, in: RoundedRectangle(cornerRadius: Theme.radius_small))
			.foregroundStyle(Theme.surface)
			.opacity(configuration.isPressed ? 0.85 : 1)
	}
}

struct QuietButtonStyle: ButtonStyle {
	var danger = false
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.system(size: 13, weight: .medium))
			.padding(.vertical, 8).padding(.horizontal, 12)
			.background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius_small))
			.overlay(RoundedRectangle(cornerRadius: Theme.radius_small).strokeBorder(configuration.isPressed ? Theme.border_hi : Theme.border))
			.foregroundStyle(danger ? Theme.danger : Theme.text)
	}
}

struct TextButtonStyle: ButtonStyle {
	var danger = false
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.system(size: 13, weight: .medium))
			.foregroundStyle(danger ? Theme.danger : Theme.text_dim)
			.opacity(configuration.isPressed ? 0.6 : 1)
	}
}

// A labelled text field drawn like the web's .field: hairline box on the surface.
struct Field<Content: View>: View {
	let label: String
	@ViewBuilder let content: Content
	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text_dim)
			content
				.font(.system(size: 15))
				.padding(.horizontal, 12).frame(minHeight: 40)
				.background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius_small))
				.overlay(RoundedRectangle(cornerRadius: Theme.radius_small).strokeBorder(Theme.border))
		}
	}
}

// A switch row drawn like the web's .toggle-row.
struct ToggleRow: View {
	let title: String
	var description: String? = nil
	@Binding var is_on: Bool
	var disabled = false
	var body: some View {
		HStack(alignment: .center, spacing: 12) {
			VStack(alignment: .leading, spacing: 2) {
				Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text)
				if let description { Text(description).font(.system(size: 12)).foregroundStyle(Theme.text_faint) }
			}
			Spacer()
			Toggle(title, isOn: $is_on).labelsHidden().tint(Theme.success).disabled(disabled)
		}
		.padding(.vertical, 8)
		.opacity(disabled ? 0.55 : 1)
	}
}

// Screen scaffolding shared by every page: the ground color and a surface navigation bar with hairline.
struct Page: ViewModifier {
	func body(content: Content) -> some View {
		content
			.background(Theme.bg.ignoresSafeArea())
			.toolbarBackground(Theme.surface, for: .navigationBar)
			.toolbarBackground(.visible, for: .navigationBar)
			.toolbarColorScheme(.light, for: .navigationBar)
			.tint(Theme.text)
	}
}

extension View {
	func page() -> some View { modifier(Page()) }
	func heading_font(_ size: CGFloat = 20) -> some View { font(.system(size: size, weight: .semibold)).tracking(-0.4).foregroundStyle(Theme.text) }
	func supporting() -> some View { font(.system(size: 13)).foregroundStyle(Theme.text_faint) }
	func mono_caption() -> some View { font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Theme.text_dim) }
}

struct DocumentHeading: View {
	let title: String
	var subtitle: String? = nil
	var icon = "doc.text"
	var body: some View {
		VStack(alignment: .leading, spacing: Theme.gap) {
			Image(systemName: icon).font(.system(size: 26, weight: .light)).foregroundStyle(Theme.text_dim)
			Text(title).heading_font(30)
			if let subtitle { Text(subtitle).supporting().fixedSize(horizontal: false, vertical: true) }
		}.frame(maxWidth: .infinity, alignment: .leading)
	}
}

struct DocumentRow<Content: View>: View {
	let icon: String
	@ViewBuilder let content: Content
	var body: some View {
		HStack(alignment: .top, spacing: Theme.gap) {
			Image(systemName: icon).font(.system(size: 17, weight: .regular)).foregroundStyle(Theme.text_faint).frame(width: 24, height: 24)
			content.frame(maxWidth: .infinity, alignment: .leading)
		}.padding(.vertical, Theme.gap).contentShape(Rectangle())
	}
}

struct EditorBar<Content: View>: View {
	@ViewBuilder let content: Content
	var body: some View {
		VStack(spacing: 0) {
			Hairline()
			HStack(spacing: Theme.gap) { content }.padding(.horizontal, Theme.pad).frame(minHeight: 56)
		}.background(Theme.surface)
	}
}

extension View {
	func paper_page() -> some View {
		background(Theme.surface.ignoresSafeArea()).toolbarBackground(Theme.surface, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar).toolbarColorScheme(.light, for: .navigationBar).tint(Theme.text)
	}
}
