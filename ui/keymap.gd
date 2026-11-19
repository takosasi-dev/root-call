# 押したキーを、sim に渡す番号(仕様書 §9.4)へ直す。渡さないキーは -1。
# 文字は unicode で取り、特別なキーは physical_keycode で取る。Ctrl・Alt・Meta と一緒のキーと、BackSpace 以外の押しっぱなしは数えない(FR-27)。
extends RefCounted

const Ed := preload("res://core/line_editor.gd")


static func code_of(ev: InputEventKey) -> int:
	if not ev.pressed or ev.ctrl_pressed or ev.alt_pressed or ev.meta_pressed:
		return -1
	var special := -1
	match ev.physical_keycode:
		KEY_ENTER, KEY_KP_ENTER:
			special = Ed.K_ENTER
		KEY_BACKSPACE:
			special = Ed.K_BACKSPACE
		KEY_TAB:
			special = Ed.K_TAB
		KEY_LEFT:
			special = Ed.K_LEFT
		KEY_RIGHT:
			special = Ed.K_RIGHT
		KEY_UP:
			special = Ed.K_UP
		KEY_DOWN:
			special = Ed.K_DOWN
	if ev.echo and special != Ed.K_BACKSPACE:
		return -1
	if special >= 0:
		return special
	return ev.unicode if ev.unicode >= 32 else -1  # 受け付けない文字は core が捨てる(E-1)
