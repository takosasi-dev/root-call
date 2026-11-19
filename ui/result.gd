# S3 結果(画面設計書 §4)。点を 600 ms で数え上げ、5 つの数・最高との差・共有する文字を出す。
# もう1回は 300 ms 後から押せる(Enter・R でも)。コピーは clipboard_set を試し、選べる枠も出す(E-16)。
extends Control

signal retry
signal to_title

const B := preload("res://core/balance.gd")
const S := preload("res://core/strings.gd")
const Score := preload("res://core/score.gd")
const Kit := preload("res://ui/kit.gd")
const Menu := preload("res://ui/menu.gd")

var menu: Menu
var share := ""
var _points := 0
var _shown_at := 0
var _points_label: Label
var _retry: Button
var _copied: Label


# rec は save_store.record() の戻り値。
func build(mode: int, result: Dictionary, rec: Dictionary, share_text: String) -> void:
	size = Vector2(1280, 720)
	share = share_text
	_points = int(result["points"])
	_shown_at = Time.get_ticks_msec()
	add_child(Kit.place(Kit.label(S.DAWN, 32, Kit.C_DIM, 700), 0, 20, 1280, 48))
	_points_label = Kit.label(S.RES_POINTS % "0", 96, Kit.C_TEXT, 800)
	add_child(Kit.place(_points_label, 0, 70, 1280, 120))
	var y := 196.0
	if mode != 1 and rec["prev_best"] != null:
		var diff := _points - int(rec["prev_best"]["points"])
		var text := ""
		if rec["new_best"]:
			text = S.RES_NEW_BEST % Score.comma(diff)
		else:
			text = S.RES_TO_BEST % Score.comma(-diff)
		if mode == 0:
			var best: int = maxi(int(rec["prev_best"]["points"]), _points)
			text += S.RES_TODAY_BEST % Score.comma(best)
		add_child(Kit.place(Kit.label(text, 24, Kit.C_GOOD if rec["new_best"] else Kit.C_DIM, 700), 0, y, 1280, 36))
	y += 48
	var stats := [S.RES_UPTIME % Score.pct1(int(result["uptime100"])), S.RES_MTTR % Score.sec1(int(result["mttr10"])),
		S.RES_KEYS % int(result["keys"]), S.RES_FIXED % int(result["fixed"])]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 44)
	for s: String in stats:
		row.add_child(Kit.label(s, 22, Kit.C_TEXT, 500))
	var bk := S.RES_BACKUP_OK
	if int(result["backups_left"]) > 0:
		bk = S.RES_BACKUP_NG % (int(result["backups_left"]) * B.BACKUP_PENALTY)
	row.add_child(Kit.label(bk, 22, Kit.C_ERR if int(result["backups_left"]) > 0 else Kit.C_TEXT, 500))
	add_child(Kit.place(row, 0, y, 1280, 40))
	_retry = Kit.place(Kit.button("retry", S.B_RETRY, 30), 490, 310, 300, 72)
	_retry.disabled = true
	add_child(_retry)
	var box := TextEdit.new()
	box.name = "share"
	box.text = share
	box.editable = false
	box.context_menu_enabled = true
	box.focus_mode = Control.FOCUS_CLICK
	box.add_theme_font_override("font", Kit.mono())
	box.add_theme_font_size_override("font_size", 18)
	box.add_theme_color_override("font_readonly_color", Kit.C_TERM_TEXT)
	add_child(Kit.place(box, 290, 400, 700, 104))
	var copy := Kit.place(Kit.button("copy", S.B_COPY, 24), 420, 520, 200, 60)
	var title := Kit.place(Kit.button("title", S.B_TITLE, 24), 660, 520, 200, 60)
	add_child(copy)
	add_child(title)
	_copied = Kit.label("", 18, Kit.C_DIM)
	add_child(Kit.place(_copied, 0, 588, 1280, 30))
	var notes: Array = []
	if rec.get("first_training", false):
		notes.append(S.RES_TRAINING_DONE)
	if not rec.get("saved", true):
		notes.append(S.SAVE_FAILED)
	add_child(Kit.place(Kit.label("\n".join(notes), 20, Kit.C_GOOD), 0, 624, 1280, 70))
	_retry.pressed.connect(func() -> void: retry.emit())
	copy.pressed.connect(_copy)
	title.pressed.connect(func() -> void: to_title.emit())
	menu = Menu.new([_retry, copy, title] as Array[Button], 0)


func _copy() -> void:
	DisplayServer.clipboard_set(share)
	_copied.text = S.COPIED


@warning_ignore("integer_division")
func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() - _shown_at
	var shown := _points if t >= B.COUNT_MS else _points * t / B.COUNT_MS
	_points_label.text = S.RES_POINTS % Score.comma(shown)
	if _retry.disabled and t >= B.RETRY_LOCK_MS:
		_retry.disabled = false


func key(ev: InputEventKey) -> void:
	if ev.pressed and not ev.echo and ev.physical_keycode == KEY_R and not _retry.disabled:
		retry.emit()
		return
	menu.key(ev)
