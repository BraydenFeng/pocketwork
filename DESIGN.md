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

## Phone workspace, September 13

Brayden requested a Notion/Obsidian-inspired phone interface and direct home-screen editing. The native direction is a minimal document workspace: cool paper, graphite type, quiet rules, one blue save action. Preserve the original home hierarchy while removing repeated explanations and schema labels. Three repeated structures: a page title with a small document glyph, ruled document rows with separate Edit actions, and a bottom editing bar for adding blocks. New routine opens an unsaved page draft. Cancel discards it; Save validates and stores it. Home allowance editing preserves its daily/shared-window semantics. App groups expose a direct Choose apps action and visible permission errors.


Phone editing follow-up: Edit opens the actual routine page in place. Preserve its heading rail, timer and counter cards, checklist rows, and note typography. Text becomes editable where it already lives; only configuration controls replace live actions. A quiet bottom bar offers Cancel, Add block, and behavior settings. Save returns to the same running page. Home allowances likewise keep their existing page and edit budgets inside its schedule cards. No block list or separate inspector is the default editing destination.


## Connected logic workspace

Brayden selected a Supabase-diagram-like node canvas alongside the Page view. Repeat three structures: compact node cards with labelled input/output ports, graphite connection wires with one selected accent, and a separate inspector for node settings. Node positions are workspace geometry; connections translate into the existing executable native routine schema. Unsupported combinations must fail explicitly rather than imply arbitrary code execution. Keep Page and Logic visibly accessible for home allowances as well as ordinary routines. Native capability boundaries remain visible, and draft graphs require Apply before their rules sync.
