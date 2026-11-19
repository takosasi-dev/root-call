# やさしい(v0.2.0)のテスト。ふつうの夜は変えない(ふつうの決まりは test_night・test_shell が見る)。
extends "res://tests/suite.gd"

const Sched := preload("res://core/schedule.gd")
const Shell := preload("res://core/shell.gd")
const Bots := preload("res://core/bots.gd")
const Store := preload("res://save/save_store.gd")
const Share := preload("res://core/share_text.gd")


static func easy_night(plan: Array = []) -> Sim:
	return Sim.new(1, Sim.MODE_PRACTICE, plan, true)


func test_easy_schedule_is_slower_same_order() -> bool:
	var n := Sched.build(42)
	var e := Sched.build(42, true)
	ok(e.size() < n.size(), "やさしいは障害が少ない: %d < %d" % [e.size(), n.size()])
	var k := mini(e.size(), n.size())
	eq(e.slice(0, k).map(func(x: Dictionary) -> Array: return [x["kind"], x["server"]]),
		n.slice(0, k).map(func(x: Dictionary) -> Array: return [x["kind"], x["server"]]), "種類とサーバーの並びは同じ")
	eq(int(e[0]["t"]), B.SCHED_FIRST, "1 件目の時刻は同じ")
	return true


func test_easy_deterministic() -> bool:
	var a := Bots.play(Sim.new(777, Sim.MODE_DAILY, null, true), Bots.CORRECT)
	var b := Bots.play(Sim.new(777, Sim.MODE_DAILY, null, true), Bots.CORRECT)
	eq(a, b, "同じ種・やさしいなら同じ結果")
	return true


func test_easy_escalation_and_run_time() -> bool:
	var sim := easy_night([at(0, I.DISK, Srv.DB)])
	run(sim, 1)
	eq(int(sim.incidents[0]["total"]), B.DISK_ESCALATE * B.EASY_ESCALATE_MUL, "悪化して止まるまで 2 倍")
	send(sim, "ssh db01\n")
	run(sim, 1)
	eq(int(sim.running["total"]), B.T_SSH / B.EASY_RUN_DIV, "実行の時間は半分")
	return true


func test_easy_short_commands_and_no_sudo() -> bool:
	var sim := easy_night([at(0, I.DOWN, Srv.WEB01), at(0, I.DISK, Srv.DB), at(0, I.CERT, Srv.WEB02), at(0, I.QUEUE, Srv.MAIL), at(0, I.BACKUP, Srv.DB)])
	run(sim, 1)
	cmd(sim, "ssh web01")
	cmd(sim, "restart")
	ok(sim.srv.up(Srv.WEB01), "restart だけで nginx を再起動")
	cmd(sim, "ssh db01")
	cmd(sim, "vacuum")
	eq(sim.srv.disk[Srv.DB], B.DISK_NORMAL, "vacuum でログを消す")
	cmd(sim, "backup")
	ok(sim.srv.backup_ok, "backup で取り直す")
	cmd(sim, "ssh web02")
	cmd(sim, "renew")
	ok(sim.srv.cert_ok[Srv.WEB02], "renew で証明書")
	cmd(sim, "ssh mail01")
	cmd(sim, "postqueue -f")
	eq(sim.srv.queue[Srv.MAIL], 0, "sudo を省いた元の形も通る")
	run(sim, 2)
	eq(sim.active().size(), 0, "全部直った")
	return true


func test_easy_restart_on_jump_is_error() -> bool:
	var sim := easy_night()
	cmd(sim, "restart")
	eq(sim.lines[-1][0], S.E_JUMP, "jump で restart は jump の誤り")
	return true


func test_normal_keeps_sudo_and_no_alias() -> bool:
	var sim := night([at(0, I.DOWN, Srv.WEB01)])
	run(sim, 1)
	cmd(sim, "ssh web01")
	cmd(sim, "restart")
	eq(sim.lines[-1][0], S.E_NOT_FOUND % "restart", "ふつうでは短い形は通らない")
	cmd(sim, "systemctl restart nginx")
	eq(sim.lines[-1][0], S.E_NEED_SUDO, "ふつうでは sudo が要る")
	return true


func test_easy_empty_tab_fills_fix() -> bool:
	var sim := easy_night([at(0, I.DISK, Srv.DB)])
	run(sim, 1)
	sim.queue_key(Ed.K_TAB)
	run(sim, 1)
	eq(sim.ed.text, "", "jump の空の行の Tab では入れない")
	cmd(sim, "ssh db01")
	sim.queue_key(Ed.K_TAB)
	run(sim, 1)
	eq(sim.ed.text, "vacuum", "障害のあるサーバーの空の行の Tab で直す形が入る")
	var keys := sim.ed.keys
	sim.queue_key(Ed.K_ENTER)
	settle(sim)
	run(sim, 1)
	eq(sim.active().size(), 0, "Tab → Enter で直る")
	eq(sim.ed.keys, keys + 1, "Tab も 1 打鍵")
	return true


func test_normal_empty_tab_lists() -> bool:
	var sim := night([at(0, I.DISK, Srv.DB)])
	run(sim, 1)
	cmd(sim, "ssh db01")
	sim.queue_key(Ed.K_TAB)
	run(sim, 1)
	eq(sim.ed.text, "", "ふつうの空の行の Tab は候補の一覧だけ")
	return true


func test_easy_hints_short_every_time() -> bool:
	var sim := Sim.new(9, Sim.MODE_DAILY, [at(0, I.DOWN, Srv.WEB01), at(1, I.DOWN, Srv.DB), at(2, I.DOWN, Srv.MAIL)], true)
	run(sim, 3 * B.TICK_HZ)
	var hints: Array = sim.alert_rows().filter(func(r: Dictionary) -> bool: return r["incident"]).map(func(r: Dictionary) -> String: return r["hint"])
	eq(hints, ["ssh web01 → restart", "ssh db01 → restart", "ssh mail01 → restart"], "3 回目でも短い形の下書き")
	return true


func test_easy_completion_has_aliases() -> bool:
	ok(Shell.candidates([], Srv.DB, true).has("vacuum"), "やさしいの 1 語目に短い形")
	ok(not Shell.candidates([], Srv.DB).has("vacuum"), "ふつうには無い")
	return true


func test_cause_flag_on_cards() -> bool:
	var sim := easy_night([at(0, I.DOWN, Srv.DB)])
	run(sim, 1)
	var s := sim.snapshot()
	ok(s["servers"][Srv.DB]["cause"], "db01 が原因")
	ok(not s["servers"][Srv.APP]["cause"], "app01 は影響だけ")
	return true


func test_records_split_by_level() -> bool:
	var p := "user://test_easy_save.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var st := Store.new(p)
	st.record(2, 322, {"points": 9500, "mttr10": 40}, true)
	st.record(2, 322, {"points": 8000, "mttr10": 60})
	st.record(0, 322, {"points": 9000, "mttr10": 50}, true)
	var again := Store.new(p)
	eq(again.practice_best(true)["points"], 9500, "やさしいの練習の最高")
	eq(again.practice_best()["points"], 8000, "ふつうの練習の最高は別")
	eq(again.daily(322, true)["first"]["points"], 9000, "やさしいの今日の記録")
	eq(again.daily(322)["first"], null, "ふつうの今日の記録は空")
	again.set_setting("easy", false)
	eq(Store.new(p).settings()["easy"], false, "難しさの設定が残る")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	return true


func test_old_save_keeps_normal_records() -> bool:
	var v: Dictionary = Store.parse('{"version": 1, "practice_best": {"points": 7000, "mttr10": 80}, "settings": {"volume": 50, "shake": true, "reduce_flash": false}}')
	eq(v["practice_best"], {"points": 7000, "mttr10": 80}, "v0.1.0 の記録はふつうのまま")
	eq(v["practice_best_easy"], null, "やさしいの記録は空")
	eq(v["settings"]["easy"], true, "難しさは既定のやさしい")
	return true


func test_share_text_easy_label() -> bool:
	var r := {"uptime100": 8640, "mttr10": 98, "keys": 412, "backups_left": 0}
	ok(Share.make("2026-11-19", 0, true, r, true).begins_with("RootCall 2026-11-19(今日の夜・1回目・やさしい)"), "見出しに、やさしい")
	ok(Share.make("2026-11-19", 0, true, r).begins_with("RootCall 2026-11-19(今日の夜・1回目)"), "ふつうは今までどおり")
	return true
