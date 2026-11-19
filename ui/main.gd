# 画面の切り替え(S0〜S5)・入力の振り分け・保存・自動の一時停止を受け持つ。ゲームの決まりは持たない(INV-1)。
# ?keys=1(または --keys)でキーの確かめの画面(共通 §3 の 22)、?debug=1(または --debug)で window.rcState に状態を出す。
extends Node

const B := preload("res://core/balance.gd")
const S := preload("res://core/strings.gd")
const Sim := preload("res://core/sim.gd")
const Day := preload("res://core/day_index.gd")
const Share := preload("res://core/share_text.gd")
const Store := preload("res://save/save_store.gd")
const Kit := preload("res://ui/kit.gd")
const Play := preload("res://ui/play.gd")
const Title := preload("res://ui/title.gd")
const Result := preload("res://ui/result.gd")
const Settings := preload("res://ui/settings.gd")
const Pause := preload("res://ui/pause.gd")

var stage: Control
var store: Store
var screen := "gate"  # gate / title / play / result / settings / keys
var current: Control = null  # 今の画面(play の時は play)
var play: Play = null
var pause_view: Pause = null
var settings_from := "title"
var night := {}  # 今の夜 { mode, seed, day, date }
var debug := false
var keys_mode := false
var key_log: Array = []  # 届いたキーの中身(直近 20 個。キーの確かめと自動の確認が読む)
var lat_ms: Array = []
var frame_ms: Array = []
var _touch_note: Label = null
var _keys_label: Label = null
var _visibility_cb: Variant = null
var _keys_drawn := 0
var _last_frame := 0


func _ready() -> void:
	stage = Control.new()
	stage.size = Vector2(1280, 720)
	add_child(stage)
	var bg := ColorRect.new()
	bg.color = Kit.C_BG
	stage.add_child(Kit.place(bg, -2000, -2000, 5280, 4720))
	store = Store.new()
	_apply_settings()
	debug = _flag("debug")
	keys_mode = _flag("keys")
	_watch_visibility()
	RenderingServer.frame_post_draw.connect(_after_draw)
	_show_gate()


static func _flag(flag: String) -> bool:
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("location.search", true)
		return q is String and q.contains(flag + "=1")
	return OS.get_cmdline_user_args().has("--" + flag)


func _apply_settings() -> void:
	var st: Dictionary = store.settings()
	Sfx.set_volume(int(st["volume"]))


func _clear() -> void:
	if pause_view != null:
		pause_view.queue_free()
		pause_view = null
	for c in stage.get_children():
		if c is ColorRect and c.get_index() == 0:
			continue
		c.queue_free()
	current = null
	play = null


# --- S0 始める ---

func _show_gate() -> void:
	_clear()
	screen = "gate"
	var g := Control.new()
	g.size = Vector2(1280, 720)
	g.add_child(Kit.place(Kit.label(S.NAME, 72, Kit.C_TEXT, 700, Kit.mono()), 0, 220, 1280, 100))
	g.add_child(Kit.place(Kit.label(S.S0_START, 28, Kit.C_TEXT, 500), 0, 360, 1280, 44))
	g.add_child(Kit.place(Kit.label(S.S0_KEYBOARD, 18, Kit.C_DIM), 0, 410, 1280, 30))
	_touch_note = Kit.label(S.TOUCH, 22, Kit.C_WARN, 700)
	_touch_note.visible = false
	g.add_child(Kit.place(_touch_note, 0, 470, 1280, 40))
	stage.add_child(g)
	current = g


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		_log_key(event)
	if screen == "gate":
		if event is InputEventScreenTouch and event.pressed:
			_touch_note.visible = true  # FR-29: タッチで開いた人に伝える
			get_viewport().set_input_as_handled()
			return
		if (event is InputEventKey or event is InputEventMouseButton) and event.pressed:
			Sfx.unlock()  # FR-26: この入力は数えない
			get_viewport().set_input_as_handled()
			if keys_mode:
				_show_keys()
			else:
				_show_title()
		return
	if not (event is InputEventKey):
		return
	get_viewport().set_input_as_handled()  # Tab・矢印を Godot のフォーカスの移動に使わせない
	if screen == "keys":
		_keys_input(event)
	elif screen == "settings":
		current.key(event)
	elif pause_view != null:
		pause_view.key(event)
	elif current != null and current.has_method("key"):
		current.key(event)


# --- S1 タイトル ---

func _show_title() -> void:
	_clear()
	screen = "title"
	var d := _today()
	var t := Title.new()
	t.build(store, d["day"], d["date"])
	t.chosen.connect(_on_title)
	stage.add_child(t)
	current = t


func _on_title(what: String) -> void:
	match what:
		"settings":
			_show_settings("title")
		"daily":
			var d := _today()
			_start({"mode": Sim.MODE_DAILY, "seed": Day.day_seed(d["day"]), "day": d["day"], "date": d["date"]})
		"training":
			var d2 := _today()
			_start({"mode": Sim.MODE_TRAINING, "seed": 1, "day": d2["day"], "date": d2["date"]})
		"practice":
			var d3 := _today()
			var s := Time.get_ticks_usec() & 0xFFFFFFFF
			_start({"mode": Sim.MODE_PRACTICE, "seed": s if s != 0 else 1, "day": d3["day"], "date": d3["date"]})


# 端末の今日の日付。始めた時の日付で夜を決める(E-17)。
func _today() -> Dictionary:
	var t := Time.get_date_dict_from_system()
	var y := int(t["year"])
	var m := int(t["month"])
	var dd := int(t["day"])
	return {"day": Day.day_index(y, m, dd), "date": Day.date_string(y, m, dd)}


# --- S2 プレイ ---

func _start(n: Dictionary) -> void:
	_clear()
	night = n
	screen = "play"
	play = Play.new()
	var st: Dictionary = store.settings()
	play.shake_on = st["shake"]
	play.reduce_flash = st["reduce_flash"]
	stage.add_child(play)
	play.start(int(n["mode"]), int(n["seed"]))
	play.finished.connect(_on_finished)
	play.pause_requested.connect(_pause)
	current = play


func _pause() -> void:
	if play == null or pause_view != null or not play.is_playing():
		return
	play.paused = true
	pause_view = Pause.new()
	pause_view.build()
	pause_view.picked.connect(_on_pause)
	stage.add_child(pause_view)


func _on_pause(what: String) -> void:
	match what:
		"resume":
			pause_view.queue_free()
			pause_view = null
			play.paused = false  # 押した tick から再開(待ち時間なし)
		"restart":
			_start(night)
		"settings":
			_show_settings("pause")
		"title":
			_show_title()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_pause()  # E-13: 戻っても自動では再開しない


# タブが裏に回ったら一時停止にする。Web では通知が来ないことがあるので、ブラウザにも聞く(ParryDuel と同じ)。
func _watch_visibility() -> void:
	if not OS.has_feature("web"):
		return
	_visibility_cb = JavaScriptBridge.create_callback(func(_args: Array) -> void: _pause())
	var doc: Variant = JavaScriptBridge.get_interface("document")
	if doc != null:
		doc.addEventListener("visibilitychange", _visibility_cb)


# --- S3 結果 ---

func _on_finished(result: Dictionary) -> void:
	var n := night
	var rec := store.record(int(n["mode"]), int(n["day"]), result)
	var text := Share.make(n["date"], int(n["mode"]), rec["first_today"], result)
	_clear()
	screen = "result"
	var r := Result.new()
	r.build(int(n["mode"]), result, rec, text)
	r.retry.connect(func() -> void: _start(night))  # FR-21: 同じ入口。今日の夜は同じ種
	r.to_title.connect(_show_title)
	stage.add_child(r)
	current = r


# --- S4 設定 ---

func _show_settings(from: String) -> void:
	settings_from = from
	var s := Settings.new()
	s.build(store)
	s.back.connect(_settings_back.bind(s))
	if from == "pause":
		pause_view.visible = false
		var dim := ColorRect.new()
		dim.color = Color(Kit.C_BG, 0.96)
		s.add_child(Kit.place(dim, 0, 0, 1280, 720))
		s.move_child(dim, 0)
		stage.add_child(s)
		current = s
		screen = "settings"
		pause_view.process_mode = Node.PROCESS_MODE_DISABLED
		_settings_overlay = s
	else:
		_clear()
		screen = "settings"
		stage.add_child(s)
		current = s


var _settings_overlay: Control = null


func _settings_back(s: Control) -> void:
	_apply_settings()
	if settings_from == "pause" and play != null:
		var st: Dictionary = store.settings()
		play.shake_on = st["shake"]
		play.reduce_flash = st["reduce_flash"]
		play.monitor.reduce_flash = st["reduce_flash"]
		play.terminal.reduce_flash = st["reduce_flash"]
		s.queue_free()
		_settings_overlay = null
		pause_view.visible = true
		pause_view.process_mode = Node.PROCESS_MODE_INHERIT
		current = play
		screen = "play"
	else:
		_show_title()


# --- キーの確かめ(共通 §3 の 22) ---

func _show_keys() -> void:
	_clear()
	screen = "keys"
	var g := Control.new()
	g.size = Vector2(1280, 720)
	g.add_child(Kit.place(Kit.label(S.KEYS_TITLE, 22, Kit.C_TEXT, 700), 0, 20, 1280, 40))
	_keys_label = Kit.label("", 18, Kit.C_TERM_TEXT, 400, Kit.mono())
	_keys_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_keys_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	g.add_child(Kit.place(_keys_label, 60, 80, 1160, 620))
	stage.add_child(g)
	current = g


var _esc_count := 0


func _keys_input(ev: InputEventKey) -> void:
	if not ev.pressed:
		return
	_keys_label.text = "\n".join(key_log.slice(maxi(key_log.size() - 22, 0)).map(func(k: Dictionary) -> String: return JSON.stringify(k)))
	_esc_count = _esc_count + 1 if ev.physical_keycode == KEY_ESCAPE else 0
	if _esc_count >= 2:
		keys_mode = false
		_show_title()


func _log_key(ev: InputEventKey) -> void:
	key_log.append({"pk": ev.physical_keycode, "pk_name": OS.get_keycode_string(ev.physical_keycode), "label": OS.get_keycode_string(ev.key_label),
		"unicode": ev.unicode, "echo": ev.echo, "shift": ev.shift_pressed, "ctrl": ev.ctrl_pressed, "alt": ev.alt_pressed, "meta": ev.meta_pressed})
	if key_log.size() > 40:
		key_log.pop_front()


# --- デバッグ用の窓口(読むだけ) ---

func _after_draw() -> void:
	var now := Time.get_ticks_usec()
	if _last_frame > 0 and frame_ms.size() < 20000:
		frame_ms.append((now - _last_frame) / 1000.0)
	_last_frame = now
	if play != null and play.sim != null and play.sim.ed.keys != _keys_drawn:
		_keys_drawn = play.sim.ed.keys
		if play.key_at > 0 and lat_ms.size() < 2000:
			lat_ms.append((now - play.key_at) / 1000.0)
	if debug and OS.has_feature("web"):
		JavaScriptBridge.eval("window.rcState=" + JSON.stringify(JSON.stringify(state())), true)
		if frame_ms.size() % 60 == 0:
			JavaScriptBridge.eval("window.rcStats=" + JSON.stringify(JSON.stringify(stats())), true)


func state() -> Dictionary:
	var out := {"screen": screen, "paused": pause_view != null, "keys": key_log.slice(maxi(key_log.size() - 20, 0)),
		"buttons": {}, "sfx": Sfx.played, "unlocked": Sfx.unlocked, "lat_n": lat_ms.size(), "frames_n": frame_ms.size(),
		"save_failed": store.write_failed, "load_failed": store.load_failed}
	var root: Control = pause_view if pause_view != null and pause_view.visible else current
	if root != null:
		for b in root.find_children("*", "Button", true, false):
			var btn := b as Button
			if btn.is_visible_in_tree() and not btn.disabled:
				out["buttons"][String(btn.name)] = [btn.global_position.x + btn.size.x / 2, btn.global_position.y + btn.size.y / 2]
	if play != null and play.sim != null:
		var sim := play.sim
		out["play"] = {"line": sim.ed.text, "cursor": sim.ed.cursor, "prompt": sim.prompt(), "keys": sim.ed.keys, "tick": sim.tick,
			"loc": sim.loc, "running": sim.is_running(), "alerts": sim.alert_rows().size(), "incidents": sim.incidents.size(),
			"fixed": sim.incidents.filter(func(i: Dictionary) -> bool: return int(i["fixed"]) >= 0).size(),
			"last": sim.lines.slice(maxi(sim.lines.size() - 4, 0)).map(func(l: Array) -> String: return l[0]), "pos": [play.position.x, play.position.y]}
	return out


func stats() -> Dictionary:
	return {"lat": _pct(lat_ms), "frame": _pct(frame_ms)}


static func _pct(list: Array) -> Dictionary:
	if list.is_empty():
		return {"n": 0}
	var s := list.duplicate()
	s.sort()
	return {"n": s.size(), "p50": s[s.size() / 2], "p95": s[mini(int(ceil(s.size() * 0.95)) - 1, s.size() - 1)], "max": s[-1]}
