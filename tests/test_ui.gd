# 画面の流れのテスト(AC-18〜AC-20・FR-21・FR-25・FR-28)。main.tscn を木に置き、キーのイベントを直接渡し、フレームは _process を呼んで進める。
extends "res://tests/suite.gd"

const MainScene := preload("res://ui/main.tscn")
const Store := preload("res://save/save_store.gd")


static func kev(pk: int, unicode: int = 0, echo: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.pressed = true
	e.physical_keycode = pk as Key
	e.keycode = pk as Key
	e.unicode = unicode
	e.echo = echo
	return e


func _main() -> Node:
	var p := ProjectSettings.globalize_path(Store.PATH)
	if FileAccess.file_exists(Store.PATH):
		DirAccess.remove_absolute(p)
	var m := MainScene.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(m)
	return m


func _done(m: Node) -> void:
	m.get_parent().remove_child(m)
	m.free()


static func press(m: Node, pk: int, unicode: int = 0) -> void:
	m._input(kev(pk, unicode))


static func typed(m: Node, text: String) -> void:
	for k in text.length():
		var c := text.unicode_at(k)
		press(m, KEY_A if c >= 97 and c <= 122 else KEY_SPACE if c == 32 else KEY_0, c)


static func frames(m: Node, n: int, dt: float = 1.0 / 60.0) -> void:
	for k in n:
		if m.play != null:
			m.play._process(dt)
		if m.current != null and m.current.has_method("_process") and m.current != m.play:
			m.current._process(dt)


func test_ac18_flow_keyboard_only() -> bool:
	var m := _main()
	eq(m.screen, "gate", "S0 から始まる")
	press(m, KEY_X, 120)
	eq(m.screen, "title", "どれかのキーで S1")
	ok(m.play == null, "S0 のキーはゲームの操作に数えない")
	eq(String(m.current.menu.buttons[0].name), "training", "研修を終えるまでは研修の夜が一番上(FR-28)")
	press(m, KEY_DOWN)
	press(m, KEY_ENTER)
	eq(m.screen, "play", "Enter で今日の夜")
	eq(int(m.night["mode"]), 0, "今日の夜")
	typed(m, "ssh db01")
	frames(m, 2)
	eq(m.play.sim.ed.text, "ssh db01", "打った文字が端末に入る")
	press(m, KEY_ENTER)
	frames(m, 40)
	eq(m.play.sim.loc, 3, "ssh が効く")
	# 夜を終わらせる
	while not m.play.sim.is_over():
		m.play.sim.step()
	frames(m, 1)
	m.play.finished.emit(m.play.sim.result())  # 夜が明けた後の 600 ms を待たない
	eq(m.screen, "result", "夜が明けると S3")
	var seed_before: int = m.night["seed"]
	m.current._shown_at -= 1000
	frames(m, 1)
	press(m, KEY_ENTER)
	eq(m.screen, "play", "もう1回(Enter)")
	eq(int(m.night["seed"]), seed_before, "今日の夜は同じ種(FR-21)")
	_done(m)
	return true


func test_result_retry_locked_300ms() -> bool:
	var m := _main()
	press(m, KEY_X, 120)
	press(m, KEY_DOWN)
	press(m, KEY_DOWN)
	press(m, KEY_ENTER)
	eq(int(m.night["mode"]), 2, "練習の夜")
	while not m.play.sim.is_over():
		m.play.sim.step()
	frames(m, 1)
	m.play.finished.emit(m.play.sim.result())  # 夜が明けた後の 600 ms を待たない
	press(m, KEY_R)
	eq(m.screen, "result", "300 ms の前は押せない")
	ok(m.current.share.begins_with("RootCall "), "共有する文字")
	ok(m.store.practice_best() != null, "練習の夜の最高を保存")
	_done(m)
	return true


func test_ac19_pause_freezes() -> bool:
	var m := _main()
	press(m, KEY_X, 120)
	press(m, KEY_ENTER)  # 研修の夜
	eq(int(m.night["mode"]), 1, "研修の夜")
	frames(m, 30)
	typed(m, "ssh")
	frames(m, 2)
	press(m, KEY_ESCAPE)
	ok(m.pause_view != null, "Esc で一時停止")
	var t: int = m.play.sim.tick
	frames(m, 120)
	eq(m.play.sim.tick, t, "時計が止まる")
	eq(m.play.sim.ed.text, "ssh", "打ちかけの行が残る")
	m._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	press(m, KEY_ESCAPE)
	ok(m.pause_view == null, "Esc で続ける")
	frames(m, 2)
	ok(m.play.sim.tick > t, "続けると進む")
	m._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	ok(m.pause_view != null, "フォーカスが外れると一時停止(E-13)")
	_done(m)
	return true


func test_pause_settings_back() -> bool:
	var m := _main()
	press(m, KEY_X, 120)
	press(m, KEY_ENTER)
	press(m, KEY_ESCAPE)
	press(m, KEY_DOWN)
	press(m, KEY_DOWN)
	press(m, KEY_ENTER)
	eq(m.screen, "settings", "一時停止から設定")
	press(m, KEY_DOWN)
	press(m, KEY_ENTER)  # 揺れを切る
	eq(m.store.settings()["shake"], false, "揺れを切って保存")
	press(m, KEY_ESCAPE)
	eq(m.screen, "play", "戻ると一時停止へ")
	ok(m.pause_view != null and m.pause_view.visible, "一時停止の画面")
	eq(m.play.shake_on, false, "設定がプレイに届く")
	_done(m)
	return true


func test_ac20_no_shake_when_off() -> bool:
	var m := _main()
	m.store.set_setting("shake", false)
	press(m, KEY_X, 120)
	press(m, KEY_DOWN)
	press(m, KEY_DOWN)
	press(m, KEY_ENTER)
	m.play._on_event({"type": "escalated", "id": 1})
	frames(m, 3)
	eq(m.play.position, Vector2.ZERO, "揺れを切ると動かない")
	m.play.shake_on = true
	m.play._on_event({"type": "escalated", "id": 1})
	var moved := false
	for k in 5:
		frames(m, 1, 0.0)
		moved = moved or m.play.position != Vector2.ZERO
	ok(moved, "入なら揺れる")
	_done(m)
	return true


func test_modifier_and_echo_keys() -> bool:
	var m := _main()
	press(m, KEY_X, 120)
	press(m, KEY_DOWN)
	press(m, KEY_ENTER)
	var e := kev(KEY_A, 97)
	e.ctrl_pressed = true
	m._input(e)
	m._input(kev(KEY_B, 98, true))
	press(m, KEY_C, 99)
	m._input(kev(KEY_BACKSPACE, 0, true))
	frames(m, 2)
	eq(m.play.sim.ed.text, "", "Ctrl と一緒・押しっぱなしの文字は数えず、押しっぱなしの BackSpace は数える")
	eq(m.play.sim.ed.keys, 2, "打鍵の数(c と BackSpace)")
	_done(m)
	return true


func test_gate_ignores_touch_mouse() -> bool:
	var m := _main()
	var t := InputEventScreenTouch.new()
	t.pressed = true
	m._input(t)
	var mb := InputEventMouseButton.new()
	mb.pressed = true
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.device = InputEvent.DEVICE_ID_EMULATION
	m._input(mb)
	eq(m.screen, "gate", "タッチと、そこから作られたマウスでは進まない(FR-29)")
	ok(m._touch_note.visible, "キーボードで遊ぶ案内が出る")
	_done(m)
	return true


func test_result_ignores_modifier_keys() -> bool:
	var m := _main()
	press(m, KEY_X, 120)
	press(m, KEY_DOWN)
	press(m, KEY_DOWN)
	press(m, KEY_ENTER)
	while not m.play.sim.is_over():
		m.play.sim.step()
	frames(m, 1)
	m.play.finished.emit(m.play.sim.result())
	m.current._shown_at -= 1000
	frames(m, 1)
	var e := kev(KEY_R, 114)
	e.ctrl_pressed = true
	m._input(e)
	var e2 := kev(KEY_ENTER)
	e2.alt_pressed = true
	m._input(e2)
	eq(m.screen, "result", "Ctrl・Alt 付きの R・Enter ではもう1回にならない(FR-27)")
	press(m, KEY_R, 114)
	eq(m.screen, "play", "R だけならもう1回")
	_done(m)
	return true
