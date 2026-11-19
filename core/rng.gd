# 夜の並びの乱数(xorshift32。DashCut 仕様書 §9.2 と同じ式)。
# 端末や版で結果が変わらないよう、Godot の乱数関数は使わない(INV-2)。
extends RefCounted

const MASK := 0xFFFFFFFF

var state: int = 1


func _init(seed_value: int = 1) -> void:
	state = seed_value & MASK
	if state == 0:
		state = 1


func next() -> int:
	var x := state
	x = x ^ ((x << 13) & MASK)
	x = x ^ (x >> 17)
	x = x ^ ((x << 5) & MASK)
	state = x
	return x


# 0 以上 n 未満(仕様書の rng.range。range は組み込みの名前なので next_int にした)。
func next_int(n: int) -> int:
	return next() % n
