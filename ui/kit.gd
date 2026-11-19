# 画面の共通部品(色・字体・ラベル・ボタン・置き場所・文字の折り返し)。画面設計書 §8 の色はここに置く。
# 文言は持たない。各画面は文言を core/strings.gd から渡す。
extends RefCounted

const SANS := "res://assets/fonts/NotoSansJP-Subset.ttf"
const MONO := "res://assets/fonts/BIZUDGothic-Subset.ttf"

const C_BG := Color("0A0D12")
const C_TERM := Color("05070A")
const C_TERM_TEXT := Color("C9D1D9")
const C_PROMPT := Color("6BB8FF")
const C_ERR := Color("FF6B6B")
const C_GOOD := Color("7EE787")
const C_WARN := Color("FFB84D")
const C_IMPACT := Color("C97B7B")
const C_EDGE := Color("3A4250")
const C_HINT := Color("8B95A5")
const C_TEXT := Color("E6E6E6")
const C_DIM := Color("8B95A5")
const C_PANEL := Color("10151C")
const C_SEL := Color("6BB8FF")

static var _fonts := {}


static func font(weight: int = 400) -> Font:
	if not _fonts.has(weight):
		var fv := FontVariation.new()
		fv.base_font = load(SANS)
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_fonts[weight] = fv
	return _fonts[weight]


static func mono() -> Font:
	if not _fonts.has("mono"):
		_fonts["mono"] = load(MONO)
	return _fonts["mono"]


static func label(text: String, size: int, color: Color = C_TEXT, weight: int = 400, f: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", f if f != null else font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(6)
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.anti_aliasing = true
	return s


# ボタン。node_name は自動の確認が押す時の目印。キーボードでの選択は ui/menu.gd が見た目を変える。
static func button(node_name: String, text: String, size: int = 28) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # Tab・矢印を Godot のフォーカスの移動に使わせない
	b.add_theme_font_override("font", font(700))
	b.add_theme_font_size_override("font_size", size)
	set_selected(b, false)
	b.add_theme_stylebox_override("pressed", box(Color(C_SEL, 0.3), C_SEL, 3))
	b.add_theme_stylebox_override("disabled", box(Color(1, 1, 1, 0.02), Color(C_DIM, 0.3), 2))
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, C_TEXT)
	b.add_theme_color_override("font_disabled_color", Color(C_DIM, 0.5))
	return b


static func set_selected(b: Button, on: bool) -> void:
	var edge := C_SEL if on else Color(C_TEXT, 0.55)
	var fill := Color(C_SEL, 0.16) if on else Color(1, 1, 1, 0.04)
	b.add_theme_stylebox_override("normal", box(fill, edge, 3 if on else 2))
	b.add_theme_stylebox_override("hover", box(Color(C_SEL, 0.12), C_SEL, 3))


static func place(c: Control, x: float, y: float, w: float, h: float) -> Control:
	c.position = Vector2(x, y)
	c.size = Vector2(w, h)
	if c is Button:
		c.custom_minimum_size = Vector2(w, h)
	return c


# 健全さ(0〜20)の折れ線。slots 個分の幅に右詰めで描く。線は青、末尾の点だけ今の健全さの色。
static func draw_health(ci: CanvasItem, box: Rect2, values: Array, slots: int) -> void:
	if values.size() < 2:
		return
	var pts := PackedVector2Array()
	var step := box.size.x / float(maxi(slots - 1, 1))
	var x0 := box.end.x - step * (values.size() - 1)
	for k in values.size():
		pts.append(Vector2(x0 + step * k, box.end.y - box.size.y * int(values[k]) / 20.0))
	var fill := pts.duplicate()
	fill.append(Vector2(pts[-1].x, box.end.y))
	fill.append(Vector2(pts[0].x, box.end.y))
	ci.draw_colored_polygon(fill, Color(C_PROMPT, 0.12))
	ci.draw_polyline(pts, C_PROMPT, 2.0, true)
	var last := int(values[-1])
	ci.draw_circle(pts[-1], 3.5, C_GOOD if last >= 16 else (C_WARN if last >= 8 else C_ERR))


# 文字を幅で折り返す(日本語は空白が無いので 1 文字ずつ測る)。
static func wrap(f: Font, text: String, size: int, width: float) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	for k in text.length():
		var c := text[k]
		if f.get_string_size(cur + c, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width and not cur.is_empty():
			out.append(cur)
			cur = c
		else:
			cur += c
	out.append(cur)
	return out
