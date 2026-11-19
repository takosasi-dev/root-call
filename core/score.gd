# 稼働率・平均の復旧・点(仕様書 §9.9)。整数だけで数える。
# 稼働率は 1/100 % の整数(86.40% → 8640)、平均の復旧は秒 × 10 の整数(切り捨て)で持つ。
extends RefCounted

const B := preload("res://core/balance.gd")


# 健全さの合計と、数えた tick の数から稼働率(1/100 %)。
@warning_ignore("integer_division")
static func uptime100(health_sum: int, ticks: int) -> int:
	if ticks <= 0:
		return 10000
	return health_sum * 10000 / (20 * ticks)


# 障害の並びから平均の復旧(秒 × 10)。end_tick までに直っていない物は end_tick までを数える。
# fixed_only が真なら、直った物だけで数える(プレイ中の帯)。数える物が無ければ -1。
@warning_ignore("integer_division")
static func mttr10(incidents: Array, end_tick: int, fixed_only: bool) -> int:
	var sum := 0
	var n := 0
	for inc: Dictionary in incidents:
		var f: int = inc["fixed"]
		if f < 0 and fixed_only:
			continue
		sum += (f if f >= 0 else end_tick) - int(inc["start"])
		n += 1
	if n == 0:
		return -1
	return sum * 10 / (n * B.TICK_HZ)


static func points(up100: int, backups_left: int) -> int:
	return up100 - backups_left * B.BACKUP_PENALTY


# 最高の比べ(点、同じなら平均の復旧の短い方)。a が b より良ければ真。
static func better(a: Dictionary, b: Dictionary) -> bool:
	if int(a["points"]) != int(b["points"]):
		return int(a["points"]) > int(b["points"])
	return int(a["mttr10"]) < int(b["mttr10"])


# 1/100 % を小数 1 桁(切り捨て)の文字に。8640 → "86.4"
@warning_ignore("integer_division")
static func pct1(up100: int) -> String:
	return "%d.%d" % [up100 / 100, (up100 % 100) / 10]


# 秒 × 10 を小数 1 桁の文字に。98 → "9.8"
@warning_ignore("integer_division")
static func sec1(v10: int) -> String:
	return "%d.%d" % [v10 / 10, v10 % 10]


# 点の 3 桁区切り。8640 → "8,640"
static func comma(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
