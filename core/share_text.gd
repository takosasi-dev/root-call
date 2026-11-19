# 人に見せる結果の文字(仕様書 §9.12・共通 §3 の 12)。3 行。
extends RefCounted

const S := preload("res://core/strings.gd")
const Score := preload("res://core/score.gd")


# mode: 0 = 今日の夜、1 = 研修の夜、2 = 練習の夜。first_today は今日の夜の 1 回目か。
# easy なら見出しに「・やさしい」を足す。
static func make(date: String, mode: int, first_today: bool, result: Dictionary, easy: bool = false) -> String:
	var label: String = S.DAILY_FIRST if mode == 0 and first_today else S.MODE_LABEL[mode]
	if easy:
		label += S.SHARE_EASY
	var body := S.SHARE_BODY % [Score.pct1(int(result["uptime100"])), Score.sec1(maxi(int(result["mttr10"]), 0)), int(result["keys"])]
	if int(result["backups_left"]) > 0:
		body += S.SHARE_BACKUP
	return "\n".join([S.SHARE_HEAD % [S.NAME, date, label], body, S.URL])
