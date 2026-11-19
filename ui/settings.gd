# S4 設定(共通 §6)。音量(5 段)・画面の揺れ・点滅を弱める。変えたらすぐ保存し、音量はその音量で 1 回鳴らす。
# ← → でも値を変えられる。Esc か「戻る」で来た画面へ。
extends Control

signal back

const B := preload("res://core/balance.gd")
const S := preload("res://core/strings.gd")
const Kit := preload("res://ui/kit.gd")
const Menu := preload("res://ui/menu.gd")

var menu: Menu
var store: RefCounted
var _vol: Button
var _shake: Button
var _flash: Button


func build(p_store: RefCounted) -> void:
	store = p_store
	size = Vector2(1280, 720)
	add_child(Kit.place(Kit.label(S.SETTINGS, 40, Kit.C_TEXT, 700), 0, 60, 1280, 60))
	_vol = Kit.place(Kit.button("volume", "", 26), 390, 180, 500, 72)
	_shake = Kit.place(Kit.button("shake", "", 26), 390, 270, 500, 72)
	_flash = Kit.place(Kit.button("reduce_flash", "", 26), 390, 360, 500, 72)
	var ret := Kit.place(Kit.button("back", S.B_BACK, 26), 520, 480, 240, 72)
	for b: Button in [_vol, _shake, _flash, ret]:
		add_child(b)
	_vol.pressed.connect(func() -> void: _step_volume(1))
	_shake.pressed.connect(func() -> void: _toggle("shake"))
	_flash.pressed.connect(func() -> void: _toggle("reduce_flash"))
	ret.pressed.connect(func() -> void: back.emit())
	menu = Menu.new([_vol, _shake, _flash, ret] as Array[Button], 0)
	_paint()


func _paint() -> void:
	var st: Dictionary = store.settings()
	_vol.text = "%s  %d" % [S.SET_VOLUME, int(st["volume"])]
	_shake.text = "%s  %s" % [S.SET_SHAKE, S.ON if st["shake"] else S.OFF]
	_flash.text = "%s  %s" % [S.SET_FLASH, S.ON if st["reduce_flash"] else S.OFF]


func _step_volume(d: int) -> void:
	var i: int = B.VOLUMES.find(int(store.settings()["volume"]))
	var v: int = B.VOLUMES[(i + d + B.VOLUMES.size()) % B.VOLUMES.size()]
	store.set_setting("volume", v)
	Sfx.set_volume(v)
	Sfx.play("fixed")
	_paint()


func _toggle(k: String) -> void:
	store.set_setting(k, not store.settings()[k])
	_paint()


func key(ev: InputEventKey) -> void:
	if not ev.pressed or ev.echo:
		return
	if ev.physical_keycode == KEY_ESCAPE:
		back.emit()
	elif menu.sel == 0 and ev.physical_keycode in [KEY_LEFT, KEY_RIGHT]:
		_step_volume(-1 if ev.physical_keycode == KEY_LEFT else 1)
	elif menu.sel in [1, 2] and ev.physical_keycode in [KEY_LEFT, KEY_RIGHT]:
		_toggle("shake" if menu.sel == 1 else "reduce_flash")
	else:
		menu.key(ev)
