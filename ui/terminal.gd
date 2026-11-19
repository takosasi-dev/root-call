# 端末の描画(画面設計書 §3)。sim の snapshot の行・打っている行・カーソル・実行中の棒を描くだけ。
# 等幅の字体 16 px。英数字は 1 桁、それ以外は 2 桁として折り返す(BIZ UDGothic は半角 0.5em・全角 1em)。
extends Control

const B := preload("res://core/balance.gd")
const S := preload("res://core/strings.gd")
const Kit := preload("res://ui/kit.gd")

const FONT_SIZE := 16
const LINE_H := 24.0
const PAD := Vector2(6, 8)

var snap: Dictionary = {}
var reduce_flash := false
var cell := 8.0
var drawn_at := 0  # 最後に描いた時の Time.get_ticks_usec()(打ってから描くまでを測る)


func _ready() -> void:
	cell = Kit.mono().get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x


func update_snap(s: Dictionary) -> void:
	snap = s
	queue_redraw()


func cols() -> int:
	return int((size.x - PAD.x * 2) / cell)


static func cells_of(text: String) -> int:
	var n := 0
	for k in text.length():
		n += 1 if text.unicode_at(k) < 128 else 2
	return n


# 1 行を桁で折り返し、[文, 色] の区切りの並びの行にする。
func _wrap(parts: Array) -> Array:
	var rows: Array = [[]]
	var used := 0
	var w := cols()
	for p: Array in parts:
		var cur := ""
		for k in String(p[0]).length():
			var ch: String = p[0][k]
			var c := 1 if ch.unicode_at(0) < 128 else 2
			if used + c > w:
				rows[-1].append([cur, p[1]])
				rows.append([])
				cur = ""
				used = 0
			cur += ch
			used += c
		rows[-1].append([cur, p[1]])
	return rows


func _parts(text: String, kind: String) -> Array:
	match kind:
		"p":
			var k := text.find("$ ")
			if k >= 0:
				return [[text.substr(0, k + 2), Kit.C_PROMPT], [text.substr(k + 2), Kit.C_TERM_TEXT]]
		"e":
			return [[text, Kit.C_ERR]]
		"g":
			return [[text, Kit.C_GOOD]]
		"i":
			return [[text, Kit.C_HINT]]
	return [[text, Kit.C_TERM_TEXT]]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Kit.C_TERM)
	draw_rect(Rect2(Vector2.ZERO, size), Kit.C_EDGE, false, 1.0)
	if snap.is_empty():
		return
	var font := Kit.mono()
	var max_rows := int((size.y - PAD.y * 2) / LINE_H)
	# 打っている行(一番下)
	var input := _wrap([[snap["prompt"], Kit.C_PROMPT], [snap["line"], Kit.C_TERM_TEXT]])
	var tail: Array = []
	if snap["running"]:
		tail.append([[S.RUNNING, Kit.C_HINT]])
	var rows: Array = []
	var lines: Array = snap["lines"]
	var k := lines.size() - 1
	while k >= 0 and rows.size() < max_rows:
		var w := _wrap(_parts(lines[k][0], lines[k][1]))
		w.append_array(rows)
		rows = w
		k -= 1
	rows.append_array(tail)
	var first_input := rows.size()
	rows.append_array(input)
	var skip := maxi(rows.size() - max_rows, 0)
	var y := PAD.y + LINE_H - 6
	for r in range(skip, rows.size()):
		var x := PAD.x
		for seg: Array in rows[r]:
			draw_string(font, Vector2(x, y), seg[0], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, seg[1])
			x += cells_of(seg[0]) * cell
		if snap["running"] and r == first_input - 1:
			var frac := float(snap["run_left"]) / maxf(float(snap["run_total"]), 1.0)
			var bx := PAD.x + cells_of(S.RUNNING) * cell + 12
			draw_rect(Rect2(bx, y - 11, 160, 8), Color(Kit.C_HINT, 0.25))
			draw_rect(Rect2(bx, y - 11, 160 * (1.0 - frac), 8), Kit.C_HINT)
		y += LINE_H
	# カーソル(0.5 秒ごとに点滅。点滅を弱める時は点けたまま)
	var pos := cells_of(snap["prompt"]) + cells_of(String(snap["line"]).substr(0, int(snap["cursor"])))
	var row := first_input + pos / cols() - skip
	var col := pos % cols()
	var on := reduce_flash or (Time.get_ticks_msec() / B.CURSOR_BLINK_MS) % 2 == 0
	if on and row >= 0:
		var cy := PAD.y + row * LINE_H
		draw_rect(Rect2(PAD.x + col * cell, cy + 2, 2, LINE_H - 4), Kit.C_TERM_TEXT)
	drawn_at = Time.get_ticks_usec()
