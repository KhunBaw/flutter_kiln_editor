---
name: Kiln Editor
description: A dark, olive-tinted desktop scene editor for Flame, where each behavior is a printed counter on a map board.
colors:
  z0: "#0F110E"
  z1: "#161814"
  z2: "#1D1F1A"
  z3: "#252821"
  z4: "#30332B"
  z5: "#3D4137"
  z6: "#50554A"
  z7: "#6A6F62"
  z8: "#8E9286"
  z9: "#BDBFB4"
  z10: "#E8E6DC"
  mark: "#E9C548"
  danger: "#E0775A"
  family-render: "#C9B57A"
  family-input: "#7C93A8"
  family-logic: "#C96A42"
  family-physics: "#8B9958"
typography:
  head:
    fontFamily: "Barlow Semi Condensed, Barlow, sans-serif"
    fontSize: "13px"
    fontWeight: 700
    letterSpacing: "1.3px"
  label:
    fontFamily: "Barlow Semi Condensed, Barlow, sans-serif"
    fontSize: "13px"
    fontWeight: 600
    letterSpacing: "0.9px"
  code:
    fontFamily: "Barlow Semi Condensed, Barlow, sans-serif"
    fontSize: "13px"
    fontWeight: 600
    fontFeature: "\"tnum\""
  body:
    fontFamily: "Barlow, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.385
  value:
    fontFamily: "Barlow, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    fontFeature: "\"tnum\""
rounded:
  stripe: "1px"
  sm: "2px"
  counter: "3px"
spacing:
  xxs: "4px"
  xs: "6px"
  sm: "8px"
  md: "10px"
  panel: "12px"
  lg: "24px"
  board: "40px"
components:
  toolbar:
    backgroundColor: "{colors.z0}"
    height: "44px"
    padding: "0 8px"
  button-text:
    textColor: "{colors.z9}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "0 10px"
    height: "28px"
  button-text-disabled:
    textColor: "{colors.z6}"
  button-play:
    backgroundColor: "{colors.mark}"
    textColor: "{colors.z1}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "0 12px"
    height: "28px"
  button-stop:
    textColor: "{colors.danger}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "0 12px"
    height: "28px"
  button-icon:
    textColor: "{colors.z8}"
    rounded: "{rounded.sm}"
    size: "28px"
  panel-header:
    textColor: "{colors.z9}"
    typography: "{typography.head}"
    height: "34px"
    padding: "0 6px 0 12px"
  hierarchy-row:
    textColor: "{colors.z10}"
    typography: "{typography.body}"
    height: "30px"
    padding: "0 12px"
  hierarchy-row-hover:
    backgroundColor: "{colors.z3}"
  hierarchy-row-selected:
    backgroundColor: "{colors.z4}"
    textColor: "{colors.z10}"
  family-stripe:
    rounded: "{rounded.stripe}"
    width: "6px"
    height: "14px"
  input-field:
    backgroundColor: "{colors.z1}"
    textColor: "{colors.z10}"
    typography: "{typography.value}"
    rounded: "{rounded.sm}"
    padding: "7px 8px"
  counter-head:
    backgroundColor: "{colors.z1}"
    textColor: "{colors.z10}"
    typography: "{typography.head}"
    rounded: "{rounded.counter}"
    height: "34px"
  counter-family-field:
    textColor: "{colors.z1}"
    typography: "{typography.head}"
    width: "30px"
  factor-strip:
    textColor: "{colors.z10}"
    typography: "{typography.code}"
    padding: "0 10px"
  counter-body:
    backgroundColor: "{colors.z1}"
    padding: "10px 10px 4px 10px"
  selection-tag:
    backgroundColor: "{colors.mark}"
    textColor: "{colors.z1}"
    typography: "{typography.head}"
    height: "20px"
    padding: "0 6px"
  add-frame:
    textColor: "{colors.z8}"
    typography: "{typography.label}"
    rounded: "{rounded.counter}"
    height: "30px"
  dialog:
    backgroundColor: "{colors.z2}"
    textColor: "{colors.z10}"
    typography: "{typography.body}"
    rounded: "{rounded.sm}"
  tooltip:
    backgroundColor: "{colors.z0}"
    textColor: "{colors.z10}"
    typography: "{typography.body}"
    rounded: "{rounded.sm}"
  popup-menu:
    backgroundColor: "{colors.z0}"
    textColor: "{colors.z10}"
    typography: "{typography.body}"
    rounded: "{rounded.sm}"
    padding: "4px 0"
  snackbar:
    backgroundColor: "{colors.z4}"
    textColor: "{colors.z10}"
    typography: "{typography.body}"
    rounded: "{rounded.sm}"
    width: "420px"
---

# Design System: Kiln Editor

## Overview

**Creative North Star: "The Counter Sheet"**

Kiln Editor is a wargame component sheet laid on a matte map board. Every behavior attached to an entity is a die-cut counter: a solid family field carrying one letter, the behavior name in condensed capitals, and a ruled factor strip printed with the counter's key numbers. Entities carry short codes (`SC`, `E1`, `E2`…) shared between the hierarchy, the scene marker and the inspector header, so one item is addressed the same way everywhere. Everything lives in `apps/kiln_editor/lib/theme.dart`: the `Z` neutral ramp, the `Family` enum, the `T` text styles, and `kilnTheme()`.

The surface is dense and quiet. It is built for long sessions next to a dark IDE: an eleven-step olive-tinted ramp supplies every grey, one 13px size carries all text, and rank comes from weight, case, condensed width and 1px rules. Colour is reserved. Four muted family hues identify what an entity is made of, and one marker yellow points at what is selected or live. The Unity layout is kept intact: hierarchy left, scene centre, inspector right.

Edit and Play share one `SceneFrame`, so pressing Play swaps the game in place at the same fit scale without moving the board.

**Key Characteristics:**
- Olive-tinted map-board neutrals (`Z.z0`–`Z.z10`) are the only greys.
- One text size (13px). Hierarchy comes from weight, case, condensed width and rules.
- Behaviors render as counters with a family field, an uppercase name and a factor strip.
- Marker yellow (`Z.mark`) marks selection and live state. It is never decoration.
- Square 2–3px corners, 1px rules, flat surfaces, and no authored shadows.
- A dotted map board frames the scene at fit scale in both Edit and Play.

## Colors

The palette is a warm olive-grey night with four faded print inks and one marker yellow.

### Primary
- **Marker Chit Yellow** (`Z.mark`): the selection and live-state colour. It is used for the Play button fill, the 3px inset bar on the selected hierarchy row and its code, the scene selection rule, corner tabs and code tag, the inspector's entity code, action case numbers (`4.1`), the dirty dot, the focused input border, the text cursor, selection highlight (32% alpha) and the checked checkbox fill. It maps to `ColorScheme.primary`.

### Secondary
- **Render Khaki** (`Family.render`): the counter field and hierarchy stripe for Shape, Sprite, Text and Tween.
- **Field-Grey Blue** (`Family.input`): used for OnTap.
- **Logic Rust** (`Family.logic`): used for Timer, Spawner, Condition and Prefab.
- **Physics Olive** (`Family.physics`): used for Collider and OnCollide.
- **Custom** (`Family.custom`, reuses `Z.z8`): used for any app-registered type. A custom type gets a neutral field rather than a new hue.

### Tertiary
- **Burnt Signal** (`Z.danger`): used for the Stop button (outline and text), the Discard dialog action and the input error border. It maps to `ColorScheme.error`.

### Neutral
- **Board Black** (`Z.z0`): the toolbar, the scene map board, tooltips, popup menus and dropdown menus.
- **Sheet Black** (`Z.z1`): the scaffold, input fill, counter head and body, and dark text on yellow or family fields.
- **Panel Olive** (`Z.z2`): the hierarchy and inspector panels and dialogs (`ColorScheme.surface`).
- **Rule Olive** (`Z.z3`): dividers, header and toolbar bottom rules, board dots and row hover.
- **Edge Olive** (`Z.z4`): input, counter and dialog outlines, toolbar separators, the selected-row fill, button overlays and the snackbar.
- **Frame Olive** (`Z.z5`): the scene frame border, the action connector rule and the scrollbar thumb.
- **Muted Olive** (`Z.z6`): disabled button text, the checkbox outline, the colour-swatch border, the hovered scrollbar and the breadcrumb slash.
- **Hint Olive** (`Z.z7`): input hint text.
- **Label Grey** (`Z.z8`): labels, codes, icons, empty-state copy and the project name in the breadcrumb.
- **Head Bone** (`Z.z9`): panel headers, section rules and text-button labels.
- **Bone** (`Z.z10`): body text, values, counter names and the file name.

### Named Rules
**The Map-Board Rule.** Every grey comes from `Z`. No `Colors.grey`, no Material neutrals, no ad-hoc hex.

**The Marker Rule.** `Z.mark` means "this one" or "live now": selection, Play, focus, unsaved and the codes that address the selected item. It is never used for decoration, headers or section accents.

**The Ink-Per-Family Rule.** A family hue appears only as a counter field, a hierarchy stripe or an add-menu stripe. It does not tint text or backgrounds.

## Typography

**Label/Head Font:** Barlow Semi Condensed (Dart family `BarlowSemiCondensed`; bundled weights 500/600/700)
**Body/Value Font:** Barlow (bundled weights 400/500/600)

Both are bundled under SIL OFL in `apps/kiln_editor/assets/fonts/` and declared in `pubspec.yaml`. `ThemeData.fontFamily` is `Barlow`.

**Character:** a condensed grotesk does the printing on counters and rules. A plain grotesk carries what the user types. Tabular figures keep columns of numbers steady.

### Hierarchy
- **Head** (`T.head`, 700, 13px, +1.3 tracking, uppercase in use): panel headers, section rules, counter names, the breadcrumb, the dialog title and the selection tag.
- **Label** (`T.label`, 600, 13px, +0.9 tracking, uppercase in use): field labels (74px column), text buttons, add-frame labels and the board caption (`SCENE · 400 × 700 · 82%`).
- **Code** (`T.code`, 600, 13px, tabular): entity codes (`E1`), action case numbers and scene size. Set at 700 in `Z.z10`, it is the factor strip.
- **Body** (`T.body`, 400, 13px, 18px line): names, menus, tooltips, snackbars, dialog content and empty states. Set at 600 for the scene row name and action type names.
- **Value** (`T.value`, 400, 13px, tabular): every `TextField` and dropdown value.

### Named Rules
**The One-Size Rule.** All text inside the editor is `T.size` (13px). Rank is made with weight, case, tracking, condensed width and a 1px rule. Never with a larger size.

**The Two-Hands Rule.** Condensed type is for what the editor prints: labels, codes and names. Barlow is for what the user writes, meaning values and names they edit.

## Layout

There are three fixed columns under a 44px toolbar. The hierarchy is 248px, the scene board fills the remaining width, and the inspector is 340px. They are separated by 1px `VerticalDivider`s in `Z.z3`. Panel headers are 34px. Hierarchy rows are 30px with a 30px code column and 14px indent per depth. Inspector content sits in 12px side padding. Fields stack with a 6px bottom gap, and paired fields (`x`/`y`, `w`/`h`) sit in a `_Pair` with a 12px gutter. Counters are separated by 8px. Section rules (`_Rule`) take 14px above and 8px below.

The board (`SceneFrame`) fits the scene with 40px padding on every side and a minimum scale of 0.05. A 1.5px dot is drawn every 24px. The caption sits at 16px from the left and 12px from the bottom. Density is set by `VisualDensity.compact` and `MaterialTapTargetSize.shrinkWrap`. Interactive controls are 28px tall.

## Elevation & Depth

The system is flat and uses tonal layering. Depth is a step on the `Z` ramp: the board (`z0`) sits below the sheet (`z1`), which sits below the panel (`z2`). Edges are 1px rules in `z3`–`z5`. `kilnTheme()` defines no shadows. Overlays (dialog, popup menu, tooltip, snackbar) are separated from the surface by a `z4` outline and a tone change, not by authored elevation. Inspector counter heads stay pinned (`SliverPersistentHeader`, 34px) while their body scrolls, so the family field never scrolls out of view.

### Named Rules
**The Rule-Not-Shadow Rule.** Separation is a 1px line or a ramp step. Do not add `BoxShadow` for depth.

## Shapes

The form language is square and printed. Corners are 2px on buttons, inputs, tooltips, dialogs, menus, snackbars, checkboxes and colour swatches, and 3px on counters and add frames. Family stripes and the scrollbar take 1px. A counter whose body is open rounds only its top corners, and the body closes the shape with left, right and bottom rules. The only round form is the 7px dirty dot. The scene selection is a 1px yellow rule with two 8px square corner tabs (top-left and bottom-right) and a 20px code tag sitting 24px above the box.

## Components

### Buttons
- **Text button** (`TextButton`): a printed command. It uses `T.label` uppercase in `Z.z9`, 10px horizontal padding, 28px minimum height, 2px corners and a `Z.z4` overlay on hover/press. When disabled the text is `Z.z6`. Each toolbar button is wrapped in a `Tooltip` that names its shortcut.
- **Play** (`TextButton.icon`): filled `Z.mark` with `Z.z1` text, a `Z.mark` side, a 16px `play_arrow` and 12px padding. While playing it becomes **Stop**, which is transparent with a `Z.danger` side, `Z.danger` text and a `stop` icon.
- **Icon button** (`IconButton`): a 16px Material icon in `Z.z8` on a 28×28 square with 2px corners and a `Z.z4` overlay. When disabled the icon is `Z.z6`. Every icon button has a tooltip.
- **Add frame** (`_AddButton` / `_AddMenu`): a 30px full-width outlined slot with a 1px `Z.z4` border and 3px corners. It holds a centred 14px `add` icon and an uppercase `T.label`, and its hover fill is `Z.z3`. `_AddMenu` opens a `PopupMenuButton` whose items are sorted by family and each carry a 6×14 family stripe.

### Inputs / Fields
- **Field** (`Field` in `_Labeled`): a 74px uppercase `T.label` column, then a dense `TextField` in `T.value`. The fill is `Z.z1` with a 1px `Z.z4` outline, 2px corners and 7/8px padding. It commits on every valid keystroke.
- **Focus:** the outline turns `Z.mark`. The cursor and selection handles are `Z.mark`.
- **Error:** the outline is `Z.danger`.
- **Choice** (`DropdownButtonFormField`): the same frame, with its menu on `Z.z0`.
- **Bool** (`Checkbox`): a square with 2px corners and a `Z.z6` side. Checked, it fills `Z.mark` with a `Z.z1` check.
- **Colour:** the field is led by an 18px swatch with a `Z.z6` border and 2px corners.
- **Asset:** an image or audio field ends in an `file_upload_outlined` icon button.

### Navigation
- **Toolbar:** a 44px `Z.z0` strip with a `Z.z3` bottom rule. From left to right it holds the text buttons NEW · PROJECT · OPEN · SAVE, then a 1×20 `_Sep` in `Z.z4`, UNDO · REDO, another separator, then Play. After an 18px gap comes the breadcrumb: the project (`Z.z8`), ` / ` (`Z.z6`) and the file name (`Z.z10`), all in `T.head`. The dirty dot follows. Native shortcuts live in a `PlatformMenuBar`.
- **Panel header** (`_Header`): a 34px row with a `Z.z3` bottom rule, an uppercase `T.head` title and trailing actions. The inspector header ends in the selected entity's code in `Z.mark`.
- **Hierarchy row** (`_Row`): 30px tall, with a code column in `T.code`, the name in `T.body` and trailing 6×14 family stripes with 2px gaps. Hover is `Z.z3`. Selected rows take a `Z.z4` fill, a `Z.mark` code and a 3px `Z.mark` inset bar on the left edge. The scene itself is row `SC` and shows its size.

### Behavior Counter (signature)
`_Counter` is the signature component. Its head is a pinned 34px `Material` in `Z.z1` with a `Z.z4` side and 3px corners. It contains:
- a 30px **family field** in the family colour, holding the family letter (`R`/`I`/`L`/`P`/`C`) in `T.head` `Z.z1`
- a 10px gap and the type name, uppercase, in `T.head` `Z.z10`
- the **factor strip**, up to 150px wide with 1px `Z.z4` rules left and right, showing `factorOf()` output in `T.code` 700 `Z.z10` (for example `5s ×1`, `balloon.png`, `0·-850 / 5s`)
- a remove `IconButton`

Tapping the head collapses or expands the counter. The body is a `Z.z1` slab ruled on three sides with 10/10/4px padding, holding the property editors generated from `PropDef`.

### Action Chain
Actions inside a counter sit under a `_Rule` (uppercase `T.head` over a `Divider`). Each case is indented 4px and hangs off one 1px `Z.z5` connector rule on its left with 10px inner padding. Its 28px header row carries the case number (`4.1`) in `T.code` `Z.mark` (34px column), the action type in `T.body` 600 and a remove button.

### Scene Board
`SceneFrame` paints the `_BoardPainter` map board, which is `Z.z0` with `Z.z3` dots every 24px. The scene sits at fit scale inside a 1px `Z.z5` frame, with an uppercase caption: mode · size · scale%. In Edit mode `SceneView` overlays the selection marker: a `Z.mark` 1px rule, two 8px tabs and a `Z.mark` code tag reading `E2 · BALLOON` in `T.head` `Z.z1` (+0.8 tracking). In Play mode the same frame hosts the `GameWidget`.

### Overlays
- **Dialog** (`AlertDialog`): `Z.z2` with a 1px `Z.z4` side and 2px corners. The title is `T.head` in `Z.z10` and uppercase in copy. Actions are text buttons, and a destructive action takes a `Z.danger` foreground.
- **Tooltip:** `Z.z0` with a `Z.z4` border, 2px corners and `T.body`. It appears after a 500ms wait.
- **Popup menu:** `Z.z0` with a `Z.z4` side, 2px corners, 4px vertical padding and 30px items.
- **Snackbar:** floating, 420px wide, `Z.z4` with 2px corners and `T.body`.

## Do's and Don'ts

### Do:
- **Do** take every neutral from `Z` and every behavior hue from `Family.of(type)`.
- **Do** set all text at 13px using `T.head`, `T.label`, `T.code`, `T.body` or `T.value`, and rank it with weight, case and rules.
- **Do** use `T.value` or `T.code` (tabular figures) wherever numbers line up.
- **Do** give every new behavior type a `Family` and a `factorOf()` line so its counter has a printed face.
- **Do** address items by their shared code (`SC`, `E1`…, `4.1`) in every place the item appears.
- **Do** keep corners at 2px (controls, overlays) or 3px (counters, add frames), with 1px rules in `z3`–`z5`.
- **Do** put a `Tooltip` on every icon button and toolbar command.

### Don't:
- **Don't** add a second text size, a larger heading or a display face inside the editor.
- **Don't** use `Z.mark` for decoration, panel accents or headers. It points at the selected or live thing only.
- **Don't** introduce pills, large radii, gradients or `BoxShadow` depth.
- **Don't** tint text or panel backgrounds with family colours.
- **Don't** move the hierarchy, scene and inspector out of their left, centre and right order, and don't let Play resize or re-centre the board.
