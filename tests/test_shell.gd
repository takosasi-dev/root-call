# コマンドの解釈と出力のテスト(仕様書 §9.5・AC-7・E-4)。
extends "res://tests/suite.gd"


func test_ssh_and_exit() -> bool:
	var sim := night()
	send(sim, "ssh db01\n")
	run(sim, 1)
	ok(sim.is_running(), "ssh には実行の時間がある")
	eq(sim.prompt(), "oncall@jump:~$ ", "終わるまでは jump")
	run(sim, B.T_SSH)
	eq(sim.prompt(), "oncall@db01:~$ ", "終わるとサーバーのプロンプト")
	cmd(sim, "ssh web02")
	eq(sim.loc, Srv.WEB02, "サーバーからでも移れる(入れ子にしない)")
	cmd(sim, "exit")
	eq(sim.loc, -1, "exit で jump へ")
	return true


func test_ssh_unknown_host() -> bool:
	var sim := night()
	var ev := cmd(sim, "ssh web09")
	eq(last_text(sim), S.E_NO_HOST % "web09", "無いサーバー")
	ok(types(ev).has("cmd_error"), "cmd_error")
	eq(sim.loc, -1, "移らない")
	return true


func test_ac7_need_sudo() -> bool:
	var sim := night()
	cmd(sim, "ssh web01")
	cmd(sim, "systemctl restart nginx")
	eq(last_text(sim), S.E_NEED_SUDO, "sudo が無い")
	eq(sim.srv.svc[Srv.WEB01], Srv.RUNNING, "何も変わらない")
	return true


func test_ac7_no_unit() -> bool:
	var sim := night()
	cmd(sim, "ssh web01")
	cmd(sim, "sudo systemctl restart postgresql")
	eq(last_text(sim), S.E_NO_UNIT % "postgresql", "そのサーバーに無いサービス")
	return true


func test_ac7_jump_server_command() -> bool:
	var sim := night()
	cmd(sim, "df -h")
	eq(last_text(sim), S.E_JUMP, "jump での df -h")
	cmd(sim, "sudo systemctl restart nginx")
	eq(last_text(sim), S.E_JUMP, "jump での再起動")
	return true


func test_ac7_forbidden() -> bool:
	var sim := night([at(0, I.DOWN, Srv.WEB01)])
	cmd(sim, "ssh web01")
	for line in ["rm -rf /var/log", "sudo reboot", "chmod 777 x", "sudo shutdown now", "kill 1"]:
		var ev := cmd(sim, line)
		eq(last_text(sim), S.E_FORBIDDEN, line)
		ok(types(ev).has("forbidden"), line + " で forbidden")
	eq(sim.active().size(), 1, "何も直らない")
	return true


func test_not_found() -> bool:
	var sim := night()
	var ev := cmd(sim, "ls")
	eq(last_text(sim), S.E_NOT_FOUND % "ls", "表に無いコマンド")
	ok(types(ev).has("cmd_error"), "cmd_error")
	return true


func test_line_normalized() -> bool:
	var sim := night()
	cmd(sim, "  SSH    DB01  ")
	eq(sim.loc, Srv.DB, "小文字にそろえ、空白をまとめる")
	return true


func test_enter_while_running() -> bool:
	var sim := night()
	send(sim, "ssh db01\n")
	run(sim, 1)
	send(sim, "df\n")
	run(sim, 1)
	eq(sim.ed.text, "df", "実行中の Enter は何もしない。打った文字は残る(E-4)")
	ok(sim.is_running(), "まだ実行中")
	return true


func test_status_on_jump() -> bool:
	var sim := night([at(0, I.DOWN, Srv.DB)])
	run(sim, 1)
	var before := sim.lines.size()
	cmd(sim, "status")
	eq(sim.lines.size() - before, 7, "プロンプト + 6 台")
	eq(last_text(sim), S.STATUS_LINE % ["mail01", "postfix", S.ST_RUNNING], "1 行の形")
	ok(texts(sim).has(S.STATUS_LINE % ["db01", "postgresql", S.ST_STOPPED]), "止まった db01")
	return true


func test_help_table_by_mode() -> bool:
	var daily := Sim.new(5, Sim.MODE_DAILY, [])
	cmd(daily, "help")
	ok(not texts(daily).has(S.HELP_TABLE[0]), "今日の夜は対応表を出さない")
	var practice := night()
	cmd(practice, "help")
	ok(texts(practice).has(S.HELP_TABLE[0]), "練習の夜は対応表も出す")
	return true


func test_clear_and_history() -> bool:
	var sim := night()
	cmd(sim, "help")
	cmd(sim, "clear")
	eq(sim.lines.size(), 0, "clear で画面を消す")
	ok(not texts(sim).has(S.HELP[0]), "clear で前の出力が消える")
	cmd(sim, "history")
	eq(last_text(sim), S.HISTORY_LINE % [3, "history"], "history は古い順に番号つき")
	return true


func test_look_commands() -> bool:
	var sim := night([at(0, I.DISK, Srv.DB)])
	cmd(sim, "ssh db01")
	cmd(sim, "df -h")
	ok(last_text(sim).begins_with("/dev/sda1"), "df -h の出力")
	cmd(sim, "systemctl status postgresql")
	eq(last_text(sim), S.R_LOG % S.LOG_DISK, "最後のログに理由")
	cmd(sim, "ssh app01")
	cmd(sim, "free -m")
	eq(last_text(sim), S.R_FREE % B.MEM_NORMAL, "free -m")
	return true


func test_wrong_place_commands() -> bool:
	var sim := night()
	cmd(sim, "ssh db01")
	cmd(sim, "sudo certbot renew")
	eq(last_text(sim), S.E_NOT_HERE % "certbot", "certbot は web だけ")
	cmd(sim, "sudo postqueue -f")
	eq(last_text(sim), S.E_NOT_HERE % "postqueue", "postqueue は mail01 だけ")
	cmd(sim, "ssh web01")
	cmd(sim, "sudo systemctl start backup")
	eq(last_text(sim), S.E_NO_UNIT % "backup", "backup は db01 だけ")
	return true
