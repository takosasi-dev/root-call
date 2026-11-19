# 端末の 1 行の編集・補完・履歴(仕様書 §9.4・D-8)。打鍵を整数で受け、打鍵の数を数える。
# 補完の候補は呼ぶ側(sim)が文脈から決めて complete() に渡す。
extends RefCounted

const B := preload("res://core/balance.gd")

const K_ENTER := 1000
const K_BACKSPACE := 1001
const K_TAB := 1002
const K_LEFT := 1003
const K_RIGHT := 1004
const K_UP := 1005
const K_DOWN := 1006

# press() の戻り値
const DROPPED := -1  # 捨てた(打鍵に数えない)
const EDITED := 0
const ENTER := 1
const TAB := 2

var text := ""
var cursor := 0
var keys := 0  # 打鍵の数
var history: Array[String] = []  # 新しい順
var hist_pos := -1  # -1 = 打ちかけの行
var draft := ""


static func accepts_char(c: int) -> bool:
	return (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c in [32, 45, 46, 61, 47, 95]


# 1 打鍵を受ける。
func press(code: int) -> int:
	if code >= 65 and code <= 90:
		code += 32  # 大文字は小文字にする(D-12)
	if code >= 32 and code <= 126:
		if not accepts_char(code) or text.length() >= B.LINE_MAX:
			return DROPPED  # E-1・E-2
		keys += 1
		text = text.substr(0, cursor) + char(code) + text.substr(cursor)
		cursor += 1
		hist_pos = -1  # E-12: 履歴から出した行を、打ちかけの行として編集する
		return EDITED
	match code:
		K_ENTER:
			keys += 1
			return ENTER
		K_BACKSPACE:
			keys += 1
			if cursor > 0:
				text = text.substr(0, cursor - 1) + text.substr(cursor)
				cursor -= 1
				hist_pos = -1
			return EDITED
		K_TAB:
			keys += 1
			return TAB
		K_LEFT:
			keys += 1
			cursor = maxi(cursor - 1, 0)
			return EDITED
		K_RIGHT:
			keys += 1
			if cursor >= text.length():
				return TAB  # D-6
			cursor += 1
			return EDITED
		K_UP:
			keys += 1
			if hist_pos + 1 < history.size():
				if hist_pos == -1:
					draft = text
				hist_pos += 1
				_put_line(history[hist_pos])
			return EDITED
		K_DOWN:
			keys += 1
			if hist_pos >= 0:
				hist_pos -= 1
				_put_line(draft if hist_pos == -1 else history[hist_pos])
			return EDITED
	return DROPPED


func _put_line(s: String) -> void:
	text = s
	cursor = s.length()


# 行を実行に回す。空でなければ履歴に入れ、行を空にする。実行した行を返す。
func commit() -> String:
	var line := text
	if not line.strip_edges().is_empty():
		history.push_front(line)
		if history.size() > B.HISTORY_MAX:
			history.resize(B.HISTORY_MAX)
	text = ""
	cursor = 0
	hist_pos = -1
	draft = ""
	return line


# カーソルの前の語の始まり。
func word_start() -> int:
	var i := cursor
	while i > 0 and text[i - 1] != " ":
		i -= 1
	return i


# 補う語の前にある語(小文字)。
func words_before() -> Array:
	var out: Array = []
	for w in text.substr(0, word_start()).to_lower().split(" ", false):
		out.append(w)
	return out


# 候補で補う。戻り値: { "result": "done" | "list" | "none", "list": [合う候補] }
func complete(candidates: Array) -> Dictionary:
	var start := word_start()
	var word := text.substr(start, cursor - start).to_lower()
	var hits: Array = candidates.filter(func(c: String) -> bool: return c.to_lower().begins_with(word))
	if hits.is_empty():
		return {"result": "none", "list": []}
	var fill: String = hits[0]
	if hits.size() == 1:
		if not fill.ends_with("=") and not text.substr(cursor).begins_with(" "):
			fill += " "
	else:
		fill = _common_head(hits)
		if fill.length() <= word.length():
			return {"result": "list", "list": hits}
	text = text.substr(0, start) + fill + text.substr(cursor)
	cursor = start + fill.length()
	if text.length() > B.LINE_MAX:
		text = text.substr(0, B.LINE_MAX)
		cursor = mini(cursor, B.LINE_MAX)
	hist_pos = -1
	return {"result": "done", "list": hits}


static func _common_head(list: Array) -> String:
	var head: String = list[0]
	for s: String in list:
		var n := 0
		while n < head.length() and n < s.length() and head[n].to_lower() == s[n].to_lower():
			n += 1
		head = head.substr(0, n)
	return head
