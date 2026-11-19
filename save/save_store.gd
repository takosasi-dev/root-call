# 保存の読み書き(仕様書 §9.15・FR-23・E-14・E-15)。研修を終えたか・練習の夜の最高・今日の夜の記録・設定を持つ。
# 置き場: Web はブラウザの localStorage の root-call/save(共通 §3 の 10。user:// は同じサイトのゲーム全部で 1 つなので使わない)、
# やさしいの記録は practice_best_easy・daily_easy に分けて持つ(ふつうの記録は v0.1.0 と同じ所)。
# それ以外は user://save.json。読めない・壊れている・version が違う時は既定値で始め、書けなくても止めない。作りは ParryDuel の save_store。
extends RefCounted

const B := preload("res://core/balance.gd")
const Score := preload("res://core/score.gd")

const PATH := "user://save.json"
const VERSION := 1
const WEB_KEY := "root-call/save"
# 使えない時は投げずに null / "no" を返す。書けたかは文字の 'ok' で返す(JS の true は 4.7.2 の Web で bool として届かない。ParryDuel v0.1.2)
const JS_READ := "(() => { try { return localStorage.getItem('%s'); } catch (e) { return null; } })()"
const JS_WRITE := "(() => { try { localStorage.setItem('%s', %s); return 'ok'; } catch (e) { return 'no'; } })()"

var path: String
var data: Dictionary = {}
var load_failed := false  # 保存があったのに読めなかった(E-14)
var write_failed := false  # 直前の書き込みが失敗した(E-15)
var _web := OS.has_feature("web")


func _init(p_path: String = PATH) -> void:
	path = p_path
	load_data()


static func default_settings() -> Dictionary:
	return {"volume": B.DEFAULT_VOLUME, "shake": true, "reduce_flash": false, "easy": true}


static func defaults() -> Dictionary:
	return {"version": VERSION, "training_done": false, "practice_best": null, "daily": null,
		"practice_best_easy": null, "daily_easy": null, "settings": default_settings()}


# 難しさごとの記録の置き場の名前。
static func _k(name: String, easy: bool) -> String:
	return name + "_easy" if easy else name


func load_data() -> void:
	data = defaults()
	load_failed = false
	var text: Variant = _read_text()
	if text == null:
		return
	var read: Variant = parse(text)
	if read == null:
		load_failed = true
	else:
		data = read


func _read_text() -> Variant:
	if _web:
		var v: Variant = JavaScriptBridge.eval(JS_READ % WEB_KEY, true)
		return v if v is String else null
	if not FileAccess.file_exists(path):
		return null
	return FileAccess.get_file_as_string(path)


func _write_text(text: String) -> bool:
	if _web:
		var ok: Variant = JavaScriptBridge.eval(JS_WRITE % [WEB_KEY, JSON.stringify(text)], true)
		return ok is String and ok == "ok"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


# 保存の文字を決まった形に直す。読めない・辞書でない・version が 1 でない時は null(既定値で始める)。
static func parse(text: String) -> Variant:
	var j := JSON.new()
	if j.parse(text) != OK or not (j.data is Dictionary):
		return null
	var v: Dictionary = j.data
	if not _is_num(v.get("version")) or float(v["version"]) != float(VERSION):
		return null
	var out := defaults()
	out["training_done"] = v.get("training_done") == true
	for e: bool in [false, true]:
		out[_k("practice_best", e)] = _record(v.get(_k("practice_best", e)))
		var d: Variant = v.get(_k("daily", e))
		if d is Dictionary and _is_num(d.get("day")):
			out[_k("daily", e)] = {"day": int(d["day"]), "first": _record(d.get("first")), "best": _record(d.get("best"))}
	var st: Variant = v.get("settings")
	if st is Dictionary:
		if _is_num(st.get("volume")) and int(st["volume"]) in B.VOLUMES:
			out["settings"]["volume"] = int(st["volume"])
		for k: String in ["shake", "reduce_flash", "easy"]:
			if st.get(k) is bool:
				out["settings"][k] = st[k]
	return out


static func _record(v: Variant) -> Variant:
	if not (v is Dictionary) or not _is_num(v.get("points")) or not _is_num(v.get("mttr10")):
		return null
	return {"points": int(v["points"]), "mttr10": maxi(int(v["mttr10"]), 0)}


static func _is_num(v: Variant) -> bool:
	return v is float or v is int


static func _better_of(a: Variant, b: Variant) -> Variant:
	if not (a is Dictionary):
		return b
	if not (b is Dictionary):
		return a
	return b if Score.better(b, a) else a


# 書く直前に今ある保存を読み直して合わせる(同じブラウザの別のタブが先に書いた記録を消さない)。
func _merge_from_disk() -> void:
	var text: Variant = _read_text()
	var disk: Variant = parse(text) if text != null else null
	if disk == null:
		return
	data["training_done"] = data["training_done"] or disk["training_done"]
	for e: bool in [false, true]:
		var pk := _k("practice_best", e)
		var dk := _k("daily", e)
		data[pk] = _better_of(data[pk], disk[pk])
		var mine: Variant = data[dk]
		var theirs: Variant = disk[dk]
		if theirs is Dictionary:
			if not (mine is Dictionary) or int(theirs["day"]) > int(mine["day"]):
				data[dk] = theirs
			elif int(theirs["day"]) == int(mine["day"]):
				data[dk] = {"day": mine["day"], "first": theirs["first"] if theirs["first"] != null else mine["first"],
					"best": _better_of(mine["best"], theirs["best"])}


func save_data() -> bool:
	_merge_from_disk()
	write_failed = not _write_text(JSON.stringify(data, "", false))
	return not write_failed


func training_done() -> bool:
	return data["training_done"]


func practice_best(easy: bool = false) -> Variant:
	return data[_k("practice_best", easy)]


# 今日の記録 { day, first, best }。日付が違えば空の物(保存はまだ書き換えない)。
func daily(day: int, easy: bool = false) -> Dictionary:
	var d: Variant = data[_k("daily", easy)]
	if d is Dictionary and int(d["day"]) == day:
		return d
	return {"day": day, "first": null, "best": null}


# 結果画面に入った時に呼ぶ(FR-23)。mode: 0 = 今日の夜、1 = 研修の夜、2 = 練習の夜。
# { prev_best, new_best, first_today, first_training, saved } を返す。
func record(mode: int, day: int, result: Dictionary, easy: bool = false) -> Dictionary:
	var pk := _k("practice_best", easy)
	var dk := _k("daily", easy)
	var rec := {"points": int(result["points"]), "mttr10": int(result["mttr10"])}
	var out := {"prev_best": null, "new_best": false, "first_today": false, "first_training": false, "saved": true}
	if mode == 1:
		out["first_training"] = not data["training_done"]
		data["training_done"] = true
	elif mode == 2:
		out["prev_best"] = data[pk]
		out["new_best"] = out["prev_best"] == null or Score.better(rec, out["prev_best"])
		if out["new_best"]:
			data[pk] = rec
	else:
		var stored: Variant = data[dk]
		if stored is Dictionary and int(stored["day"]) > day:
			return out  # 日付をまたいだ古い日の回(E-17)。新しい日の記録を置き換えない
		var today := daily(day, easy)
		out["prev_best"] = today["best"]
		out["new_best"] = today["best"] == null or Score.better(rec, today["best"])
		if today["first"] == null:
			today["first"] = rec
			out["first_today"] = true
		if out["new_best"]:
			today["best"] = rec
		data[dk] = today
	out["saved"] = save_data()
	return out


func settings() -> Dictionary:
	return data["settings"]


func set_setting(key: String, value: Variant) -> void:
	data["settings"][key] = value
	save_data()
