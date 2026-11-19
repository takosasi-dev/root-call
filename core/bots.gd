# テスト用の bot(仕様書 §9.14)。12 tick に 1 打鍵。補完は使わずに全部打つ。
# 正解 bot = 一番古い障害の行を直す。症状 bot = 一番古い行(影響を含む)を選び、影響ならそのサーバーを再起動する。
# 影響の行は原因と同じ tick に出るので、症状 bot は同じ時刻なら影響の行を取る(仕様は同じ時刻の扱いを書いていない。取らないと正解 bot と同じ動きになる)。
extends RefCounted

const B := preload("res://core/balance.gd")
const S := preload("res://core/strings.gd")
const I := preload("res://core/incidents.gd")
const Ed := preload("res://core/line_editor.gd")

const CORRECT := 0
const SYMPTOM := 1
const IDLE := 2

var kind := CORRECT
var typing: Array[int] = []
var wait := 0


func _init(p_kind: int) -> void:
	kind = p_kind


# sim.step() の前に毎 tick 呼ぶ。
func act(sim: RefCounted) -> void:
	if kind == IDLE:
		return
	if wait > 0:
		wait -= 1
		return
	if typing.is_empty():
		if sim.is_running():
			return
		var cmd := plan(sim)
		if cmd.is_empty():
			return
		for k in cmd.length():
			typing.append(cmd.unicode_at(k))
		typing.append(Ed.K_ENTER)
	if typing[0] == Ed.K_ENTER and sim.is_running():
		return
	sim.queue_key(typing.pop_front())
	wait = B.BOT_KEY_TICKS - 1


func plan(sim: RefCounted) -> String:
	var target: Dictionary = {}
	for row: Dictionary in sim.alert_rows():
		if kind == SYMPTOM:
			if target.is_empty() or (row["start"] == target["start"] and not row["incident"] and target["incident"]):
				target = row
			continue
		if row["incident"]:
			target = row
			break
	if target.is_empty():
		return ""
	var server: int = target["server"]
	if sim.loc != server:
		return "%s %s" % [S.W_SSH, S.SERVERS[server]]
	if not target["incident"]:
		return "%s %s %s %s" % [S.W_SUDO, S.W_SYSTEMCTL, S.W_RESTART, S.SERVICES[server]]
	for inc: Dictionary in sim.incidents:
		if inc["id"] == target["id"]:
			return I.fix_command(sim.srv, inc)
	return ""


# 夜を 1 回、bot に最後まで遊ばせて結果を返す。
static func play(sim: RefCounted, bot_kind: int) -> Dictionary:
	var bot := new(bot_kind)
	while not sim.is_over():
		bot.act(sim)
		sim.step()
	return sim.result()
