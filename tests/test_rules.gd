# サーバーの依存・障害・悪化・再起動の決まりのテスト(仕様書 §9.5〜§9.7・AC-8〜AC-12・E-5〜E-10)。
extends "res://tests/suite.gd"


func test_ac8_app_restart_fails_when_db_down() -> bool:
	var sim := night([at(0, I.DOWN, Srv.DB)])
	cmd(sim, "ssh app01")
	send(sim, "sudo systemctl restart app\n")
	run(sim, 1)
	eq(sim.srv.svc[Srv.APP], Srv.RESTARTING, "再起動の間は再起動中")
	var ev := run(sim, B.T_RESTART)
	ok(texts(sim).has(S.R_APP_FAIL), "db01 に繋がらない")
	eq(sim.srv.svc[Srv.APP], Srv.STOPPED, "app は止まったまま")
	ok(active_kinds(sim).has([I.DOWN, Srv.APP]), "停止 app01 の障害が増える")
	ok(types(ev).has("incident"), "incident が出る")
	return true


func test_ac8_nginx_restart_upstream() -> bool:
	var sim := night([at(0, I.DOWN, Srv.DB)])
	cmd(sim, "ssh web01")
	cmd(sim, "sudo systemctl restart nginx")
	ok(texts(sim).has(S.R_NGINX_502), "上流が応答しない")
	eq(sim.srv.svc[Srv.WEB01], Srv.RUNNING, "nginx は動いたまま")
	return true


func test_ac8_fix_cause_clears_impacts() -> bool:
	var sim := night([at(0, I.DOWN, Srv.DB)])
	run(sim, 1)
	eq(sim.srv.impact(Srv.APP), 2, "app01 は DB に接続できない")
	eq(sim.srv.impact(Srv.WEB01), 1, "web01 は 502")
	cmd(sim, "ssh db01")
	send(sim, "sudo systemctl restart postgresql\n")
	run(sim, 1)
	var guard := 0
	while sim.is_running() and guard < 1000:
		sim.step()
		guard += 1
		if not sim.is_running():
			eq(sim.srv.impact(Srv.APP), 0, "app01 の影響が同じ step で消える")
			eq(sim.srv.impact(Srv.WEB02), 0, "web の影響が同じ step で消える")
			ok(not sim.alert_rows().any(func(r: Dictionary) -> bool: return not r["incident"]), "影響の行も消える")
	eq(sim.active().size(), 0, "app と web に触らずに直る")
	return true


func test_ac9_disk_escalates() -> bool:
	var sim := night([at(0, I.DISK, Srv.DB)])
	var ev := run(sim, B.DISK_ESCALATE - 1)  # 起きた step から数えて 2400 step 目に止まる
	ok(not types(ev).has("escalated"), "20 秒の手前ではまだ")
	ok(sim.srv.disk[Srv.DB] > B.DISK_ALERT, "% が上がって見える")
	ev = run(sim, 1)
	ok(types(ev).has("escalated"), "20 秒で escalated")
	eq(sim.srv.svc[Srv.DB], Srv.STOPPED, "サービスが止まる")
	eq(sim.srv.disk[Srv.DB], B.DISK_FULL, "100%")
	eq(sim.active().size(), 1, "新しい障害ではなく同じ障害の続き")
	eq(int(sim.active()[0]["kind"]), I.DOWN, "停止に変わる")
	return true


func test_ac9_disk_fixed_in_time() -> bool:
	var sim := night([at(0, I.DISK, Srv.MAIL)])
	cmd(sim, "ssh mail01")
	var ev := cmd(sim, "sudo journalctl --vacuum-size=200M")
	ok(types(ev).has("fixed"), "空けると直る")
	ev = run(sim, B.DISK_ESCALATE)
	ok(not types(ev).has("escalated"), "直した後は止まらない")
	eq(sim.srv.svc[Srv.MAIL], Srv.RUNNING, "動いたまま")
	return true


func test_ac10_down_and_disk() -> bool:
	var sim := night([at(0, I.DOWN, Srv.DB), at(0, I.DISK, Srv.DB)])
	cmd(sim, "ssh db01")
	cmd(sim, "sudo systemctl restart postgresql")
	eq(last_text(sim), S.R_DISK_FAIL % "postgresql", "ディスクを直す前の再起動は失敗(E-6)")
	eq(sim.srv.svc[Srv.DB], Srv.STOPPED, "止まったまま")
	cmd(sim, "sudo journalctl --vacuum-size=200m")
	cmd(sim, "sudo systemctl restart postgresql")
	eq(sim.srv.svc[Srv.DB], Srv.RUNNING, "直した後は成功")
	eq(sim.active().size(), 0, "両方直る")
	return true


func test_ac11_restart_healthy_nginx() -> bool:
	var sim := night()
	cmd(sim, "ssh web01")
	eq(sim.srv.health(), 20, "健全")
	send(sim, "sudo systemctl restart nginx\n")
	run(sim, 1)
	var seen := []
	for k in B.T_RESTART - 1:
		sim.step()
		seen.append(sim.srv.health())
	ok(seen.all(func(h: int) -> bool: return h == 12), "2 秒の間は 12")
	run(sim, 1)
	eq(sim.srv.health(), 20, "終わると 20")
	return true


func test_ac12_web01_down_all_night() -> bool:
	var sim := night([at(0, I.DOWN, Srv.WEB01)])
	run(sim, B.NIGHT_TICKS)
	var r := sim.result()
	eq(r["uptime100"], 6000, "稼働率 60.00%")
	eq(r["points"], 6000, "点 6000")
	ok(sim.is_over(), "夜が明ける")
	return true


func test_e7_db_and_cache_down() -> bool:
	var sim := night([at(0, I.DOWN, Srv.DB), at(0, I.DOWN, Srv.CACHE)])
	cmd(sim, "ssh app01")
	cmd(sim, "sudo systemctl restart app")
	ok(texts(sim).has(S.R_APP_FAIL), "db01 の文")
	return true


func test_cache_down_app_slow() -> bool:
	var sim := night([at(0, I.DOWN, Srv.CACHE)])
	run(sim, 1)
	eq(sim.srv.health(), 4 * 2 + 4, "キャッシュが止まると web は半分")
	eq(sim.srv.impact(Srv.APP), 3, "応答が遅い")
	cmd(sim, "ssh app01")
	cmd(sim, "sudo systemctl restart app")
	eq(last_text(sim), S.R_APP_SLOW, "起動するが遅いまま")
	return true


func test_leak_escalates_and_restart_fixes() -> bool:
	var sim := night([at(0, I.LEAK, Srv.APP)])
	var ev := run(sim, B.LEAK_ESCALATE + 1)
	ok(types(ev).has("escalated"), "25 秒で止まる")
	eq(sim.srv.svc[Srv.APP], Srv.STOPPED, "app が止まる")
	cmd(sim, "ssh app01")
	ev = cmd(sim, "sudo systemctl restart app")
	ok(types(ev).has("fixed"), "再起動で直る")
	eq(sim.srv.mem[Srv.APP], B.MEM_NORMAL, "メモリが戻る")
	return true


func test_leak_fixed_before_escalation() -> bool:
	var sim := night([at(0, I.LEAK, Srv.APP)])
	cmd(sim, "ssh app01")
	var ev := cmd(sim, "sudo systemctl restart app")
	ok(types(ev).has("fixed"), "止まる前の再起動で直る")
	ev = run(sim, B.LEAK_ESCALATE)
	ok(not types(ev).has("escalated"), "その後は悪化しない")
	return true


func test_cert_queue_backup() -> bool:
	var sim := night([at(0, I.CERT, Srv.WEB02), at(0, I.QUEUE, Srv.MAIL), at(0, I.BACKUP, Srv.DB)])
	run(sim, 1)
	eq(sim.srv.health(), 4 * 2, "証明書の切れた web と詰まったメールは健全でない(バックアップは入らない)")
	cmd(sim, "ssh web02")
	cmd(sim, "sudo certbot renew")
	cmd(sim, "ssh mail01")
	cmd(sim, "sudo postqueue -f")
	eq(sim.active().size(), 1, "残りはバックアップ")
	cmd(sim, "ssh db01")
	cmd(sim, "sudo systemctl start backup")
	eq(sim.active().size(), 0, "全部直る")
	eq(sim.srv.health(), 20, "健全")
	return true


func test_backup_penalty() -> bool:
	var sim := night([at(0, I.BACKUP, Srv.DB)])
	run(sim, B.NIGHT_TICKS)
	var r := sim.result()
	eq(r["uptime100"], 10000, "健全さには入らない")
	eq(r["backups_left"], 1, "未対応 1")
	eq(r["points"], 10000 - B.BACKUP_PENALTY, "点を引く")
	return true


func test_e9_same_incident_not_repeated() -> bool:
	var sim := night([at(0, I.DOWN, Srv.WEB01), at(1, I.DOWN, Srv.WEB01), at(2, I.DOWN, Srv.WEB02)])
	run(sim, 3 * B.TICK_HZ)
	eq(sim.incidents.size(), 2, "直っていない同じ物は起こさない")
	return true


func test_e8_restart_running_service() -> bool:
	var sim := night()
	cmd(sim, "ssh cache01")
	send(sim, "sudo systemctl restart redis\n")
	run(sim, 1)
	eq(sim.snapshot()["servers"][Srv.CACHE]["card"], "restart", "札は再起動中")
	eq(sim.srv.health(), 12, "その間は止まっているものとして数える")
	settle(sim)
	eq(sim.srv.svc[Srv.CACHE], Srv.RUNNING, "終わると動く")
	eq(sim.incidents.size(), 0, "障害は増えない")
	return true


func test_e10_night_ends_while_running() -> bool:
	var sim := night([at(0, I.DOWN, Srv.WEB01)])
	cmd(sim, "ssh web01")
	run(sim, B.NIGHT_TICKS - sim.tick - 10)
	send(sim, "sudo systemctl restart nginx\n")
	var ev := run(sim, 20)
	ok(types(ev).has("over"), "over")
	ok(not sim.is_running(), "実行を打ち切る")
	eq(sim.result()["fixed"], 0, "直らなかったものとする")
	return true


func test_fixed_event_and_text() -> bool:
	var sim := night([at(0, I.DOWN, Srv.WEB01)])
	run(sim, 600)
	cmd(sim, "ssh web01")
	var ev := cmd(sim, "sudo systemctl restart nginx")
	var fixed: Array = ev.filter(func(e: Dictionary) -> bool: return e["type"] == "fixed")
	eq(fixed.size(), 1, "fixed が 1 回")
	var secs10: int = fixed[0]["secs10"]
	ok(secs10 > 50 and secs10 < 100, "かかった秒")
	eq(last_text(sim), S.R_FIXED % ("%d.%d" % [secs10 / 10, secs10 % 10]), "直った(n 秒)")
	return true


func test_cards_and_edges() -> bool:
	var sim := night([at(0, I.DOWN, Srv.DB), at(0, I.CERT, Srv.WEB01)])
	run(sim, 1)
	var cards: Array = sim.snapshot()["servers"].map(func(s: Dictionary) -> String: return s["card"])
	eq(cards, ["warn", "impact", "impact", "down", "ok", "ok"], "札の 4 つの状態")
	eq(sim.snapshot()["edges"], [true, true, true, false], "原因から影響へ伝わる矢印")
	return true


func test_alert_order() -> bool:
	var sim := night([at(0, I.DOWN, Srv.DB), at(1, I.DISK, Srv.MAIL)])
	run(sim, 2 * B.TICK_HZ)
	var rows := sim.alert_rows()
	eq(rows.map(func(r: Dictionary) -> int: return r["server"]), [Srv.DB, Srv.WEB01, Srv.WEB02, Srv.APP, Srv.MAIL], "起きた順、同じ時刻は障害の行が先")
	ok(rows[4]["left"] > 0, "悪化の残りがある")
	return true
