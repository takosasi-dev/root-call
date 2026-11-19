# S2 プレイ。sim をたまった時間ぶん進め(1 フレーム 8 tick まで)、events で演出と音を出し、snapshot を監視と端末に渡す。
# ゲームの決まりは持たない(INV-1)。打鍵は ui/keymap で番号にして sim.queue_key に渡すだけ。
# 上の帯の右に稼働の折れ線(直近 60 秒)と難しさの札を描き、障害が来ると画面の縁を赤く脈打たせる(v0.2.0)。
extends Control

signal finished(result: Dictionary)
signal pause_requested

const B := preload("res://core/balance.gd")
const S := preload("res://core/strings.gd")
const Sim := preload("res://core/sim.gd")
const Score := preload("res://core/score.gd")
const Kit := preload("res://ui/kit.gd")
const Keymap := preload("res://ui/keymap.gd")
const Monitor := preload("res://ui/monitor.gd")
const Terminal := preload("res://ui/terminal.gd")

var sim: Sim = null
var mode := 0
var seed_value := 1
var paused := false
var shake_on := true
var reduce_flash := false
var monitor: Monitor
var terminal: Terminal
var key_at := 0  # 最後に打鍵を受けた時刻(usec。描くまでを測る)
var latencies: Array = []  # 打ってから描くまで(ms。デバッグ用)
var _acc := 0.0
var _over_at := -1
var _shake_until := 0
var _bar: Dictionary = {}
var _dawn: Label
var _esc: Button
var history: Array[int] = []  # 1 秒ごとの健全さ(0〜20)。結果の画面の折れ線にも渡す
var _spark_sec := -1
var _edge: Control


# 画面の縁の脈打ち(監視と端末より上に描く)。
class EdgePulse extends Control:
	var at := -100000
	var alpha_max := 0.55

	func _draw() -> void:
		var t := float(Time.get_ticks_msec() - at) / B.EDGE_PULSE_MS
		if t >= 1.0:
			return
		for k in 5:
			var c := Color(Kit.C_ERR, alpha_max * (1.0 - t) * (1.0 - k / 5.0))
			draw_rect(Rect2(k * 3, k * 3, size.x - k * 6, size.y - k * 6), c, false, 3.0)


func _ready() -> void:
	size = Vector2(1280, 720)
	_esc = Kit.place(Kit.button("Esc", S.ESC, 20), 24, 8, 72, 40)
	_esc.pressed.connect(func() -> void: pause_requested.emit())
	add_child(_esc)
	for k: String in ["clock", "uptime", "mttr", "keys"]:
		var l := Kit.label("", 22 if k == "clock" else 20, Kit.C_TEXT, 700, Kit.mono() if k == "clock" else null)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		add_child(l)
		_bar[k] = l
	Kit.place(_bar["clock"], 120, 8, 100, 40)
	Kit.place(_bar["uptime"], 240, 8, 200, 40)
	Kit.place(_bar["mttr"], 460, 8, 240, 40)
	Kit.place(_bar["keys"], 720, 8, 200, 40)
	monitor = Monitor.new()
	Kit.place(monitor, 16, 64, 440, 640)
	add_child(monitor)
	terminal = Terminal.new()
	Kit.place(terminal, 472, 64, 792, 640)
	add_child(terminal)
	_edge = EdgePulse.new()
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Kit.place(_edge, 0, 0, 1280, 720)
	add_child(_edge)
	_dawn = Kit.label(S.DAWN, 48, Kit.C_TEXT, 800)
	Kit.place(_dawn, 0, 300, 1280, 120)
	_dawn.visible = false
	add_child(_dawn)


func start(p_mode: int, p_seed: int, easy: bool = false) -> void:
	mode = p_mode
	seed_value = p_seed
	sim = Sim.new(p_seed, p_mode, null, easy)
	paused = false
	_acc = 0.0
	_over_at = -1
	_dawn.visible = false
	history.clear()
	_spark_sec = -1
	_edge.at = -100000
	_edge.alpha_max = B.REDUCED_FLASH_ALPHA if reduce_flash else 0.55
	monitor.reduce_flash = reduce_flash
	terminal.reduce_flash = reduce_flash
	_refresh()


func is_playing() -> bool:
	return sim != null and not sim.is_over()


# S2 のキー。Esc は一時停止、ほかは全部端末へ(画面設計書 §5)。
func key(ev: InputEventKey) -> void:
	if ev.pressed and not ev.echo and ev.physical_keycode == KEY_ESCAPE:
		pause_requested.emit()
		return
	if sim == null or sim.is_over():
		return
	var code := Keymap.code_of(ev)
	if code >= 0:
		sim.queue_key(code)
		key_at = Time.get_ticks_usec()


func _process(delta: float) -> void:
	if sim == null:
		return
	position = Vector2.ZERO
	if shake_on and Time.get_ticks_msec() < _shake_until:
		position = Vector2(randf_range(-B.SHAKE_PX, B.SHAKE_PX), randf_range(-B.SHAKE_PX, B.SHAKE_PX))
	if _over_at >= 0:
		if Time.get_ticks_msec() - _over_at >= B.OVER_MS:
			_over_at = -2
			finished.emit(sim.result())
		return
	if paused or _over_at == -2:
		return
	_acc += delta * B.TICK_HZ
	var n := int(_acc)
	_acc -= n
	if n > B.MAX_STEPS_PER_FRAME:
		n = B.MAX_STEPS_PER_FRAME  # E-21: 超えた分は捨てる
		_acc = 0.0
	var keyed := false
	for k in n:
		sim.step()
		for e: Dictionary in sim.events():
			keyed = _on_event(e) or keyed
	if keyed:
		Sfx.play("key")  # 1 フレーム 1 回
	_refresh()


# 演出の表(§9.13)。打鍵なら真。
func _on_event(e: Dictionary) -> bool:
	match e["type"]:
		"key":
			return true
		"incident":
			monitor.flash(int(e["id"]))
			_edge.at = Time.get_ticks_msec()
			Sfx.play("alert")
		"escalated":
			monitor.flash(int(e["id"]))
			Sfx.play("escalated")
			_shake_until = Time.get_ticks_msec() + B.SHAKE_MS
		"fixed":
			monitor.ghost(int(e["id"]))
			monitor.ripple(int(e["server"]))
			Sfx.play("fixed")
		"cmd_error":
			Sfx.play("cmd_error")
		"forbidden":
			Sfx.play("forbidden")
		"bell":
			Sfx.play("bell")
		"over":
			Sfx.play("over")
			_dawn.visible = true
			_over_at = Time.get_ticks_msec()
	return false


@warning_ignore("integer_division")
func _refresh() -> void:
	var s := sim.snapshot()
	var minutes := int(s["tick"]) / B.TICK_HZ  # 1 秒 = 画面の 1 分(4 時間 ÷ 240 秒)
	_bar["clock"].text = "%02d:%02d" % [2 + minutes / 60, minutes % 60]
	_bar["uptime"].text = S.BAR_UPTIME % Score.pct1(int(s["uptime100"]))
	var m := int(s["mttr10"])
	_bar["mttr"].text = S.BAR_MTTR_NONE if m < 0 else S.BAR_MTTR % Score.sec1(m)
	_bar["keys"].text = S.BAR_KEYS % int(s["keys"])
	var sec := int(s["tick"]) / B.TICK_HZ
	if sec != _spark_sec:
		_spark_sec = sec
		history.append(int(s["health"]))
	monitor.update_snap(s)
	terminal.update_snap(s)
	_edge.queue_redraw()
	queue_redraw()


# 上の帯の右: 稼働の折れ線と難しさの札。
func _draw() -> void:
	if sim == null:
		return
	var box := Rect2(900, 12, 240, 36)
	draw_rect(box, Kit.C_PANEL)
	draw_rect(box, Kit.C_EDGE, false, 1.0)
	draw_line(Vector2(box.position.x, box.position.y + 4), Vector2(box.end.x, box.position.y + 4), Color(Kit.C_GOOD, 0.15), 1.0)
	Kit.draw_health(self, box.grow(-3), history.slice(maxi(history.size() - B.SPARK_SECONDS, 0)), B.SPARK_SECONDS)
	var easy: bool = sim.easy
	var tag := Rect2(1152, 14, 104, 32)
	draw_rect(tag, Color(Kit.C_GOOD, 0.14) if easy else Color(1, 1, 1, 0.04))
	draw_rect(tag, Kit.C_GOOD if easy else Kit.C_EDGE, false, 2.0)
	draw_string(Kit.font(700), tag.position + Vector2(0, 22), S.LEVEL[1 if easy else 0], HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 16,
		Kit.C_GOOD if easy else Kit.C_DIM)
