# テストの土台。ok / eq で確かめ、失敗は errors にたまる。夜を組み立てて打つ道具も持つ。
# 各テストは最後に true を返す(途中で止まったことを見分けるため)。
extends RefCounted

const B := preload("res://core/balance.gd")
const S := preload("res://core/strings.gd")
const Sim := preload("res://core/sim.gd")
const Ed := preload("res://core/line_editor.gd")
const I := preload("res://core/incidents.gd")
const Srv := preload("res://core/servers.gd")

var errors: Array = []


func ok(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)


func eq(got: Variant, want: Variant, msg: String) -> void:
	if typeof(got) != typeof(want) or got != want:
		errors.append("%s: %s のはずが %s" % [msg, want, got])


# 障害の無い夜(練習の夜の形)。plan で障害を差し替える。
static func night(plan: Array = []) -> Sim:
	return Sim.new(1, Sim.MODE_PRACTICE, plan)


# 文字を打つ(大文字もそのまま渡す)。Enter は "\n"。次の step で入る。
static func send(sim: Sim, text: String) -> void:
	for k in text.length():
		var c := text.unicode_at(k)
		sim.queue_key(Ed.K_ENTER if c == 10 else c)


static func run(sim: Sim, ticks: int) -> Array:
	var ev: Array = []
	for k in ticks:
		sim.step()
		ev.append_array(sim.events())
	return ev


# 実行中のコマンドが終わるまで進める(打った行は次の step で入る)。
static func settle(sim: Sim) -> Array:
	var ev := run(sim, 1)
	var guard := 0
	while sim.is_running() and guard < 10000:
		sim.step()
		ev.append_array(sim.events())
		guard += 1
	return ev


# 打って Enter し、終わるまで進める。
static func cmd(sim: Sim, line: String) -> Array:
	send(sim, line + "\n")
	return settle(sim)


static func types(ev: Array) -> Array:
	return ev.map(func(e: Dictionary) -> String: return e["type"])


static func last_text(sim: Sim) -> String:
	return sim.lines[sim.lines.size() - 1][0] if not sim.lines.is_empty() else ""


static func texts(sim: Sim) -> Array:
	return sim.lines.map(func(l: Array) -> String: return l[0])


static func at(sec: float, kind: int, server: int) -> Dictionary:
	return {"t": int(sec * B.TICK_HZ), "kind": kind, "server": server}


static func active_kinds(sim: Sim) -> Array:
	return sim.active().map(func(inc: Dictionary) -> Array: return [inc["kind"], inc["server"]])
