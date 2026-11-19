# 夜の並び・決定性・下書き・研修の夜・bot・日付・共有する文字・点のテスト(仕様書 §9.8〜§9.14・AC-2・AC-13〜AC-16・AC-22)。
extends "res://tests/suite.gd"

const Sched := preload("res://core/schedule.gd")
const Bots := preload("res://core/bots.gd")
const Day := preload("res://core/day_index.gd")
const Share := preload("res://core/share_text.gd")
const Score := preload("res://core/score.gd")

# 固定の入力(種 3 の練習の夜を正解 bot が遊ぶ)の結果。Windows・CI(Linux)で同じになること(NFR-4)
const GOLDEN := {"uptime100": 8704, "mttr10": 59, "keys": 608, "fixed": 17, "incidents": 17, "backups_left": 0, "points": 8704}


func test_schedule_shape() -> bool:
	var p := Sched.build(12345)
	ok(p.size() >= 13 and p.size() <= 24, "1 夜の障害の数: %d" % p.size())
	eq(int(p[0]["t"]), B.SCHED_FIRST, "最初は 5 秒")
	var last := 0
	for e: Dictionary in p:
		ok(int(e["t"]) >= last and int(e["t"]) < B.SCHED_END, "時刻の順と範囲")
		last = int(e["t"])
	eq(Sched.build(12345), p, "同じ種なら同じ並び")
	ok(Sched.build(54321) != p, "違う種なら違う並び")
	return true


func test_schedule_seed_zero() -> bool:
	eq(Sched.build(0), Sched.build(1), "種 0 は 1 として扱う")
	return true


func test_schedule_pair() -> bool:
	var found := false
	for s in range(1, 200):
		var p := Sched.build(s)
		for k in p.size() - 1:
			if p[k]["t"] == p[k + 1]["t"]:
				found = true
				eq([p[k]["server"], p[k + 1]["server"]], [Srv.WEB01, Srv.WEB02], "同時は web01 と web02 の停止")
	ok(found, "200 個の種のどこかで同時が出る")
	return true


func test_ac13_plan_independent_of_keys() -> bool:
	var a := Sim.new(777, Sim.MODE_DAILY)
	var b := Sim.new(777, Sim.MODE_DAILY)
	Bots.play(a, Bots.CORRECT)
	Bots.play(b, Bots.IDLE)
	var pick := func(sim: Sim) -> Array:
		return sim.plan.map(func(e: Dictionary) -> Array: return [e["t"], e["kind"], e["server"]])
	eq(pick.call(a), pick.call(b), "打鍵が違っても予定の並びは同じ")
	return true


func test_ac2_replay_100() -> bool:
	# 正解 bot の打鍵を記録し、同じ記録を 100 回流す
	var rec: Array = []
	var sim := Sim.new(3, Sim.MODE_PRACTICE)
	var bot := Bots.new(Bots.CORRECT)
	while not sim.is_over():
		var before := sim._keys.size()
		bot.act(sim)
		if sim._keys.size() > before:
			rec.append([sim.tick, sim._keys[sim._keys.size() - 1]])
		sim.step()
	var want := sim.result()
	eq(want, GOLDEN, "固定の入力の結果(NFR-4)")
	for n in 100:
		var s2 := Sim.new(3, Sim.MODE_PRACTICE)
		var i := 0
		while not s2.is_over():
			while i < rec.size() and rec[i][0] == s2.tick:
				s2.queue_key(rec[i][1])
				i += 1
			s2.step()
		if s2.result() != want:
			errors.append("%d 回目が違う: %s" % [n, s2.result()])
			break
	return true


func test_ac15_bots() -> bool:
	for s in range(1, 11):
		var c := Bots.play(Sim.new(s, Sim.MODE_PRACTICE), Bots.CORRECT)
		var idle := Bots.play(Sim.new(s, Sim.MODE_PRACTICE), Bots.IDLE)
		ok(int(c["uptime100"]) >= 7000, "種 %d の正解 bot: %d" % [s, c["uptime100"]])
		ok(int(idle["uptime100"]) <= 4000, "種 %d の何もしない bot: %d" % [s, idle["uptime100"]])
	return true


func test_r3_symptom_bot_gap() -> bool:
	var gap := 0
	for s in range(1, 11):
		gap += int(Bots.play(Sim.new(s, Sim.MODE_PRACTICE), Bots.CORRECT)["uptime100"])
		gap -= int(Bots.play(Sim.new(s, Sim.MODE_PRACTICE), Bots.SYMPTOM)["uptime100"])
	ok(gap / 10 >= 500, "症状 bot と正解 bot の差が 5 ポイント以上: %s" % Score.pct1(gap / 10))
	return true


func test_ac14_training_plan() -> bool:
	var p := Sched.training()
	var want := [[5, I.DOWN, Srv.WEB01], [35, I.DOWN, Srv.DB], [70, I.DISK, Srv.DB], [100, I.LEAK, Srv.APP],
		[130, I.CERT, Srv.WEB02], [155, I.QUEUE, Srv.MAIL], [180, I.BACKUP, Srv.DB], [200, I.DOWN, Srv.CACHE],
		[215, I.DOWN, Srv.APP], [215, I.DOWN, Srv.WEB01]]
	eq(p.map(func(e: Dictionary) -> Array: return [e["t"] / B.TICK_HZ, e["kind"], e["server"]]), want, "§9.8 の表")
	var sim := Sim.new(1, Sim.MODE_TRAINING)
	eq(texts(sim), S.GUIDE, "始めに案内の 3 行")
	var ev := run(sim, 5 * B.TICK_HZ + 1)
	ok(types(ev).has("incident"), "0:05 に web01")
	return true


func test_ac14_training_hints_and_explain() -> bool:
	var sim := Sim.new(1, Sim.MODE_TRAINING)
	run(sim, 36 * B.TICK_HZ)
	var rows := sim.alert_rows()
	var db: Dictionary = rows.filter(func(r: Dictionary) -> bool: return r["server"] == Srv.DB)[0]
	eq(db["hint"], "ssh db01 → sudo systemctl restart postgresql", "下書きは毎回全部")
	eq(db["explain"], S.EXPLAIN[I.DOWN], "停止の説明")
	var imp: Dictionary = rows.filter(func(r: Dictionary) -> bool: return not r["incident"])[0]
	eq(imp["explain"], S.EXPLAIN[0], "影響の説明")
	eq(imp["upstream"], S.UPSTREAM, "上流を見る")
	var web: Dictionary = rows.filter(func(r: Dictionary) -> bool: return r["incident"] and r["server"] == Srv.WEB01)[0]
	eq(web["hint"], "ssh web01 → sudo systemctl restart nginx", "2 回目の停止でも全部")
	return true


func test_ac14_daily_hints_fade() -> bool:
	var sim := Sim.new(9, Sim.MODE_DAILY, [at(0, I.DOWN, Srv.WEB01), at(1, I.DOWN, Srv.DB), at(2, I.DOWN, Srv.MAIL)])
	run(sim, 3 * B.TICK_HZ)
	var hints: Array = sim.alert_rows().filter(func(r: Dictionary) -> bool: return r["incident"]).map(func(r: Dictionary) -> String: return r["hint"])
	eq(hints, ["ssh web01 → sudo systemctl restart nginx", "ssh db01 → sudo …", ""], "1・2・3 回目で 全部・最初の語・無し")
	ok(sim.alert_rows().all(func(r: Dictionary) -> bool: return r["explain"] == ""), "今日の夜は説明を出さない")
	return true


func test_hint_disk_before_restart() -> bool:
	var sim := night([at(0, I.DISK, Srv.DB)])
	run(sim, B.DISK_ESCALATE + 2)
	eq(sim.alert_rows()[0]["hint"], "ssh db01 → sudo journalctl --vacuum-size=200M", "止まった後もディスクから")
	cmd(sim, "ssh db01")
	cmd(sim, "sudo journalctl --vacuum-size=200M")
	eq(sim.alert_rows()[0]["hint"], "ssh db01 → sudo systemctl restart postgresql", "空けたら再起動")
	return true


func test_ac16_day_index() -> bool:
	eq(Day.day_index(2026, 1, 1), 0, "2026-01-01 は 0")
	eq(Day.day_index(2026, 11, 19), 322, "2026-11-19 は 322")
	eq(Day.day_index(2027, 1, 1), 365, "2027-01-01 は 365")
	eq(Day.day_index(2025, 12, 31), 0, "前は 0(E-18)")
	eq(Day.day_seed(322), ((323 * 2654435761) + 0x5243) & 0xFFFFFFFF, "種の式")
	ok(Day.day_seed(322) != 0, "0 にならない")
	eq(Day.date_string(2026, 3, 4), "2026-03-04", "日付の形")
	return true


func test_ac16_share_text() -> bool:
	var r := {"uptime100": 8649, "mttr10": 98, "keys": 412, "backups_left": 0}
	eq(Share.make("2026-11-19", 0, true, r), "RootCall 2026-11-19(今日の夜・1回目)\n稼働率 86.4% / 平均の復旧 9.8 秒 / 打鍵 412\nhttps://takosasi-dev.github.io/root-call/", "今日の夜の 1 回目")
	eq(Share.make("2026-11-19", 0, false, r).split("\n")[0], "RootCall 2026-11-19(今日の夜)", "2 回目以降")
	eq(Share.make("2026-11-19", 2, false, r).split("\n")[0], "RootCall 2026-11-19(練習の夜)", "練習の夜")
	eq(Share.make("2026-11-19", 1, true, r).split("\n")[0], "RootCall 2026-11-19(研修の夜)", "研修の夜")
	r["backups_left"] = 1
	eq(Share.make("2026-11-19", 2, false, r).split("\n")[1], "稼働率 86.4% / 平均の復旧 9.8 秒 / 打鍵 412 / バックアップ 未対応", "未対応のバックアップ")
	return true


func test_score_helpers() -> bool:
	eq(Score.pct1(8640), "86.4", "小数 1 桁")
	eq(Score.pct1(10000), "100.0", "100%")
	eq(Score.sec1(98), "9.8", "秒")
	eq(Score.comma(8640), "8,640", "3 桁区切り")
	eq(Score.comma(-162), "-162", "負")
	eq(Score.comma(1234567), "1,234,567", "7 桁")
	ok(Score.better({"points": 2, "mttr10": 9}, {"points": 1, "mttr10": 1}), "点で比べる")
	ok(Score.better({"points": 1, "mttr10": 5}, {"points": 1, "mttr10": 9}), "同じなら平均の復旧の短い方")
	eq(Score.mttr10([{"start": 0, "fixed": 120}, {"start": 0, "fixed": -1}], 360, false), 20, "直っていない物は終わりまで")
	eq(Score.mttr10([{"start": 0, "fixed": -1}], 360, true), -1, "直った物が無い")
	return true


func test_ac22_core_purity() -> bool:
	var dir := "res://core/"
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string(dir + f)
		ok(not src.contains("extends Node"), f + " が Node を継承している")
		for bad in ["sin(", "cos(", "randf", "randi", "Time."]:
			for line in src.split("\n"):
				var code := line.split("#")[0]
				ok(not code.contains(bad), "%s に %s: %s" % [f, bad, line.strip_edges()])
		if f == "strings.gd":
			continue
		for line in src.split("\n"):
			var code := line.split("#")[0]
			for k in code.length():
				if code.unicode_at(k) > 127:
					errors.append("%s の文言が strings.gd の外にある: %s" % [f, line.strip_edges()])
					break
	return true
