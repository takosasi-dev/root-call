# 監視の画面(画面設計書 §3・§8)。サーバーの札・依存の矢印・アラートの一覧と下書きを、sim の snapshot から描くだけ。
# 札の 4 つの状態は印(● ▲ ■ ◆)と文字でも分ける(NFR-11)。光る行と、直った行を 300 ms 緑で残すのはここ。
extends Control

const B := preload("res://core/balance.gd")
const S := preload("res://core/strings.gd")
const Kit := preload("res://ui/kit.gd")

const CARD := Vector2(140, 52)
const CARD_POS := [Vector2(20, 40), Vector2(220, 40), Vector2(120, 120), Vector2(20, 200), Vector2(220, 200), Vector2(280, 276)]
const MON_H := 336.0
const ALERT_Y := 344.0
const ROW_H := 19.0

var snap: Dictionary = {}
var reduce_flash := false
var _flash := {}  # 行の id → 光り終わる時刻(ms)
var _ghosts := {}  # 直った行の id → { row, until }
var _last_rows := {}  # 直前の snapshot の行(id → 行)


func update_snap(s: Dictionary) -> void:
	snap = s
	_last_rows.clear()
	for r: Dictionary in s["alerts"]:
		_last_rows[r["id"]] = r
	queue_redraw()


func flash(id: int) -> void:
	_flash[id] = Time.get_ticks_msec() + B.FLASH_MS


func ghost(id: int) -> void:
	if _last_rows.has(id):
		_ghosts[id] = {"row": _last_rows[id], "until": Time.get_ticks_msec() + B.FIXED_MS}


func _draw() -> void:
	if snap.is_empty():
		return
	var now := Time.get_ticks_msec()
	var sans := Kit.font(700)
	var mono := Kit.mono()
	draw_rect(Rect2(0, 0, size.x, MON_H), Kit.C_PANEL)
	draw_rect(Rect2(0, 0, size.x, MON_H), Kit.C_EDGE, false, 1.0)
	draw_string(sans, Vector2(12, 24), S.MONITOR, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Kit.C_DIM)
	_draw_edges()
	for i in snap["servers"].size():
		_draw_card(i, snap["servers"][i], sans, mono, now)
	# アラート
	var top := ALERT_Y
	draw_rect(Rect2(0, top, size.x, size.y - top), Kit.C_PANEL)
	draw_rect(Rect2(0, top, size.x, size.y - top), Kit.C_EDGE, false, 1.0)
	draw_string(sans, Vector2(12, top + 22), S.ALERTS, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Kit.C_DIM)
	var rows: Array = snap["alerts"].duplicate()
	for id: int in _ghosts.keys():
		if now > int(_ghosts[id]["until"]):
			_ghosts.erase(id)
		else:
			var g: Dictionary = _ghosts[id]["row"].duplicate()
			g["ghost"] = true
			rows.append(g)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["start"] < b["start"] if a["start"] != b["start"] else a["id"] < b["id"])
	_draw_rows(rows, top + 34, size.y - 6, now)


func _card_rect(i: int) -> Rect2:
	return Rect2(CARD_POS[i], CARD)


func _draw_edges() -> void:
	var hot: Array = snap["edges"]
	var pairs := [[0, 2], [1, 2], [2, 3], [2, 4]]  # web01→app01, web02→app01, app01→db01, app01→cache01(依存する向き)
	for k in pairs.size():
		var a := _card_rect(pairs[k][0])
		var b := _card_rect(pairs[k][1])
		var from := Vector2(a.get_center().x, a.end.y)
		var to := Vector2(b.get_center().x, b.position.y)
		var c := Kit.C_ERR if hot[k] else Kit.C_EDGE
		draw_line(from, to, c, 2.0, true)
		var d := (to - from).normalized()
		var n := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([to, to - d * 9 + n * 5, to - d * 9 - n * 5]), c)


func _draw_card(i: int, s: Dictionary, sans: Font, mono: Font, now: int) -> void:
	var r := _card_rect(i)
	var mark := S.MARK_OK
	var word := S.CARD_OK
	var edge := Kit.C_GOOD
	match s["card"]:
		"warn":
			mark = S.MARK_WARN
			word = S.CARD_WARN
			edge = Kit.C_WARN
		"down", "restart":
			mark = S.MARK_DOWN
			word = S.CARD_DOWN if s["card"] == "down" else S.CARD_RESTART
			edge = Kit.C_ERR
		"impact":
			mark = S.MARK_IMPACT
			word = S.CARD_IMPACT
			edge = Kit.C_ERR
	var fill := Color(edge, 0.18) if s["card"] in ["down", "restart"] else Kit.C_BG
	draw_rect(r, fill)
	if s["card"] == "impact":
		for side in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end],
				[r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]:
			draw_dashed_line(side[0], side[1], edge, 2.0, 6.0)
	else:
		draw_rect(r, edge, false, 2.0)
	draw_string(sans, r.position + Vector2(10, 22), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, edge)
	draw_string(mono, r.position + Vector2(30, 22), s["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Kit.C_TEXT)
	draw_string(sans, r.position + Vector2(10, 44), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, edge)
	if int(s["left"]) >= 0 and int(s["total"]) > 0:
		var frac := float(s["left"]) / float(s["total"])
		var bar := Rect2(r.position + Vector2(56, 36), Vector2(74, 8))
		draw_rect(bar, Color(Kit.C_WARN, 0.2))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Kit.C_WARN)


static func _class_color(cls: String) -> Color:
	match cls:
		"down":
			return Kit.C_ERR
		"warn":
			return Kit.C_WARN
	return Kit.C_IMPACT


func _row_lines(r: Dictionary, sans: Font) -> Array:
	var extra: Array = []  # [文, 色, 字体]
	if r["hint"] != "":
		extra.append([r["hint"], Color(Kit.C_HINT, 0.6), Kit.mono()])
	if r["explain"] != "":
		for line in Kit.wrap(sans, r["explain"], 12, size.x - 36):
			extra.append([line, Kit.C_DIM, sans])
	if r["upstream"] != "":
		extra.append([r["upstream"], Kit.C_DIM, sans])
	return extra


@warning_ignore("integer_division")
func _draw_rows(rows: Array, y0: float, y1: float, now: int) -> void:
	var sans := Kit.font(500)
	var mono := Kit.mono()
	var cap := int((y1 - y0) / ROW_H)
	var extras: Array = rows.map(func(r: Dictionary) -> Array: return _row_lines(r, sans))
	var total := rows.size()
	for e: Array in extras:
		total += e.size()
	# 入りきらない時は、古い行から 1 行ずつ縮める(下書き・説明を外す)
	for k in rows.size():
		if total <= cap:
			break
		total -= extras[k].size()
		extras[k] = []
	var y := y0
	var start_row := 0
	while total > cap and start_row < rows.size():  # それでも入らなければ古い物から外す
		total -= 1
		start_row += 1
	for k in range(start_row, rows.size()):
		var r: Dictionary = rows[k]
		var h: float = ROW_H * (1 + extras[k].size())
		var col := _class_color(r["class"])
		var ghost: bool = r.get("ghost", false)
		var alpha_max := B.REDUCED_FLASH_ALPHA if reduce_flash else 0.4
		if ghost:
			col = Kit.C_GOOD
			draw_rect(Rect2(4, y - 2, size.x - 8, h), Color(Kit.C_GOOD, minf(0.25, alpha_max)))
		elif _flash.has(r["id"]) and now < int(_flash[r["id"]]):
			draw_rect(Rect2(4, y - 2, size.x - 8, h), Color(col, alpha_max))
		var age := (int(snap["tick"]) - int(r["start"])) / B.TICK_HZ
		draw_string(mono, Vector2(10, y + 14), S.SERVERS[int(r["server"])], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
		var bar: bool = int(r["left"]) >= 0 and int(r["total"]) > 0
		draw_string(sans, Vector2(82, y + 14), r["text"], HORIZONTAL_ALIGNMENT_LEFT, 145.0 if bar else 290.0, 14, col)
		if bar:
			var frac := float(r["left"]) / float(r["total"])
			draw_rect(Rect2(232, y + 5, 60, 8), Color(Kit.C_WARN, 0.2))
			draw_rect(Rect2(232, y + 5, 60 * frac, 8), Kit.C_WARN)
			draw_string(sans, Vector2(298, y + 14), S.UNTIL_STOP % (int(r["left"]) / B.TICK_HZ + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Kit.C_WARN)
		draw_string(mono, Vector2(size.x - 54, y + 14), "%d:%02d" % [age / 60, age % 60], HORIZONTAL_ALIGNMENT_RIGHT, 44, 14, Kit.C_DIM)
		y += ROW_H
		for e: Array in extras[k]:
			draw_string(e[2], Vector2(24, y + 13), e[0], HORIZONTAL_ALIGNMENT_LEFT, size.x - 30, 13 if e[2] == mono else 12, e[1])
			y += ROW_H
