# 夜の障害の並び(仕様書 §9.8)。種だけで決まる(INV-3)。研修の夜は決まった表(INV-6。中身を変えない)。
# 1 件は { t, kind, server }。並びは t の順。
extends RefCounted

const B := preload("res://core/balance.gd")
const Rng := preload("res://core/rng.gd")
const I := preload("res://core/incidents.gd")
const Srv := preload("res://core/servers.gd")

# 研修の夜(§9.8 の表)。[秒, 種類, サーバー]
const TRAINING := [
	[5, I.DOWN, Srv.WEB01],
	[35, I.DOWN, Srv.DB],
	[70, I.DISK, Srv.DB],
	[100, I.LEAK, Srv.APP],
	[130, I.CERT, Srv.WEB02],
	[155, I.QUEUE, Srv.MAIL],
	[180, I.BACKUP, Srv.DB],
	[200, I.DOWN, Srv.CACHE],
	[215, I.DOWN, Srv.APP],
	[215, I.DOWN, Srv.WEB01],
]


static func training() -> Array:
	var out: Array = []
	for e: Array in TRAINING:
		out.append({"t": int(e[0]) * B.TICK_HZ, "kind": e[1], "server": e[2]})
	return out


# easy なら間隔を EASY_GAP_NUM/DEN 倍にする(種類とサーバーの並びは同じ)。
static func build(seed_value: int, easy: bool = false) -> Array:
	var rng := Rng.new(seed_value)
	var total := 0
	for row: Array in B.SCHED_TABLE:
		total += int(row[2])
	var out: Array = []
	var t := B.SCHED_FIRST
	while t < B.SCHED_END:
		var r := rng.next_int(total)
		var acc := 0
		for row: Array in B.SCHED_TABLE:
			acc += int(row[2])
			if acc > r:
				if int(row[0]) == 0:  # 停止 web01 と 停止 web02 の同時
					out.append({"t": t, "kind": I.DOWN, "server": Srv.WEB01})
					out.append({"t": t, "kind": I.DOWN, "server": Srv.WEB02})
				else:
					out.append({"t": t, "kind": int(row[0]), "server": int(row[1])})
				break
		for gap: Array in B.SCHED_GAPS:
			if t < int(gap[0]):
				var g := int(gap[1]) + rng.next_int(int(gap[2]))
				@warning_ignore("integer_division")
				t += g * B.EASY_GAP_NUM / B.EASY_GAP_DEN if easy else g
				break
	return out
