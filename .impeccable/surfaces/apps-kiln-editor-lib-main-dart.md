---
version: 1
slug: "apps-kiln-editor-lib-main-dart"
primary_target: "apps/kiln_editor/lib/main.dart"
related_targets: ["apps/kiln_editor/lib/panels.dart"]
---

# Kiln Editor shell

Scope: the whole editor app (toolbar, hierarchy, scene view, inspector, dialogs, empty and play states). Mode: Operate.
Audience/job: open-source Flutter/Flame developers composing scenes in long sessions beside a dark IDE.
Pinned constraints: keep the Unity layout (hierarchy left, scene centre, inspector right); it must never read as a toy. Dark ground.
Chosen direction: Counter Sheet (code-led). Memorable moment: behaviors as die-cut counters with a factor strip.

## Direction contract

THESIS: Every behavior is a die-cut counter placed on an entity, its key factors printed on its face. Refuses the category's flat grey panels with blue selection and generic "component" accordions.

OWN-WORLD: Eleven-step olive-tinted neutral ramp (map board) as the only greys. Four family colours: render khaki, input field-grey blue, logic rust, physics olive. Marker yellow for selection and Play only. Condensed tabular numerals for labels, a plain grotesk for values. One text size inside panels; rank comes from weight, case and rules. Square 2–3px corners, 1px rules, and one connector style for action chains.

STORY: The developer sees at a glance what each entity is made of (counter stripes in the hierarchy), edits values fast, and plays without the view jumping.

FIRST VIEWPORT:
- 44px toolbar: text buttons, a yellow Play, and the project / file breadcrumb with a dirty dot.
- 248px hierarchy: code column E1…, family stripes per row, and the selection marked by a yellow inset bar.
- Centre map board: dotted grid with the scene framed at fit scale. The selection gets yellow corner tabs and a code tag.
- 340px inspector: a transform grid, then a stack of behavior counters. Each counter has a family field, an uppercase name and a factor strip. Action cases are numbered 4.1, 4.2.

FORM: Hex-and-counter wargame component sheets, position 5 of 7 on the ordered list. seed: none (unavailable)

Raises:
- tonal discipline (Exposure Record)
- one text size (Timetable)
- edit/play registration (Botanical Folio)
- shared entity codes (Circle Catalog)
- one connector grammar (Transit)

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
