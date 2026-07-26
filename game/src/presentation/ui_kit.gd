extends RefCounted
## The parchment UI (docs/04 "the interface is a document"). Everything
## the player reads is something a man of 1775 could have held: an
## orderly book, a muster roll, a courier's scrap. No glass, no glow, no
## sci-fi corners — ink on rag paper, ruled lines, and a red seal where
## something is urgent.
##
## All procedural: the textures are generated at load, so there are no
## binary art assets to version and the look survives any resolution.
##
## Use via preload:
##   const UIKit := preload("res://src/presentation/ui_kit.gd")

const INK := Color(0.13, 0.11, 0.09)
const INK_FADED := Color(0.13, 0.11, 0.09, 0.62)
const INK_RED := Color(0.48, 0.11, 0.09)        # the rubricated line
const PARCHMENT := Color(0.86, 0.81, 0.68)
const PARCHMENT_DARK := Color(0.72, 0.66, 0.53)
const RULE := Color(0.42, 0.35, 0.26, 0.55)

## Body text on parchment wants a serif. We ask the system for one and
## let Godot fall back gracefully — no font file to ship or license.
static func serif_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Georgia", "Palatino", "Book Antiqua", "Times New Roman",
		"Liberation Serif", "DejaVu Serif", "serif"])
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return f


## A sheet of rag paper: uneven fibre, a warmer core, darkened edges
## where it has been handled, and a few old stains.
static func parchment_texture(seed_v := 7, size := 192) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var h := seed_v * 2654435761
	for y in size:
		for x in size:
			# Fibre: two coarse noise octaves, cheap and deterministic.
			var n1 := float((((x * 73856093) ^ (y * 19349663) ^ h) >> 8) % 1000) / 1000.0
			var n2 := float((((x / 3 * 83492791) ^ (y / 3 * 29349511) ^ h) >> 6) % 1000) / 1000.0
			var fibre := 0.94 + n1 * 0.05 + n2 * 0.05
			# Handled edges: darker toward the borders.
			var ex := absf(float(x) / float(size) - 0.5) * 2.0
			var ey := absf(float(y) / float(size) - 0.5) * 2.0
			var edge := 1.0 - pow(maxf(ex, ey), 3.0) * 0.28
			var c := PARCHMENT * fibre * edge
			# The odd old stain.
			var sx := float((h >> 3) % size)
			var sy := float((h >> 11) % size)
			var d := Vector2(float(x) - sx, float(y) - sy).length()
			if d < 26.0:
				c = c.lerp(PARCHMENT_DARK, (1.0 - d / 26.0) * 0.22)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## A parchment panel: the paper, a hairline ink border, and a soft drop
## shadow so it sits ON the world rather than in it.
static func panel_style(seed_v := 7) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = parchment_texture(seed_v)
	sb.set_texture_margin_all(10.0)
	sb.set_content_margin_all(14.0)
	sb.modulate_color = Color(1, 1, 1, 0.96)
	return sb


## The heading rule under a panel title — a ruled line, not a divider.
static func rule_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = RULE
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = 0.0
	return sb


## A label in ink. `weight` picks the hierarchy: "title" (a heading in
## a document), "body", or "note" (a marginal hand).
static func ink_label(text := "", weight := "body") -> Label:
	var l := Label.new()
	l.text = text
	var font := serif_font()
	l.add_theme_font_override("font", font)
	match weight:
		"title":
			l.add_theme_font_size_override("font_size", 22)
			l.add_theme_color_override("font_color", INK)
		"note":
			l.add_theme_font_size_override("font_size", 14)
			l.add_theme_color_override("font_color", INK_FADED)
		"red":
			l.add_theme_font_size_override("font_size", 17)
			l.add_theme_color_override("font_color", INK_RED)
		_:
			l.add_theme_font_size_override("font_size", 17)
			l.add_theme_color_override("font_color", INK)
	# Ink on paper has no glow; a faint shading keeps it legible on any
	# parchment tone without looking like a drop shadow.
	l.add_theme_constant_override("outline_size", 0)
	return l


## A finished panel with a title, a rule, and a body label — the shape
## nearly every readout in this game wants. Returns the panel; the body
## label is `panel.get_meta("body")`, the title `panel.get_meta("title")`.
static func document(title: String, seed_v := 7, width := 430.0) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style(seed_v))
	panel.custom_minimum_size = Vector2(width, 0.0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	var head := ink_label(title, "title")
	col.add_child(head)
	var rule := Panel.new()
	rule.add_theme_stylebox_override("panel", rule_style())
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	col.add_child(rule)
	var body := ink_label("", "body")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(body)
	panel.set_meta("body", body)
	panel.set_meta("title", head)
	panel.set_meta("column", col)
	return panel


## A wax seal — the one place the interface raises its voice. Used for
## a company breaking, an alarm raised, a man recognized in the street.
static func seal(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.42, 0.09, 0.08, 0.92)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(9.0)
	sb.border_width_bottom = 2
	sb.border_color = Color(0.28, 0.05, 0.05)
	p.add_theme_stylebox_override("panel", sb)
	var l := ink_label(text, "body")
	l.add_theme_color_override("font_color", Color(0.96, 0.91, 0.82))
	p.add_child(l)
	p.set_meta("body", l)
	return p
