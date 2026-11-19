# S2 プレイ。sim をたまった時間ぶん進め(1 フレーム 8 tick まで)、events で演出と音を出し、snapshot を監視と端末に渡す。
# ゲームの決まりは持たない(INV-1)。打鍵は ui/keymap で番号にして sim.queue_key に渡すだけ。
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
	_dawn = Kit.label(S.DAWN, 48, Kit.C_TEXT, 800)
	Kit.place(_dawn, 0, 300, 1280, 120)
	_dawn.visible = false
	add_child(_dawn)


func start(p_mode: int, p_seed: int) -> void:
	mode = p_mode
	seed_value = p_seed
	sim = Sim.new(p_seed, p_mode)
	paused = false
	_acc = 0.0
	_over_at = -1
	_dawn.visible = false
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
			Sfx.play("alert")
		"escalated":
			monitor.flash(int(e["id"]))
			Sfx.play("escalated")
			_shake_until = Time.get_ticks_msec() + B.SHAKE_MS
		"fixed":
			monitor.ghost(int(e["id"]))
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
	monitor.update_snap(s)
	terminal.update_snap(s)
