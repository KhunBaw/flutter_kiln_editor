---
name: Kiln Editor
description: A dark graphite desktop scene editor for Flame with one ember accent, family-tinted icon chips and a keyframe timeline.
colors:
  z0: "#0D0E11"
  z1: "#121317"
  z2: "#181A1F"
  z3: "#1F2227"
  z4: "#292C33"
  z5: "#353943"
  z6: "#4A505C"
  z7: "#69707E"
  z8: "#8D94A3"
  z9: "#B9BECA"
  z10: "#E8EAF0"
  accent: "#FF7A45"
  danger: "#F2555F"
  family-render: "#6FB1FF"
  family-input: "#5ED6A4"
  family-logic: "#B58CFF"
  family-physics: "#FF8FA8"
  family-motion: "#F2C94C"
typography:
  title: { fontFamily: "Barlow", fontSize: "13px", fontWeight: 600 }
  head: { fontFamily: "Barlow", fontSize: "12px", fontWeight: 600, letterSpacing: "0.2px" }
  label: { fontFamily: "Barlow", fontSize: "12px", fontWeight: 500 }
  body: { fontFamily: "Barlow", fontSize: "12px", fontWeight: 400, lineHeight: 1.33 }
  value: { fontFamily: "Barlow", fontSize: "12px", fontWeight: 400, fontFeature: "\"tnum\"" }
  small: { fontFamily: "Barlow", fontSize: "11px", fontWeight: 500 }
rounded:
  sm: "4px"
  md: "5px"
  lg: "8px"
---

# Design System: Kiln Editor

## Overview

**Creative North Star: "The Kiln Bench"**

A calm graphite workbench with a single ember glowing on whatever you are working on. It replaces the earlier olive "Counter Sheet" (uppercase tracked labels, letter counters, 13px-only) with the grammar professional editors share: sentence-case labels, icon chips, scrubbable number fields, collapsible cards and a bottom timeline. Everything lives in `apps/kiln_editor/lib/`: tokens in `theme.dart` (`Z`, `Family`, `T`, `kilnTheme()`), controls in `widgets.dart`, panels in `panels.dart`, the Inspector in `inspector.dart`, the Timeline in `timeline.dart`.

Layout is Unity-shaped: toolbar on top, Hierarchy + Assets left, Scene centre with the Timeline dock under it, Inspector right (252 / flex / 328px).

## Colors

- **Graphite ramp** `Z.z0`–`Z.z10`: the only greys. Depth is a step on the ramp (board `z0`, sheet `z1`, panel `z2`, card `z3`).
- **Ember** `Z.accent`: selection, focus, Play, the playhead, keys, modified-value dots. `Z.accentDim` (15%) fills selected rows and active icon buttons. Never decoration.
- **Danger** `Z.danger`: Stop, destructive menu items, input errors.
- **Families** (`Family.of(type)`): render blue, input mint, logic violet, physics rose, motion gold, custom grey. A family hue appears only as an icon chip (16% tint behind a full-hue glyph) or a small dot.

**Rule:** no ad-hoc hex and no Material neutrals; every grey comes from `Z`.

## Typography

Barlow only (400/500/600, bundled). Working size 12px, secondary 11px, titles 13px. Sentence case everywhere; no uppercase tracking. Tabular figures on every number (`T.value`, `T.code`).

## Components

- **IconBtn** 28px, 4px radius, hover `z4`, active = ember glyph on `accentDim`. Every one has a tooltip.
- **Cmd** 28px text command, `z3` fill; `primary` = ember fill (Play), `danger` = red tint (Stop).
- **Field** 12px value, `z1` fill, borderless until focus (ember border). Number fields scrub: drag the label (⇧ ×10, ⌥ ÷10). Compact fields carry their label inside; row fields use an 88px label column with a dot and reset button when the value differs from its default.
- **Seg** segmented control for ≤3 short options, otherwise a popup dropdown. **Toggle** 30×16 switch.
- **Colour** swatch opens a popover: saturation/value square, hue and alpha strips, hex, swatches.
- **Behavior card** (`z3`, 8px radius, `z4` border): chevron, family chip, name, dim summary, overflow menu (duplicate, move, reset, remove), property list.
- **Hierarchy row** 30px: family chip of the first behavior, name, dots for further families, motion glyph when animated. Selected = `accentDim`.
- **Selection** in the scene: 1.5px ember frame, name + size tag, square resize handle, round rotate handle on a stalk.
- **Overlays**: popup menus and dialogs are `z2` with a `z4` outline and a real shadow (offset + blur). Tooltips `z0`.

## Timeline

A dock under the scene (collapsible, resizable). Header: preview transport, time readout, length, loop (once / loop / ping-pong), autoplay, add track. Left column: one row per track with a key diamond (add/remove at the playhead) and the live value. Right: ruler, ember playhead, keys as diamonds joined by span bars (dim when the value holds). Drag a key to retime (snaps to 0.05s, ⌥ free), click ruler or empty lane to scrub, right-click a lane to key there, Delete removes the selected key, Space previews. The key strip edits time, value and easing (curve glyph menu) of the selected key.

Animatable: position X/Y, rotation, scale X/Y, opacity. Editing an animated property writes a key at the playhead; editing any other property changes the stored value. Keys are absolute values and play in the exported game via the `Animator` behavior and `Animate` action.

## Do's and Don'ts

- **Do** put new behavior types in a `Family` and give them a `factorOf()` summary.
- **Do** use `Field(scrub: …)` for numbers and `Seg`/dropdown for choices.
- **Do** keep `Z.accent` for "this one / live now".
- **Don't** add uppercase tracked labels, a second typeface, or hard offset shadows.
- **Don't** tint panels or text with family colours.
- **Don't** let Play resize or re-centre the scene frame.
