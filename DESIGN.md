# Pocketwork — interface brief

## October 2: page tiles, routines over data

Brayden rejected the October 1 Routines/Data tabs the same day. The phone home is My pages again, drawn as a grid of page tiles (name and a one-line status); tapping a tile opens the page. Inside a page, the description and headings come first, then a Routines section and then a Data section. Routines are compact rows: a timer with Start/Stop, a schedule or home allowance with its switch, and app blocking, plus Add routine; tapping a routine opens the page editor. Data holds checklists, counters, notes, and history: the page's own focus minutes for 14 days, or the allowance's usage against its budget with Diagnostics. Connected logic splits the same way, with controls under Routines and values, logs, and charts under Data. Edit still turns the whole page into the block editor.

## October 1: phone tabs (superseded October 2)

Brayden asked for the iPhone app to split into two tabs, Routines and Data. Routines lists each routine as one row: a switch for routines that enforce themselves (schedules and the home allowance), Start/Stop for timer routines, and nothing for plain pages. Tapping a row opens the routine in edit mode; Cancel or Save returns to its live page. Data is read-only and shows what the phone has recorded: home allowance minutes against budget and focus-session minutes, each for the last 14 days. App groups stay under Routines. A block-authored home allowance no longer shows its compiled graph as a second live panel on the phone, and the Home allowance page has a Diagnostics section listing the engine's recent decisions so missed minutes can be traced on a device.

## September 27: one page, no graph

Brayden rejected the remaining node canvas, Connections workflow, and separate Routines/Data tabs. The web creator is now one Notion-like document. A page contains its content, routines, and data in a single vertical flow. The saved graph may remain an internal runtime format, but the interface must never ask a person to place nodes, draw wires, open advanced wiring, or save connections.

The tone stays editorial minimalism. The creator should feel like writing and arranging a small personal tool, not programming a workflow diagram. Blocks are added from the page or with `/`, edited in place, and saved automatically as soon as their required properties are complete. References between blocks appear as ordinary sentence-like properties such as “When,” “Use value from,” or “Show entries from.”

Home allowance is a native routine inside this same page structure, not a separate editor. Its location and allowance controls appear as the first routine block, while the page still exposes PAGE, ROUTINES, and DATA sections for adding content, automations, variables, logs, and displays. Its required schedule and Screen Time storage blocks stay internal so the page does not show duplicate controls.

Conditional flow is an ordinary Routine block named “If.” It starts with one condition and one “Then” path. Else is absent by default; a quiet “+ Add else” action inside the expanded block reveals the false path only when someone needs it. Removing Else also removes its outgoing connections after confirmation. The interface never asks users or agents to edit graph nodes. The MCP creates and edits pages through the same picker catalog and block operations as the visual builder, not through raw documents, graphs, or private presets.

Home allowance can also be authored from the ordinary low-level blocks. A page made from At location, Time window, App usage, Compare, Both/Either conditions, and Control app access is compiled into the existing native background allowance engine when it forms a complete home-only daily allowance. Those visible blocks remain the source of truth; the generated schedule and Screen Time blocks stay internal. Incomplete or unsupported combinations must remain foreground-only or fail validation instead of quietly pretending to run in the background.

Repeating work is an ordinary Routine event named “Every.” Its expanded row reads as one sentence: Every [number] [minutes / hours / days]. It exposes one “every interval” event that can feed any action, without inventing a special reminder or tracker workflow. The first interval starts when the page runs; a missed interval produces one event when the page is opened again, never a burst of catch-up events. Because arbitrary custom actions cannot execute on a closed iPhone page, the block says this directly beside its settings. Format 5 keeps these pages local until the compatible phone build is released.

Three signature moves: the document glyph and editable title; small PAGE / ROUTINES / DATA section labels within one continuous page; and expandable block rows whose properties sit directly beneath the block. There is no editor-mode tab bar and no graph deep link. Native presets and foreground-only blocks keep their capability notes, but those notes are secondary to the thing being built.

## September 20: primitives before recipes

Block descriptions should be short and literal: "Stopwatch or countdown", "Store a number", "Active between two times". Brayden rejected explanatory filler and contrast phrases such as "not a blocker". Name integrations plainly, such as "Apple Screen Time integration", and explain their actual data limits in settings.

Brayden approved independent building blocks, not renamed high-level features. The primary picker offers a general Timer, named Variables, Change variable actions, Time windows, measured App usage, Records, calculations, and displays. Existing focus/blocking combinations remain explicitly labelled presets for compatibility. Nothing silently connects a new general timer to app blocking. Award screen time remains a legacy option, not the model for new systems.

Keep the document-first structure and tokens above the abstraction change. Three recurring details: named variable destinations instead of IDs; value fields that clearly choose a fixed number or connected source; and compact live timer/variable readouts in Preview. Preview inputs never alter account or phone state. Show format-4/native-update requirements and the foreground runtime boundary. Test both a timer-to-app-gate connection and a user-defined allowance changed by a button, calculated against measured usage, and displayed independently.

## Web creation, September 19: document first

Brayden rejected the three-panel workbench as clunky and requested a Notion-like creation process. This supersedes the old workbench and advanced logic canvas while preserving the saved document format.

The tone is editorial minimalism: a quiet, left-aligned document, editable title, readable blocks, and generous space around the page. Reuse Pocketwork's existing paper, graphite, typography, and tokens. The original home remains the visual reference; do not redesign it or change native enforcement.

Three signature moves: a small document glyph above the editable title; a narrow gutter with insertion and block actions; and compact, human-readable controls inside the timer, schedule, and app-blocking blocks. No permanent library, inspector, device bezel, onboarding wizard, node canvas, or advanced wiring destination. Add block and slash search share one keyboard-accessible picker. Preview is a deliberate secondary destination. Routine edits save automatically with explicit local/sync/error states. Preview never activates a real scheduled routine.

Creation opens an empty text block, not sample motivational content. Text, tasks, numbers, and times are edited where they appear. Dependent native blocks are inserted together so ordinary creation never requires wiring a graph. Existing rules and connected behaviors must survive edits; invalid drafts never replace the saved routine. Test against the original home palette and this single-column document structure at desktop, tablet, and phone widths.

Brayden's subsequent clarification: the page also contains controls and visualizations. Named source properties and expandable block settings express relationships without a separate Connections view. Forms can record entries; charts, tables, and progress displays use the same existing behavior schema as MCP and the native runner. Native timer/schedule enforcement and foreground-only behaviors must be labelled separately. This web editing change does not claim arbitrary background execution, cross-routine data references, or a new native release.

## What this product is

A person assembles a personal iPhone tool from supported native blocks, sees exactly what it does in a live preview, and exports a configuration for the native host. This is a tool, not a marketing document.

## Tone

Editorial utility page: quiet paper, graphite structure, compact controls, and a deliberate preview. Precise and approachable; no fake analytics or decorative dashboards.

## Constraints

Next.js App Router and TypeScript editor; SwiftUI native host. Desktop and narrow screens use the same continuous document with responsive gutters. Accessible names, visible keyboard focus, 14px application body, reduced motion support. The browser simulates native restrictions and must never claim it is actually blocking apps.

## The one memorable thing

A personal app reads like a short document: content, routines, and data in one editable page instead of code or a workflow diagram.

## Three signature moves

1. PAGE / ROUTINES / DATA labels divide one continuous document without creating separate modes.
2. Every native capability has a plain-language availability note; preview and device are visibly different states.
3. Expanded blocks reveal short, sentence-like properties in place; incomplete blocks remain visible without replacing the saved page.

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

Pages are the saved workspaces. Each page holds routines (actions, controls, and conditions) and data (values, records, and displays). Show Page, Routines, and Data as sections in the same document, not separate views. Blocks can reference one another through named properties. Preserve the original home layout and existing paper/graphite tokens.

Launch assumption: three free pages at a time; free MCP and sync. Pro raises the page allowance, not Screen Time permissions. Existing pages remain accessible after cancellation. Account, privacy, support, and terms use the same ruled document layout and existing controls. Show missing launch configuration honestly; never offer a purchase before a StoreKit product loads. Page-limit monetization still requires App Review assessment.

QA: review accessible structure and named controls, then desktop, 768px, and 375px screenshots. Reuse existing measured AA text/surface tokens and keep design lint passing. Account empty state and legal-page layouts are browser-verified; authenticated purchase/deletion device screens still require signed-device testing.

## Front door

My pages comes before the editor. A person sees only their saved pages and a New page action that opens a blank document. The ready-made routine catalog was removed at Brayden’s request on 2026-09-13. Pages are named for their purpose, not their blocks. The browser back button always returns to the list.

## First-use guidance

Keep guidance inside the page editor, not in a separate onboarding wizard. A dismissible, replayable guide can lead from adding the first block to previewing it and understanding iPhone setup. It never replaces a saved page or claims that visiting a step completes it. Use literal labels and keep editing in the document at every width.

## Done for this slice

My pages home with duplicate, delete, and import; editable blocks and rules; interactive preview; persisted drafts; undo/redo; validated JSON import/export; native file import and permission-aware session runner; isolated tests; production web build; design lint; browser checks. Native device verification remains explicitly pending on Windows.

## Phone workspace, September 13

Brayden requested a Notion/Obsidian-inspired phone interface and direct home-screen editing. The native direction is a minimal document workspace: cool paper, graphite type, quiet rules, one blue save action. Preserve the original home hierarchy while removing repeated explanations and schema labels. Three repeated structures: a page title with a small document glyph, ruled document rows with separate Edit actions, and a bottom editing bar for adding blocks. New routine opens an unsaved page draft. Cancel discards it; Save validates and stores it. Home allowance editing preserves its daily/shared-window semantics. App groups expose a direct Choose apps action and visible permission errors.


Phone editing follow-up: Edit opens the actual routine page in place. Preserve its heading rail, timer and counter cards, checklist rows, and note typography. Text becomes editable where it already lives; only configuration controls replace live actions. A quiet bottom bar offers Cancel, Add block, and behavior settings. Save returns to the same running page. Home allowances likewise keep their existing page and edit budgets inside its schedule cards. No block list or separate inspector is the default editing destination.


## Retired graph direction

The September 13 node-canvas direction is historical and must not appear in the web creator. Its typed graph remains an internal storage and runtime representation only. The document editor is the sole creation surface.
