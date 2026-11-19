# S1 タイトル(画面設計書 §2)。入口 3 つと設定。研修を終えるまでは研修の夜を一番上に置く(FR-28・D-13)。
extends Control

signal chosen(what: String)  # "daily" / "training" / "practice" / "settings"

const S := preload("res://core/strings.gd")
const Score := preload("res://core/score.gd")
const Kit := preload("res://ui/kit.gd")
const Menu := preload("res://ui/menu.gd")

var menu: Menu


# store は save_store、day は通し日数、date は "2026-11-19"。
func build(store: RefCounted, day: int, date: String) -> void:
	size = Vector2(1280, 720)
	var head := Kit.label(S.NAME, 72, Kit.C_TEXT, 700, Kit.mono())
	add_child(Kit.place(head, 0, 40, 1280, 100))
	add_child(Kit.place(Kit.label(S.TAGLINE, 28, Kit.C_DIM, 500), 0, 140, 1280, 44))
	if store.load_failed:
		add_child(Kit.place(Kit.label(S.LOAD_FAILED, 18, Kit.C_WARN), 0, 186, 1280, 28))
	var training := Kit.button("training", S.B_TRAINING, 28)
	var daily := Kit.button("daily", "%s   %s" % [S.B_DAILY, date], 30)
	var practice := Kit.button("practice", S.B_PRACTICE, 26)
	var settings := Kit.button("settings", S.B_SETTINGS, 24)
	var order: Array[Button] = [daily, training, practice, settings]
	if not store.training_done():
		order = [training, daily, practice, settings]
	var heights := {training: 72, daily: 88, practice: 72, settings: 72}
	var y := 226.0
	for b in order:
		var w := 240.0 if b == settings else 520.0
		Kit.place(b, 380, y, w, heights[b])
		add_child(b)
		y += heights[b] + 14
	for b: Button in [training, daily, practice, settings]:
		var what := String(b.name)
		b.pressed.connect(func() -> void: chosen.emit(what))
	# 記録
	var easy: bool = store.settings()["easy"]
	var lv := Kit.label("%s  %s" % [S.SET_LEVEL, S.LEVEL[1 if easy else 0]], 18, Kit.C_GOOD if easy else Kit.C_DIM, 700)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(Kit.place(lv, settings.position.x + settings.size.x + 24, settings.position.y, 360, settings.size.y))
	var d: Dictionary = store.daily(day, easy)
	var rec := S.REC_NONE
	if d["first"] != null:
		rec = (S.REC_FIRST % Score.comma(d["first"]["points"])) + " / " + (S.REC_TODAY_BEST % Score.comma(d["best"]["points"]))
	_note(rec, daily)
	var pb: Variant = store.practice_best(easy)
	if pb != null:
		_note(S.REC_BEST % Score.comma(pb["points"]), practice)
	var prompt := Kit.label(S.PROMPT % S.JUMP + "_", 18, Color(Kit.C_PROMPT, 0.35), 400, Kit.mono())
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(Kit.place(prompt, 60, 630, 600, 30))
	var ver := Kit.label(S.VERSION, 20, Kit.C_DIM)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(Kit.place(ver, 24, 676, 200, 32))
	menu = Menu.new(order, 0)


func _note(text: String, by: Button) -> void:
	var l := Kit.label(text, 18, Kit.C_DIM, 500)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(Kit.place(l, by.position.x + by.size.x + 24, by.position.y, 360, by.size.y))


func key(ev: InputEventKey) -> void:
	menu.key(ev)
