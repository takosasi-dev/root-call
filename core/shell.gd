# コマンドの解釈と出力(仕様書 §9.5)。行を語に分け、表と照らして、すぐ答えるか実行の時間に回す。
# 実行の時間が終わった step で finish() が結果を出す。状態は sim の srv を書き換える。
extends RefCounted

const B := preload("res://core/balance.gd")
const S := preload("res://core/strings.gd")
const Srv := preload("res://core/servers.gd")

# 端末の行の種類
const L_PROMPT := "p"
const L_OUT := "o"
const L_ERR := "e"
const L_GOOD := "g"
const L_INFO := "i"


# 小文字にそろえ、前後の空白を除き、続いた空白を 1 つにして語に分ける。
static func words(line: String) -> Array:
	var out: Array = []
	for w in line.to_lower().split(" ", false):
		out.append(w)
	return out


# 補完の候補(§9.4 の表)。before は補う語の前にある語、loc は今いるサーバー(-1 = jump)。
static func candidates(before: Array, loc: int) -> Array:
	var w := before
	if w.is_empty():
		return S.C_FIRST_JUMP if loc < 0 else S.C_FIRST_SERVER
	if w[0] == S.W_SUDO:
		w = w.slice(1)
		if w.is_empty():
			return S.C_SUDO
	if w.size() == 1:
		match w[0]:
			S.W_SSH:
				return S.SERVERS
			S.W_SYSTEMCTL:
				return S.C_SYSTEMCTL
			S.W_JOURNALCTL:
				return [S.A_VACUUM]
			S.W_CERTBOT:
				return [S.A_RENEW]
			S.W_POSTQUEUE:
				return [S.A_FLUSH]
			S.W_DF:
				return [S.A_DF]
			S.W_FREE:
				return [S.A_FREE]
	if w.size() == 2 and w[0] == S.W_SYSTEMCTL and loc >= 0:
		if w[1] == S.W_STATUS or w[1] == S.W_RESTART:
			return [S.SERVICES[loc]]
		if w[1] == S.W_START and loc == Srv.DB:
			return [S.A_BACKUP]
	return []


# 1 行を実行する。実行の時間があれば sim.begin(op, ticks) に回す。
static func execute(sim: RefCounted, line: String) -> void:
	var all := words(line)
	if all.is_empty():
		return
	var sudo: bool = all[0] == S.W_SUDO
	var w: Array = all.slice(1) if sudo else all
	if w.is_empty():
		_error(sim, S.E_NOT_FOUND % S.W_SUDO)
		return
	if w[0] in S.FORBIDDEN_WORDS:
		sim.out(S.E_FORBIDDEN, L_ERR)
		sim.emit_event({"type": "forbidden"})
		return
	var loc: int = sim.loc
	var whole := " ".join(w)
	match w[0]:
		S.W_SSH:
			var host: String = w[1] if w.size() == 2 else (" ".join(w.slice(1)))
			var to := S.SERVERS.find(host)
			if to < 0:
				_error(sim, S.E_NO_HOST % host)
				return
			sim.begin({"op": "ssh", "server": to}, B.T_SSH)
		S.W_EXIT:
			if loc < 0:
				_error(sim, S.E_JUMP)
				return
			sim.loc = -1
		S.W_STATUS:
			if loc >= 0 or w.size() != 1:
				_error(sim, S.E_NOT_FOUND % whole)
				return
			for i in Srv.COUNT:
				sim.out(S.STATUS_LINE % [S.SERVERS[i], S.SERVICES[i], _state_word(sim.srv, i)], L_OUT)
		S.W_HELP:
			for s: String in S.HELP:
				sim.out(s, L_INFO)
			if sim.mode != 0:
				for s: String in S.HELP_TABLE:
					sim.out(s, L_INFO)
		S.W_CLEAR:
			sim.clear_screen()
		S.W_HISTORY:
			var h: Array = sim.ed.history
			for k in h.size():
				sim.out(S.HISTORY_LINE % [k + 1, h[h.size() - 1 - k]], L_OUT)
		S.W_SYSTEMCTL:
			if loc < 0:
				_error(sim, S.E_JUMP)
				return
			if w.size() != 3 or not (w[1] in S.C_SYSTEMCTL):
				_error(sim, S.E_NOT_FOUND % whole)
				return
			var unit: String = w[2]
			if w[1] == S.W_START:
				if not sudo:
					_error(sim, S.E_NEED_SUDO)
				elif unit != S.A_BACKUP or loc != Srv.DB:
					_error(sim, S.E_NO_UNIT % unit)
				else:
					sim.begin({"op": "backup", "server": loc}, B.T_BACKUP)
				return
			if unit != S.SERVICES[loc]:
				_error(sim, S.E_NO_UNIT % unit)
				return
			if w[1] == S.W_STATUS:
				sim.begin({"op": "unit", "server": loc}, B.T_LOOK)
			elif not sudo:
				_error(sim, S.E_NEED_SUDO)
			else:
				sim.srv.svc[loc] = Srv.RESTARTING  # 実行の間は止まっているものとして数える(D-5)
				sim.begin({"op": "restart", "server": loc}, B.T_RESTART)
		S.W_DF, S.W_FREE:
			if loc < 0:
				_error(sim, S.E_JUMP)
				return
			var arg: String = S.A_DF if w[0] == S.W_DF else S.A_FREE
			if w.size() != 2 or w[1] != arg:
				_error(sim, S.E_NOT_FOUND % whole)
				return
			sim.begin({"op": w[0], "server": loc}, B.T_LOOK)
		S.W_JOURNALCTL:
			_admin(sim, sudo, w, S.A_VACUUM.to_lower(), loc >= 0, {"op": "vacuum", "server": loc}, B.T_VACUUM)
		S.W_CERTBOT:
			_admin(sim, sudo, w, S.A_RENEW, loc == Srv.WEB01 or loc == Srv.WEB02, {"op": "cert", "server": loc}, B.T_CERT)
		S.W_POSTQUEUE:
			_admin(sim, sudo, w, S.A_FLUSH, loc == Srv.MAIL, {"op": "queue", "server": loc}, B.T_QUEUE)
		_:
			_error(sim, S.E_NOT_FOUND % w[0])


# sudo の要る、引数 1 つのコマンド。
static func _admin(sim: RefCounted, sudo: bool, w: Array, arg: String, here: bool, op: Dictionary, ticks: int) -> void:
	if sim.loc < 0:
		_error(sim, S.E_JUMP)
	elif w.size() != 2 or w[1] != arg:
		_error(sim, S.E_NOT_FOUND % " ".join(w))
	elif not here:
		_error(sim, S.E_NOT_HERE % w[0])
	elif not sudo:
		_error(sim, S.E_NEED_SUDO)
	else:
		sim.begin(op, ticks)


static func _error(sim: RefCounted, text: String) -> void:
	sim.out(text, L_ERR)
	sim.emit_event({"type": "cmd_error"})


static func _state_word(srv: Srv, i: int) -> String:
	match srv.svc[i]:
		Srv.STOPPED:
			return S.ST_STOPPED
		Srv.RESTARTING:
			return S.ST_RESTARTING
	return S.ST_RUNNING


# 実行の時間が終わった step に結果を出す(E-5: 終わった時の状態で決める)。
static func finish(sim: RefCounted, op: Dictionary) -> void:
	var srv: Srv = sim.srv
	var i: int = op["server"]
	match op["op"]:
		"ssh":
			sim.loc = i
			sim.out(S.R_SSH % S.SERVERS[i], L_OUT)
		"unit":
			sim.out(S.R_UNIT % [S.SERVICES[i], _state_word(srv, i)], L_OUT)
			sim.out(S.R_LOG % _last_log(srv, i), L_OUT)
		"df":
			sim.out(S.R_DF % srv.disk[i], L_OUT)
		"free":
			sim.out(S.R_FREE % srv.mem[i], L_OUT)
		"restart":
			_finish_restart(sim, srv, i)
		"backup":
			srv.backup_ok = true
			sim.out(S.R_BACKUP, L_OUT)
		"vacuum":
			if srv.disk[i] >= B.DISK_ALERT:
				srv.disk[i] = B.DISK_NORMAL
			sim.out(S.R_VACUUM % srv.disk[i], L_OUT)
		"cert":
			srv.cert_ok[i] = true
			sim.out(S.R_CERT, L_OUT)
		"queue":
			var n := srv.queue[i]
			srv.queue[i] = 0
			sim.out(S.R_QUEUE % n, L_OUT)


static func _finish_restart(sim: RefCounted, srv: Srv, i: int) -> void:
	var name: String = S.SERVICES[i]
	if i == Srv.APP:
		if not srv.up(Srv.DB):
			_fail(sim, srv, i, Srv.WHY_DB, S.R_APP_FAIL)
			return
		_start(srv, i)
		srv.mem[i] = B.MEM_NORMAL
		sim.out(S.R_APP_SLOW if not srv.up(Srv.CACHE) else S.R_RESTARTED % name, L_OUT)
	elif i == Srv.WEB01 or i == Srv.WEB02:
		_start(srv, i)
		sim.out(S.R_NGINX_502 if not srv.app_responds() else S.R_RESTARTED % name, L_OUT)
	elif srv.disk[i] >= B.DISK_ALERT:
		_fail(sim, srv, i, Srv.WHY_DISK, S.R_DISK_FAIL % name)  # E-6
	else:
		_start(srv, i)
		sim.out(S.R_RESTARTED % name, L_OUT)


static func _start(srv: Srv, i: int) -> void:
	srv.svc[i] = Srv.RUNNING
	srv.why[i] = Srv.WHY_NONE


static func _fail(sim: RefCounted, srv: Srv, i: int, why: int, text: String) -> void:
	srv.svc[i] = Srv.STOPPED
	srv.why[i] = why
	sim.out(text, L_ERR)
	sim.restart_failed(i)


static func _last_log(srv: Srv, i: int) -> String:
	if not srv.up(i):
		match srv.why[i]:
			Srv.WHY_DISK:
				return S.LOG_DISK
			Srv.WHY_OOM:
				return S.LOG_OOM
			Srv.WHY_DB:
				return S.LOG_DB
		return S.LOG_CRASH
	if srv.disk[i] >= B.DISK_ALERT:
		return S.LOG_DISK
	if i == Srv.APP and srv.mem[i] >= B.MEM_ALERT:
		return S.LOG_LEAK
	if i == Srv.APP and not srv.up(Srv.DB):
		return S.LOG_DB
	if i == Srv.APP and not srv.up(Srv.CACHE):
		return S.LOG_CACHE
	return S.LOG_OK
