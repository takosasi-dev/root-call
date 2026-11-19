# 行の編集・補完・履歴のテスト(仕様書 §9.4・AC-3〜AC-6・E-1〜E-3・E-12)。
extends "res://tests/suite.gd"


func test_upper_to_lower() -> bool:
	var ed := Ed.new()
	for c in "SsH":
		ed.press(c.unicode_at(0))
	eq(ed.text, "ssh", "大文字は小文字")
	eq(ed.keys, 3, "打鍵の数")
	return true


func test_drop_unaccepted() -> bool:
	var ed := Ed.new()
	for code in [33, 59, 0x3042, 126, 97]:  # ! ; あ ~ a
		ed.press(code)
	eq(ed.text, "a", "受け付けない文字は捨てる(E-1)")
	eq(ed.keys, 1, "捨てた文字は数えない")
	return true


func test_accepted_symbols() -> bool:
	var ed := Ed.new()
	for c in "a0 -.=/_":
		ed.press(c.unicode_at(0))
	eq(ed.text, "a0 -.=/_", "記号 - . = / _ と Space")
	return true


func test_line_max() -> bool:
	var ed := Ed.new()
	for k in 85:
		ed.press(97)
	eq(ed.text.length(), B.LINE_MAX, "80 文字で止まる(E-2)")
	eq(ed.keys, B.LINE_MAX, "超えた分は数えない")
	return true


func test_backspace_and_cursor() -> bool:
	var ed := Ed.new()
	for c in "abc":
		ed.press(c.unicode_at(0))
	ed.press(Ed.K_LEFT)
	ed.press(Ed.K_BACKSPACE)
	eq(ed.text, "ac", "カーソルの前の 1 文字を消す")
	ed.press(120)
	eq(ed.text, "axc", "カーソルの位置に入る")
	ed.press(Ed.K_LEFT)
	ed.press(Ed.K_LEFT)
	ed.press(Ed.K_LEFT)
	ed.press(Ed.K_BACKSPACE)
	eq(ed.text, "axc", "行頭の BackSpace は何もしない")
	eq(ed.keys, 10, "← → BackSpace も打鍵に数える")
	return true


func test_right_at_end_is_tab() -> bool:
	var ed := Ed.new()
	ed.press(97)
	ed.press(Ed.K_LEFT)
	eq(ed.press(Ed.K_RIGHT), Ed.EDITED, "途中の → は動くだけ")
	eq(ed.press(Ed.K_RIGHT), Ed.TAB, "行末の → は Tab と同じ(D-6)")
	return true


func test_history_up_down() -> bool:
	var ed := Ed.new()
	for line in ["one", "two"]:
		for c in line:
			ed.press(c.unicode_at(0))
		ed.commit()
	for c in "dr":
		ed.press(c.unicode_at(0))
	ed.press(Ed.K_UP)
	eq(ed.text, "two", "↑ で直前の行")
	ed.press(Ed.K_UP)
	eq(ed.text, "one", "もう 1 回でその前")
	ed.press(Ed.K_UP)
	eq(ed.text, "one", "一番古い所で止まる")
	ed.press(Ed.K_DOWN)
	eq(ed.text, "two", "↓ で戻る")
	ed.press(Ed.K_DOWN)
	eq(ed.text, "dr", "一番新しいより新しくすると打ちかけの行")
	return true


func test_history_max() -> bool:
	var ed := Ed.new()
	for k in 21:
		for c in "c%d" % k:
			ed.press(c.unicode_at(0))
		ed.commit()
	eq(ed.history.size(), B.HISTORY_MAX, "20 件まで")
	eq(ed.history[B.HISTORY_MAX - 1], "c1", "21 件目で一番古い c0 が消える(AC-6)")
	return true


func test_history_edit_becomes_draft() -> bool:
	var ed := Ed.new()
	for c in "abc":
		ed.press(c.unicode_at(0))
	ed.commit()
	ed.press(Ed.K_UP)
	ed.press(100)
	eq(ed.text, "abcd", "出した行を編集する(E-12)")
	ed.press(Ed.K_UP)
	eq(ed.text, "abc", "↑ で履歴へ")
	ed.press(Ed.K_DOWN)
	eq(ed.text, "abcd", "↓ で編集した行に戻る")
	return true


func test_empty_enter_not_in_history() -> bool:
	var sim := night()
	cmd(sim, "")
	eq(sim.ed.history.size(), 0, "空の行は履歴に入れない(E-3)")
	eq(last_text(sim), "oncall@jump:~$ ", "プロンプトをもう 1 行出す")
	return true


func test_complete_single_adds_space() -> bool:
	var ed := Ed.new()
	for c in "ex":
		ed.press(c.unicode_at(0))
	eq(ed.complete(["exit", "ssh"])["result"], "done", "候補 1 つ")
	eq(ed.text, "exit ", "空白を 1 つ足す")
	return true


func test_complete_equals_no_space() -> bool:
	var ed := Ed.new()
	ed.press(45)
	ed.complete(["--size="])
	eq(ed.text, "--size=", "= で終わる候補は空白を足さない")
	return true


func test_complete_common_head() -> bool:
	var ed := Ed.new()
	ed.press("c".unicode_at(0))
	var r := ed.complete(["cache01", "cert01"])
	eq(r["result"], "list", "補える文字が無ければ候補を出す")
	eq(ed.text, "c", "行は変わらない")
	var ed2 := Ed.new()
	ed2.press("w".unicode_at(0))
	ed2.complete(["web01", "web02"])
	eq(ed2.text, "web0", "web0 まで補う")
	return true


func test_complete_none() -> bool:
	var ed := Ed.new()
	ed.press("z".unicode_at(0))
	eq(ed.complete(["ssh"])["result"], "none", "候補 0 個")
	eq(ed.text, "z", "何もしない")
	return true


func test_ac3_tab_completion_db01() -> bool:
	var sim := night()
	cmd(sim, "ssh db01")
	var before: int = sim.ed.keys
	for part in ["su", "sy", "r", "p"]:
		send(sim, part)
		sim.queue_key(Ed.K_TAB)
	run(sim, 1)
	eq(sim.ed.text, "sudo systemctl restart postgresql ", "AC-3 の行")
	eq(sim.ed.keys - before, 10, "AC-3 の打鍵の数")
	return true


func test_ac4_jump_s_tab() -> bool:
	var sim := night()
	send(sim, "s")
	sim.queue_key(Ed.K_TAB)
	run(sim, 1)
	eq(sim.ed.text, "s", "候補 2 つでは s のまま")
	eq(last_text(sim), "ssh  status", "候補の行を出す")
	send(sim, "s")
	sim.queue_key(Ed.K_TAB)
	run(sim, 1)
	eq(sim.ed.text, "ssh ", "ss の後の Tab で ssh")
	return true


func test_ac5_right_arrow_completes() -> bool:
	var sim := night()
	cmd(sim, "ssh db01")
	var before: int = sim.ed.keys
	for part in ["su", "sy", "r", "p"]:
		send(sim, part)
		sim.queue_key(Ed.K_RIGHT)
	run(sim, 1)
	eq(sim.ed.text, "sudo systemctl restart postgresql ", "行末の → でも同じ行")
	eq(sim.ed.keys - before, 10, "打鍵も同じ")
	return true


func test_tab_none_rings_bell() -> bool:
	var sim := night()
	send(sim, "zz")
	sim.queue_key(Ed.K_TAB)
	ok(types(run(sim, 1)).has("bell"), "候補 0 個で bell")
	return true


func test_candidates_context() -> bool:
	var sim := night()
	cmd(sim, "ssh web01")
	send(sim, "sudo systemctl start ")
	sim.queue_key(Ed.K_TAB)
	ok(types(run(sim, 1)).has("bell"), "web01 では start の後に候補が無い")
	var sim2 := night()
	cmd(sim2, "ssh db01")
	send(sim2, "sudo systemctl start b")
	sim2.queue_key(Ed.K_TAB)
	run(sim2, 1)
	eq(sim2.ed.text, "sudo systemctl start backup ", "db01 では backup")
	var sim3 := night()
	cmd(sim3, "ssh mail01")
	send(sim3, "sudo journalctl -")
	sim3.queue_key(Ed.K_TAB)
	run(sim3, 1)
	eq(sim3.ed.text, "sudo journalctl --vacuum-size=200M ", "journalctl の後")
	return true
