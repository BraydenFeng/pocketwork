# Pocketwork — interface brief

## What this product is

A person assembles a personal iPhone tool from supported native blocks, sees exactly what it does in a live preview, and exports a configuration for the native host. This is a tool, not a marketing document.

## Tone

Compact industrial workbench, selected by Brayden: light canvas, component library, live iPhone preview. Quiet, precise, and approachable; no fake analytics or decorative dashboards.

## Constraints

Next.js App Router and TypeScript editor; SwiftUI native host. Desktop uses a library/canvas/inspector arrangement. Narrow screens stack the same regions. Accessible names, visible keyboard focus, 14px application body, reduced motion support. The browser simulates native restrictions and must never claim it is actually blocking apps.

## The one memorable thing

A small, live personal app sits beside its human-readable behavior recipe, like a tool on a workbench rather than code in an IDE.

## Three signature moves

1. Numbered ruled section rails: BUILD / BEHAVIOR / DEVICE, with consistent small uppercase labels and a fixed glyph column.
2. Every native capability has a plain-language availability note; preview and device are visibly different states, never a misleading permission checkbox.
3. A restrained device bezel anchors the live preview; selected blocks gain a single structural side rule, mirrored by the inspector heading.

## Skin

- Typeface: locally installed Bahnschrift for headings, Segoe UI for controls, Consolas for runtime digits; weights 400/500/600.
- Ground: cool near-white with blue-tinted graphite rules and text, not pure white or black.
- Accent: oklch(0.47 0.16 252), reserved for the primary action and selected editor mode.
- Native preview inherits the same hierarchy with larger touch controls, not a miniature desktop panel.

## Hard rules

- Values live in tokens.css; components compose shared primitives.
- Hairlines and surface steps, no decorative shadows or gradients.
- Three structural radii plus the device bezel; pill reserved for state indicators.
- No AI inference, telemetry, or payment collection. Accounts sync personal routines.
- The imported document is strictly validated data, not executable code.

## Front door

My tools comes before the workbench. A person sees only their saved routines as cards and a New routine action that opens a blank editor. The ready-made routine catalog was removed at Brayden’s request on 2026-09-13. Routines are named for the outcome (Deep work, Phone-free bedtime), not the blocks, and every one enforces something rather than only tracking it. Cards say what a tool does in one mono line (25 min session, blocks apps, 3 tasks). The browser back button always returns to the list.

## First-use guidance

Keep the existing workbench, not a separate onboarding wizard. A dismissible, replayable three-step guide leads from customizing the current draft to testing it and understanding iPhone setup. It never replaces a saved tool or claims that visiting a step completes it. Use literal labels and show edit/test instructions beside the preview. On stacked layouts, selecting a block takes the user to its settings with a direct route back to the preview.

## Done for this slice

My tools home with routines, duplicate, delete, and import; editable blocks and rules; interactive preview; persisted drafts; undo/redo; validated JSON import/export; native file import and permission-aware session runner; isolated tests; production web build; design lint; browser checks. Native device verification remains explicitly pending on Windows.
