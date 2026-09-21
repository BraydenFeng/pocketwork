# Pocketwork — interface brief

## September 20: primitives before recipes

Block descriptions should be short and literal: "Stopwatch or countdown", "Store a number", "Active between two times". Brayden rejected explanatory filler and contrast phrases such as "not a blocker". Name integrations plainly, such as "Apple Screen Time integration", and explain their actual data limits in settings.

Brayden approved independent building blocks, not renamed high-level features. The primary picker offers a general Timer, named Variables, Change variable actions, Time windows, measured App usage, Records, calculations, and displays. Existing focus/blocking combinations remain explicitly labelled presets for compatibility. Nothing silently connects a new general timer to app blocking. Award screen time remains a legacy option, not the model for new systems.

Keep the document-first structure and tokens above the abstraction change. Three recurring details: named variable destinations instead of IDs; value fields that clearly choose a fixed number or connected source; and compact live timer/variable readouts in Preview. Preview inputs never alter account or phone state. Show format-4/native-update requirements and the foreground runtime boundary. Test both a timer-to-app-gate connection and a user-defined allowance changed by a button, calculated against measured usage, and displayed independently.

## Web creation, September 19: document first

Brayden rejected the three-panel workbench as clunky and requested a Notion-like creation process. This supersedes the workbench layout below for the default web editor, not its saved document format or the advanced logic canvas.

The tone is editorial minimalism: a quiet, left-aligned document, editable title, readable blocks, and generous space around the page. Reuse Pocketwork's existing paper, graphite, typography, and tokens. The original home remains the visual reference; do not redesign it or change native enforcement.

Three signature moves: a small document glyph above the editable title; a narrow gutter with insertion and block actions; and compact, human-readable controls inside the timer, schedule, and app-blocking blocks. No permanent library, inspector, device bezel, onboarding wizard, or node canvas in the creation view. Add block and slash search share one keyboard-accessible picker. Preview and advanced logic are deliberate secondary destinations. Routine edits save automatically with explicit local/sync/error states. Preview never activates a real scheduled routine.

Creation opens an empty text block, not sample motivational content. Text, tasks, numbers, and times are edited where they appear. Dependent native blocks are inserted together so ordinary creation never requires wiring a graph. Existing rules and connected behaviors must survive edits; invalid drafts never replace the saved routine. Test against the original home palette and this single-column document structure at desktop, tablet, and phone widths.

Brayden's subsequent clarification: the page also contains connected controls and visualizations. The default Connections view uses named sources, typed input pickers, and expandable block settings instead of ports and wires. Forms can record entries; charts, tables, and progress displays use the same existing behavior schema as MCP and the native runner. Advanced wiring stays available. Native timer/schedule enforcement and foreground-only connected behaviors must be labelled separately. This web editing change does not claim arbitrary background execution, cross-routine data references, or a new native release.

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

## Launch model, September 20

Pages are the saved workspaces. Each page holds routines (actions, controls, and conditions) and data (values, records, and displays). Show Page, Routines, and Data as three views of the same document, not three disconnected editors. Sources can connect across these views. Preserve the original home layout and existing paper/graphite tokens.

Launch assumption: three free pages at a time; free MCP and sync. Pro raises the page allowance, not Screen Time permissions. Existing pages remain accessible after cancellation. Account, privacy, support, and terms use the same ruled document layout and existing controls. Show missing launch configuration honestly; never offer a purchase before a StoreKit product loads. Page-limit monetization still requires App Review assessment.

QA: reviewed accessible structure and named controls, then desktop, 768px, and 375px screenshots. Reused existing measured AA text/surface tokens; design lint passes. Removed repeated rollout wording from the connection panel after narrow-screen review. Account empty state and legal-page layouts are browser-verified; authenticated purchase/deletion device screens still require signed-device testing.

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

## Behavior library organization

Brayden requested less clutter and room for future data features on 2026-09-13. Show four collapsed sections: Time & location, Data, Logic, Actions. Search opens matching groups. Entries are compact names; descriptions belong in node settings. New nodes occupy free canvas space. Keep the graph, settings and optional Test logic distinct. Version-3 behaviors currently execute while a routine is open; do not imply arbitrary background execution or cloud-synced progress.


## Native connected editor

The iPhone Page editor opens a full-screen Logic workspace. Keep the original page appearance and use the existing paper, graphite, hairline and blue tokens. A bottom Add block action opens collapsed Time & location, Data, Logic and Actions groups. The canvas pans in both directions and has explicit zoom controls; node headings drag while 44-point ports open a compatible-connection picker. Find a block jumps through larger graphs. Settings use a sheet so the small screen does not carry desktop sidebars. Apply returns the graph to the page draft; Save uses the existing validated cloud save. Back confirms discarding graph changes. Invalid connections, cycles and incomplete graphs cannot overwrite the saved routine. New behaviors retain their foreground execution limits.
