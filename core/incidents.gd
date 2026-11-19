# 障害 6 種(仕様書 §9.7)。起きた時に状態を変える・直ったかを見る・直すコマンドの文を作る。
# 障害 1 件は辞書 { id, kind, origin, server, start, fixed, left, total, escalated, nth }。
extends RefCounted

const B := preload("res://core/balance.gd")
const S := preload("res://core/strings.gd")
const Srv := preload("res://core/servers.gd")

const DOWN := 1
const DISK := 2
const LEAK := 3
const CERT := 4
const QUEUE := 5
const BACKUP := 6


static func make(id: int, kind: int, server: int, tick: int, nth: int) -> Dictionary:
	var total := 0
	if kind == DISK:
		total = B.DISK_ESCALATE
	elif kind == LEAK:
		total = B.LEAK_ESCALATE
	return {"id": id, "kind": kind, "origin": kind, "server": server, "start": tick, "fixed": -1,
		"left": total, "total": total, "escalated": false, "nth": nth}


# 起きた時に状態を変える。
static func apply(srv: Srv, inc: Dictionary) -> void:
	var i: int = inc["server"]
	match int(inc["kind"]):
		DOWN:
			srv.svc[i] = Srv.STOPPED
			srv.why[i] = Srv.WHY_CRASH
		DISK:
			srv.disk[i] = B.DISK_ALERT
		LEAK:
			srv.mem[i] = B.MEM_ALERT
		CERT:
			srv.cert_ok[i] = false
		QUEUE:
			srv.queue[i] = B.QUEUE_STUCK
		BACKUP:
			srv.backup_ok = false


# 悪化の時計を 1 tick 進める。止まった tick に真を返す(停止に変わる)。
@warning_ignore("integer_division")
static func tick_escalation(srv: Srv, inc: Dictionary) -> bool:
	if inc["escalated"] or inc["total"] == 0:
		return false
	var i: int = inc["server"]
	# コマンドで空けた・再起動した後は、値を書き戻さない(この step の直ったかの判定に任せる)
	if (inc["origin"] == DISK and srv.disk[i] < B.DISK_ALERT) or (inc["origin"] == LEAK and srv.mem[i] < B.MEM_ALERT):
		return false
	inc["left"] = int(inc["left"]) - 1
	var done: int = int(inc["total"]) - int(inc["left"])
	if inc["origin"] == DISK:
		srv.disk[i] = B.DISK_ALERT + (B.DISK_FULL - B.DISK_ALERT) * done / int(inc["total"])
	else:
		srv.mem[i] = B.MEM_ALERT + (B.MEM_FULL - B.MEM_ALERT) * done / int(inc["total"])
	if int(inc["left"]) > 0:
		return false
	inc["escalated"] = true
	inc["kind"] = DOWN
	srv.svc[i] = Srv.STOPPED
	srv.why[i] = Srv.WHY_DISK if inc["origin"] == DISK else Srv.WHY_OOM
	return true


# 直ったか(毎 step に見る)。
static func resolved(srv: Srv, inc: Dictionary) -> bool:
	var i: int = inc["server"]
	match int(inc["kind"]):
		DOWN:
			return srv.up(i)
		DISK:
			return srv.disk[i] < B.DISK_ALERT and srv.up(i)
		LEAK:
			return srv.mem[i] < B.MEM_ALERT and srv.up(i)
		CERT:
			return srv.cert_ok[i]
		QUEUE:
			return srv.queue[i] == 0
		BACKUP:
			return srv.backup_ok
	return false


# 次に打つ正解のコマンド(そのサーバーで)。停止とディスクが重なっていればディスクから(§9.7・E-6)。
static func fix_command(srv: Srv, inc: Dictionary) -> String:
	var i: int = inc["server"]
	var restart := "%s %s %s %s" % [S.W_SUDO, S.W_SYSTEMCTL, S.W_RESTART, S.SERVICES[i]]
	var vacuum := "%s %s %s" % [S.W_SUDO, S.W_JOURNALCTL, S.A_VACUUM]
	match int(inc["kind"]):
		DOWN:
			return vacuum if srv.disk[i] >= B.DISK_ALERT else restart
		DISK:
			return vacuum
		LEAK:
			return restart
		CERT:
			return "%s %s %s" % [S.W_SUDO, S.W_CERTBOT, S.A_RENEW]
		QUEUE:
			return "%s %s %s" % [S.W_SUDO, S.W_POSTQUEUE, S.A_FLUSH]
		BACKUP:
			return "%s %s %s %s" % [S.W_SUDO, S.W_SYSTEMCTL, S.W_START, S.A_BACKUP]
	return ""


# アラートの行の文(§9.7)。
static func text(srv: Srv, inc: Dictionary) -> String:
	var i: int = inc["server"]
	match int(inc["kind"]):
		DOWN:
			return S.KIND_TEXT[DOWN] % S.SERVICES[i]
		DISK:
			return S.KIND_TEXT[DISK] % srv.disk[i]
		LEAK:
			return S.KIND_TEXT[LEAK] % srv.mem[i]
		QUEUE:
			return S.KIND_TEXT[QUEUE] % srv.queue[i]
	return S.KIND_TEXT[int(inc["kind"])]


# 下書き(§9.11 の表)。n は、その夜でその種類が出た回数。full なら n に関わらず全部(研修の夜)。
static func hint(srv: Srv, inc: Dictionary, full: bool) -> String:
	var n: int = inc["nth"]
	if not full and n >= 3:
		return ""
	var head := "%s %s" % [S.W_SSH, S.SERVERS[int(inc["server"])]]
	var cmd := fix_command(srv, inc)
	if not full and n == 2:
		cmd = cmd.split(" ")[0] + S.HINT_MORE
	return head + S.HINT_ARROW + cmd
