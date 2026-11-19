# 6 台のサーバーの状態と、依存による影響と健全さ(仕様書 §9.2・§9.6・§9.9)。
# 名前は strings.gd の SERVERS・SERVICES。ここは番号で持つ。
extends RefCounted

const B := preload("res://core/balance.gd")

const WEB01 := 0
const WEB02 := 1
const APP := 2
const DB := 3
const CACHE := 4
const MAIL := 5
const COUNT := 6

const RUNNING := 0
const STOPPED := 1
const RESTARTING := 2

# 止まった理由(systemctl status の最後のログ)
const WHY_NONE := 0
const WHY_CRASH := 1
const WHY_DISK := 2
const WHY_OOM := 3
const WHY_DB := 4

var svc: Array[int] = [RUNNING, RUNNING, RUNNING, RUNNING, RUNNING, RUNNING]
var why: Array[int] = [0, 0, 0, 0, 0, 0]
var disk: Array[int] = []
var mem: Array[int] = []
var cert_ok: Array[bool] = [true, true, true, true, true, true]
var queue: Array[int] = [0, 0, 0, 0, 0, 0]
var backup_ok := true


func _init() -> void:
	for i in COUNT:
		disk.append(B.DISK_NORMAL)
		mem.append(B.MEM_NORMAL)


func up(i: int) -> bool:
	return svc[i] == RUNNING


# app01 が応答する = app が動いていて、db01 の postgresql が動いている。
func app_responds() -> bool:
	return up(APP) and up(DB)


func app_slow() -> bool:
	return not up(CACHE)


func web_responds(w: int) -> bool:
	return up(w) and cert_ok[w] and app_responds()


# web の点 s(w)(§9.9)。
func web_score(w: int) -> int:
	if not web_responds(w):
		return 0
	return 1 if app_slow() else 2


func mail_score() -> int:
	return 1 if up(MAIL) and queue[MAIL] == 0 else 0


# 1 tick の健全さ(20 点満点)。
func health() -> int:
	return 4 * (web_score(WEB01) + web_score(WEB02)) + 4 * mail_score()


# 依存で巻き込まれている影響の文の番号。0 = 無し、1 = HTTP 502、2 = DB に接続できない、3 = 応答が遅い。
func impact(i: int) -> int:
	if i == WEB01 or i == WEB02:
		return 1 if not app_responds() else 0
	if i == APP:
		if not up(DB):
			return 2
		if not up(CACHE):
			return 3
	return 0


# 依存の矢印が原因から影響へ伝わっているか。[web01→app, web02→app, app→db, app→cache]
func edges_hot() -> Array:
	return [not app_responds(), not app_responds(), not up(DB), not up(CACHE)]
