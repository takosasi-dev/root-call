# 監視の画面(画面設計書 §3・§8)。サーバーの札・依存の矢印・アラートの一覧と下書きを、sim の snapshot から描くだけ。
# 札の 4 つの状態は印(● ▲ ■ ◆)と文字でも分ける(NFR-11)。光る行と、直った行を 300 ms 緑で残すのはここ。
# v0.2.0 の監視室の演出: 矢印を流れる光の粒(止まった線は赤い破線と ✕)、原因の札と広がる枠、札の計器と灯、直った札の波紋。
# アニメーションは時刻から _draw の中で決める(Tween を使わない)。点滅を弱めると、広がる枠・波紋の輪・明滅を止める。
extends Control

const B := preload("res://core/balance.gd")
const S := preload("res://core/strings.gd")
const Kit := preload("res://ui/kit.gd")

const CARD := Vector2(140, 52)
const CARD_POS := [Vector2(20, 44), Vector2(220, 44), Vector2(120, 128), Vector2(20, 212), Vector2(220, 212), Vector2(280, 278)]
const MON_H := 342.0
const ALERT_Y := 350.0
const ROW_H := 19.0
const FOLD_ID := 99999  # たたんだ影響の行

var snap: Dictionary = {}
var reduce_flash := false
var _flash := {}  # 行の id → 光り終わる時刻(ms)
var _ghosts := {}  # 直った行の id → { row, until }
var _last_rows := {}  # 直前の snapshot の行(id → 行)
var _ripples: Array = []  # [サーバー, 始めた時刻(ms)]
var _rows: Array = []  # 画面に出す行(原因が先、影響は 1 行にたたむ)


func update_snap(s: Dictionary) -> void:
	snap = s
	_rows = view_rows(s)
	_last_rows.clear()
	for r: Dictionary in _rows:
		_last_rows[r["id"]] = r
	queue_redraw()


# 原因の行(起きた順)の後に、影響の行をまとめた 1 行を置く。sim.alert_rows() は変えない(bot とテストが読む)。
static func view_rows(s: Dictionary) -> Array:
	var causes: Array = []
	var names: Array = []
	var first := -1
	var training: bool = int(s["mode"]) == 1
	for r: Dictionary in s["alerts"]:
		if r["incident"]:
			causes.append(r)
		else:
			names.append(S.SERVERS[int(r["server"])])
			first = int(r["start"]) if first < 0 else mini(first, int(r["start"]))
	if not names.is_empty():
		causes.append({"server": -1, "text": S.IMPACT_FOLD % [names.size(), S.IMPACT_SEP.join(names)], "start": first,
			"id": FOLD_ID, "class": "impact", "incident": false, "left": -1, "total": 0, "hint": "",
			"explain": S.IMPACT_FOLD_NOTE, "upstream": S.UPSTREAM if training else ""})
	return causes


func flash(id: int) -> void:
	_flash[id] = Time.get_ticks_msec() + B.FLASH_MS


func ghost(id: int) -> void:
	if _last_rows.has(id):
		_ghosts[id] = {"row": _last_rows[id], "until": Time.get_ticks_msec() + B.FIXED_MS}


func ripple(server: int) -> void:
	_ripples.append([server, Time.get_ticks_msec()])


func _draw() -> void:
	if snap.is_empty():
		return
	var now := Time.get_ticks_msec()
	var sans := Kit.font(700)
	var mono := Kit.mono()
	draw_rect(Rect2(0, 0, size.x, MON_H), Kit.C_PANEL)
	draw_rect(Rect2(0, 0, size.x, MON_H), Kit.C_EDGE, false, 1.0)
	draw_string(sans, Vector2(12, 24), S.MONITOR, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Kit.C_DIM)
	_draw_edges(now)
	for i in snap["servers"].size():
		_draw_card(i, snap["servers"][i], sans, mono, now)
	_draw_ripples(now)
	# アラート
	var top := ALERT_Y
	draw_rect(Rect2(0, top, size.x, size.y - top), Kit.C_PANEL)
	draw_rect(Rect2(0, top, size.x, size.y - top), Kit.C_EDGE, false, 1.0)
	draw_string(sans, Vector2(12, top + 22), S.ALERTS, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Kit.C_DIM)
	var rows: Array = _rows.filter(func(r: Dictionary) -> bool: return r["incident"])
	for id: int in _ghosts.keys():
		if now > int(_ghosts[id]["until"]):
			_ghosts.erase(id)
		else:
			var g: Dictionary = _ghosts[id]["row"].duplicate()
			g["ghost"] = true
			rows.append(g)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["start"] < b["start"] if a["start"] != b["start"] else a["id"] < b["id"])
	if not _rows.is_empty() and not _rows[-1]["incident"]:
		rows.append(_rows[-1])  # たたんだ影響の行はいつも一番下
	_draw_rows(rows, top + 34, size.y - 6, now)


func _card_rect(i: int) -> Rect2:
	return Rect2(CARD_POS[i], CARD)


func _draw_edges(now: int) -> void:
	var hot: Array = snap["edges"]
	var pairs := [[0, 2], [1, 2], [2, 3], [2, 4]]  # web01→app01, web02→app01, app01→db01, app01→cache01(要求の向き)
	for k in pairs.size():
		var a := _card_rect(pairs[k][0])
		var b := _card_rect(pairs[k][1])
		var from := Vector2(a.get_center().x, a.end.y)
		var to := Vector2(b.get_center().x, b.position.y)
		var d := (to - from).normalized()
		var n := Vector2(-d.y, d.x)
		if hot[k]:
			draw_dashed_line(from, to, Kit.C_ERR, 2.0, 5.0)
			var mid := from.lerp(to, 0.5)
			draw_line(mid + Vector2(-6, -6), mid + Vector2(6, 6), Kit.C_ERR, 3.0, true)
			draw_line(mid + Vector2(-6, 6), mid + Vector2(6, -6), Kit.C_ERR, 3.0, true)
		else:
			draw_line(from, to, Kit.C_EDGE, 2.0, true)
			for j in 3:  # 要求の流れ(光の粒)
				var p := fmod(float(now % B.PACKET_MS) / B.PACKET_MS + j / 3.0, 1.0)
				var at := from.lerp(to, p)
				draw_circle(at, 5.0, Color(Kit.C_PROMPT, 0.15))
				draw_circle(at, 2.5, Color(Kit.C_PROMPT, 0.9))
		var c := Kit.C_ERR if hot[k] else Kit.C_EDGE
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
	var cause: bool = s.get("cause", false)
	# 原因の札から広がる枠(点滅を弱める時は出さない)
	if cause and not reduce_flash:
		var t := float(now % B.PING_MS) / B.PING_MS
		draw_rect(r.grow(4.0 + 22.0 * t), Color(edge, 0.5 * (1.0 - t)), false, 2.0)
	var fill := Color(edge, 0.18) if s["card"] in ["down", "restart"] else Color("0D1117")
	draw_rect(r, fill)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(edge, 0.25 if s["card"] == "impact" else 0.55))  # ラックの上の縁
	if s["card"] == "impact":
		for side in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end],
				[r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]:
			draw_dashed_line(side[0], side[1], Color(edge, 0.8), 2.0, 6.0)
	else:
		draw_rect(r, edge, false, 3.0 if cause else 2.0)
	# 印は止まっていると明滅する(点滅を弱める時は点けたまま)
	@warning_ignore("integer_division")
	var lit: bool = reduce_flash or s["card"] != "down" or (now / B.BLINK_MS) % 2 == 0
	draw_string(sans, r.position + Vector2(10, 24), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, edge if lit else Color(edge, 0.3))
	draw_string(mono, r.position + Vector2(30, 24), s["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Kit.C_TEXT)
	draw_string(sans, r.position + Vector2(10, 45), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, edge)
	if int(s["left"]) >= 0 and int(s["total"]) > 0:
		var frac := float(s["left"]) / float(s["total"])
		var bar := Rect2(r.position + Vector2(56, 37), Vector2(74, 8))
		draw_rect(bar, Color(Kit.C_WARN, 0.2))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Kit.C_WARN)
	else:
		_gauge(Vector2(r.position.x + 70, r.position.y + 36), int(s["disk"]), B.DISK_ALERT)
		_gauge(Vector2(r.position.x + 70, r.position.y + 43), int(s["mem"]), B.MEM_ALERT)
	# 動いている札の灯(右上の 3 つ。それらしく明滅するだけで、何も表さない)
	if s["card"] in ["ok", "warn"] and not cause:
		for j in 3:
			@warning_ignore("integer_division")
			var on := (((now / 90) + i * 7 + j * 3) * 2654435761) % 5 < 3
			draw_rect(Rect2(r.end.x - 30 + j * 8, r.position.y + 10, 4, 4), Color(Kit.C_GOOD, 0.85 if on else 0.18))
	if cause:
		var tag := Rect2(r.end.x - 44, r.position.y - 10, 40, 18)
		draw_rect(tag, edge)
		draw_string(Kit.font(800), tag.position + Vector2(0, 14), S.CAUSE, HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 12, Kit.C_BG)


# 札の小さな計器(上がディスク・下がメモリ)。警告より上なら橙。
func _gauge(at: Vector2, value: int, alert: int) -> void:
	var w := 60.0
	draw_rect(Rect2(at, Vector2(w, 3)), Color(Kit.C_EDGE, 0.8))
	draw_rect(Rect2(at, Vector2(w * clampi(value, 0, 100) / 100.0, 3)), Kit.C_WARN if value >= alert else Color(Kit.C_HINT, 0.7))


func _draw_ripples(now: int) -> void:
	var keep: Array = []
	for rp: Array in _ripples:
		var t := float(now - int(rp[1])) / B.RIPPLE_MS
		if t >= 1.0:
			continue
		keep.append(rp)
		var r := _card_rect(int(rp[0]))
		draw_rect(r, Color(Kit.C_GOOD, 0.25 * (1.0 - t)))
		if not reduce_flash:
			draw_arc(r.get_center(), 30.0 + 60.0 * t, 0.0, TAU, 48, Color(Kit.C_GOOD, 0.7 * (1.0 - t)), 2.0, true)
	_ripples = keep


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
		extra.append([r["hint"], Color(Kit.C_HINT, 0.85), Kit.mono()])
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
		draw_rect(Rect2(4, y - 1, 3, h - 2), Color(col, 0.9 if r["incident"] or ghost else 0.4))  # 重さの帯
		var age := (int(snap["tick"]) - int(r["start"])) / B.TICK_HZ
		var who: String = "" if int(r["server"]) < 0 else S.SERVERS[int(r["server"])]
		draw_string(mono, Vector2(12, y + 14), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
		var bar: bool = int(r["left"]) >= 0 and int(r["total"]) > 0
		var tx := 12.0 if who == "" else 82.0
		draw_string(sans, Vector2(tx, y + 14), r["text"], HORIZONTAL_ALIGNMENT_LEFT, 145.0 if bar else 360.0 - tx, 14, col)
		if bar:
			var frac := float(r["left"]) / float(r["total"])
			draw_rect(Rect2(232, y + 5, 60, 8), Color(Kit.C_WARN, 0.2))
			draw_rect(Rect2(232, y + 5, 60 * frac, 8), Kit.C_WARN)
			draw_string(sans, Vector2(298, y + 14), S.UNTIL_STOP % (int(r["left"]) / B.TICK_HZ + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Kit.C_WARN)
		if r["incident"] or ghost:
			draw_string(mono, Vector2(size.x - 54, y + 14), "%d:%02d" % [age / 60, age % 60], HORIZONTAL_ALIGNMENT_RIGHT, 44, 14, Kit.C_DIM)
		y += ROW_H
		for e: Array in extras[k]:
			draw_string(e[2], Vector2(24, y + 13), e[0], HORIZONTAL_ALIGNMENT_LEFT, size.x - 30, 13 if e[2] == mono else 12, e[1])
			y += ROW_H
