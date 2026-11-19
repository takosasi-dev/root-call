# 保存のテスト(仕様書 §9.15・AC-17・E-14・E-17・NFR-9)。テストでは user:// の別のファイルを使う。
extends "res://tests/suite.gd"

const Store := preload("res://save/save_store.gd")
const P := "user://test_save.json"


func _fresh(text: Variant = null) -> Store:
	if FileAccess.file_exists(P):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(P))
	if text != null:
		var f := FileAccess.open(P, FileAccess.WRITE)
		f.store_string(text)
		f.close()
	return Store.new(P)


func test_ac17_empty_broken_version() -> bool:
	var st := _fresh()
	eq(st.data, Store.defaults(), "空")
	ok(not st.load_failed, "空は失敗ではない")
	st = _fresh("{not json")
	eq(st.data, Store.defaults(), "壊れた JSON")
	ok(st.load_failed, "壊れた時は知らせる(E-14)")
	st = _fresh('{"version": 2, "training_done": true}')
	eq(st.data, Store.defaults(), "version が 2")
	ok(st.load_failed, "知らない version も知らせる")
	return true


func test_practice_best() -> bool:
	var st := _fresh()
	var r1 := st.record(2, 322, {"points": 8000, "mttr10": 90})
	ok(r1["new_best"] and r1["prev_best"] == null, "初めての最高")
	var r2 := st.record(2, 322, {"points": 7000, "mttr10": 50})
	ok(not r2["new_best"], "低い点は最高にしない")
	eq(Store.new(P).practice_best(), {"points": 8000, "mttr10": 90}, "読み直しても残る")
	return true


func test_daily_first_and_best() -> bool:
	var st := _fresh()
	var a := st.record(0, 322, {"points": 8640, "mttr10": 98})
	ok(a["first_today"], "1 回目")
	st.record(0, 322, {"points": 8802, "mttr10": 85})
	var d := Store.new(P).daily(322)
	eq(d["first"], {"points": 8640, "mttr10": 98}, "1 回目は残る")
	eq(d["best"], {"points": 8802, "mttr10": 85}, "最高")
	var b := st.record(0, 323, {"points": 5000, "mttr10": 99})
	ok(b["first_today"], "日付が変われば作り直す")
	eq(Store.new(P).daily(322)["first"], null, "前の日の記録は消える")
	return true


func test_e17_old_day_does_not_overwrite() -> bool:
	var st := _fresh()
	st.record(0, 323, {"points": 5000, "mttr10": 99})
	var r := st.record(0, 322, {"points": 9999, "mttr10": 1})
	ok(not r["first_today"] and not r["new_best"], "古い日の回は記録しない")
	eq(Store.new(P).daily(323)["best"], {"points": 5000, "mttr10": 99}, "新しい日のまま")
	return true


func test_training_done_and_settings() -> bool:
	var st := _fresh()
	ok(not st.training_done(), "初めは研修前")
	var r := st.record(1, 322, {"points": 9000, "mttr10": 60})
	ok(r["first_training"], "初めて研修を終えた")
	st.set_setting("volume", 25)
	st.set_setting("shake", false)
	var again := Store.new(P)
	ok(again.training_done(), "研修を終えたが残る")
	eq(again.settings(), {"volume": 25, "shake": false, "reduce_flash": false}, "設定が残る")
	return true


func test_bad_settings_values() -> bool:
	var st := _fresh('{"version": 1, "settings": {"volume": 33, "shake": "yes"}, "practice_best": {"points": "x"}}')
	eq(st.settings(), Store.default_settings(), "おかしな値は既定値")
	eq(st.practice_best(), null, "おかしな記録は無し")
	ok(not st.load_failed, "形は読めた")
	return true
