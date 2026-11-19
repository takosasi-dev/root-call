# 1 回の夜の全状態と step()(仕様書 §9.3)。入力はキーの番号(整数)だけ(INV-4)。
# ui と audio は events() と snapshot() を読むだけ(INV-1)。step の中の順番は §9.3 のとおりで、変えない。
extends RefCounted

const B := preload("res://core/balance.gd")
const S := preload("res://core/strings.gd")
const Srv := preload("res://core/servers.gd")
const Ed := preload("res://core/line_editor.gd")
const I := preload("res://core/incidents.gd")
const Sched := preload("res://core/schedule.gd")
const Shell := preload("res://core/shell.gd")
const Score := preload("res://core/score.gd")

const MODE_DAILY := 0
const MODE_TRAINING := 1
const MODE_PRACTICE := 2

var seed_value := 1
var mode := MODE_DAILY
var easy := false  # やさしい(間隔・悪化・実行の時間・短い形・空の行の Tab)
var tick := 0
var over := false
var srv := Srv.new()
var ed := Ed.new()
var loc := -1  # 今いるサーバー。-1 = jump
var lines: Array = []  # 端末の行 [文, 種類(shell.gd の L_*)]
var running: Dictionary = {}  # { op, left, total }
var incidents: Array = []
var plan: Array = []
var plan_i := 0
var health_sum := 0
var impact_since: Array[int] = [-1, -1, -1, -1, -1, -1]
var _seen := {}  # 種類 → その夜で出た回数
var _keys: Array[int] = []
var _events: Array = []
var _next_id := 1


# plan_override はテスト用(障害の並びを差し替える)。
func _init(p_seed: int, p_mode: int, plan_override: Variant = null, p_easy: bool = false) -> void:
	seed_value = p_seed
	mode = p_mode
	easy = p_easy
	if plan_override is Array:
		plan = plan_override
	elif mode == MODE_TRAINING:
		plan = Sched.training()
	else:
		plan = Sched.build(p_seed, easy)
	if mode == MODE_TRAINING:
		for s: String in (S.GUIDE_EASY if easy else S.GUIDE):
			out(s, Shell.L_INFO)


func queue_key(code: int) -> void:
	_keys.append(code)


func step() -> void:
	_events = []
	if over:
		return
	# 2. 実行中のコマンド
	if not running.is_empty():
		running["left"] = int(running["left"]) - 1
		if int(running["left"]) <= 0:
			var op: Dictionary = running["op"]
			running = {}
			Shell.finish(self, op)
	# 3. 打鍵
	for code in _keys:
		_key(code)
	_keys.clear()
	# 4. 予定された障害
	while plan_i < plan.size() and int(plan[plan_i]["t"]) <= tick:
		_spawn(int(plan[plan_i]["kind"]), int(plan[plan_i]["server"]))
		plan_i += 1
	# 5. 悪化
	for inc: Dictionary in incidents:
		if int(inc["fixed"]) < 0 and I.tick_escalation(srv, inc):
			emit_event({"type": "escalated", "id": inc["id"], "server": inc["server"]})
	# 6. 直った物と影響
	_resolve()
	for i in Srv.COUNT:
		if srv.impact(i) != 0:
			if impact_since[i] < 0:
				impact_since[i] = tick
		else:
			impact_since[i] = -1
	# 7. 健全さ
	health_sum += srv.health()
	# 8. 時間
	tick += 1
	if tick >= B.NIGHT_TICKS:
		over = true
		running = {}  # E-10
		emit_event({"type": "over"})


func events() -> Array:
	return _events


func is_over() -> bool:
	return over


func is_running() -> bool:
	return not running.is_empty()


func _key(code: int) -> void:
	var r := ed.press(code)
	if r == Ed.DROPPED:
		return
	emit_event({"type": "key"})
	if r == Ed.ENTER:
		if is_running():
			return  # E-4
		var line := ed.text
		out(prompt() + line, Shell.L_PROMPT)
		ed.commit()
		Shell.execute(self, line)
	elif r == Ed.TAB:
		if easy and ed.text.strip_edges().is_empty() and _fill_fix():
			return
		var res := ed.complete(Shell.candidates(ed.words_before(), loc, easy))
		if res["result"] == "none":
			emit_event({"type": "bell"})
		elif res["result"] == "list":
			out(prompt() + ed.text, Shell.L_PROMPT)
			out("  ".join(res["list"]), Shell.L_INFO)


# やさしい: 空の行の Tab で、今いるサーバーの一番古い障害を直す短い形を入れる。無ければ偽(ふつうの補完へ)。
func _fill_fix() -> bool:
	if loc < 0:
		return false
	for inc: Dictionary in active():
		if int(inc["server"]) == loc:
			ed._put_line(I.short_command(srv, inc))
			return true
	return false


func _spawn(kind: int, server: int) -> void:
	for inc: Dictionary in incidents:
		if int(inc["fixed"]) < 0 and int(inc["kind"]) == kind and int(inc["server"]) == server:
			return  # D-11・E-9
	_seen[kind] = int(_seen.get(kind, 0)) + 1
	var inc := I.make(_next_id, kind, server, tick, _seen[kind], easy)
	_next_id += 1
	I.apply(srv, inc)
	incidents.append(inc)
	emit_event({"type": "incident", "id": inc["id"], "kind": kind, "server": server})


func _resolve() -> void:
	for inc: Dictionary in incidents:
		if int(inc["fixed"]) < 0 and I.resolved(srv, inc):
			inc["fixed"] = tick
			@warning_ignore("integer_division")
			var secs10: int = (tick - int(inc["start"])) * 10 / B.TICK_HZ
			emit_event({"type": "fixed", "id": inc["id"], "server": inc["server"], "secs10": secs10})
			out(S.R_FIXED % Score.sec1(secs10), Shell.L_GOOD)


# --- shell.gd から呼ぶ ---

func out(text: String, kind: String) -> void:
	lines.append([text, kind])
	if lines.size() > B.SCREEN_MAX:
		lines.pop_front()


func clear_screen() -> void:
	lines.clear()


func emit_event(e: Dictionary) -> void:
	_events.append(e)


func begin(op: Dictionary, ticks: int) -> void:
	@warning_ignore("integer_division")
	var t := ticks / B.EASY_RUN_DIV if easy else ticks
	running = {"op": op, "left": t, "total": t}


# 再起動に失敗して止まった。止まりを数える障害がまだ無ければ「停止」を足す(§9.5 の app の決まり)。
func restart_failed(server: int) -> void:
	for inc: Dictionary in incidents:
		if int(inc["fixed"]) < 0 and int(inc["kind"]) == I.DOWN and int(inc["server"]) == server:
			return
	_spawn(I.DOWN, server)


func prompt() -> String:
	return S.PROMPT % (S.JUMP if loc < 0 else S.SERVERS[loc])


# --- 読むだけ ---

func active() -> Array:
	return incidents.filter(func(inc: Dictionary) -> bool: return int(inc["fixed"]) < 0)


# アラートの一覧(§9.11)。起きた順。同じ tick なら障害の行が先。
func alert_rows() -> Array:
	var full := mode == MODE_TRAINING
	var rows: Array = []
	for inc: Dictionary in active():
		var esc: bool = int(inc["total"]) > 0 and not inc["escalated"]
		rows.append({"server": inc["server"], "text": I.text(srv, inc), "start": inc["start"], "id": inc["id"],
			"class": "down" if int(inc["kind"]) == I.DOWN else "warn", "incident": true,
			"left": int(inc["left"]) if esc else -1, "total": int(inc["total"]) if esc else 0,
			"hint": I.hint(srv, inc, full, easy), "explain": S.EXPLAIN[int(inc["origin"])] if full else "", "upstream": ""})
	for i in Srv.COUNT:
		var imp := srv.impact(i)
		if imp != 0 and impact_since[i] >= 0:
			rows.append({"server": i, "text": [S.IMPACT_502, S.IMPACT_DB, S.IMPACT_SLOW][imp - 1], "start": impact_since[i],
				"id": 100000 + i, "class": "impact", "incident": false, "left": -1, "total": 0, "hint": "",
				"explain": S.EXPLAIN[0] if full else "", "upstream": S.UPSTREAM if full else ""})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["start"] != b["start"]:
			return a["start"] < b["start"]
		return a["id"] < b["id"])
	return rows


func _card(i: int) -> String:
	if srv.svc[i] == Srv.STOPPED:
		return "down"
	if srv.svc[i] == Srv.RESTARTING:
		return "restart"
	for inc: Dictionary in active():
		if int(inc["server"]) == i:
			return "warn"
	return "impact" if srv.impact(i) != 0 else "ok"


func snapshot() -> Dictionary:
	var servers: Array = []
	for i in Srv.COUNT:
		var left := -1
		var total := 0
		for inc: Dictionary in active():
			if int(inc["server"]) == i and int(inc["total"]) > 0 and not inc["escalated"]:
				left = int(inc["left"])
				total = int(inc["total"])
		var cause := active().any(func(inc: Dictionary) -> bool: return int(inc["server"]) == i)
		servers.append({"name": S.SERVERS[i], "service": S.SERVICES[i], "card": _card(i), "cause": cause, "disk": srv.disk[i],
			"mem": srv.mem[i], "left": left, "total": total})
	return {
		"tick": tick, "over": over, "mode": mode, "easy": easy, "loc": loc, "prompt": prompt(), "line": ed.text, "cursor": ed.cursor,
		"keys": ed.keys, "running": is_running(), "run_left": int(running.get("left", 0)), "run_total": int(running.get("total", 0)),
		"lines": lines, "servers": servers, "edges": srv.edges_hot(), "alerts": alert_rows(),
		"uptime100": Score.uptime100(health_sum, tick), "mttr10": Score.mttr10(incidents, tick, true), "health": srv.health(),
	}


func result() -> Dictionary:
	var end := mini(tick, B.NIGHT_TICKS)
	var backups := 0
	var fixed := 0
	for inc: Dictionary in incidents:
		if int(inc["fixed"]) >= 0:
			fixed += 1
		elif int(inc["kind"]) == I.BACKUP:
			backups += 1
	var up := Score.uptime100(health_sum, end)
	return {"uptime100": up, "mttr10": maxi(Score.mttr10(incidents, end, false), 0), "keys": ed.keys, "fixed": fixed,
		"incidents": incidents.size(), "backups_left": backups, "points": Score.points(up, backups)}
