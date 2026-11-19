# bot 3 種を種 10 個で回し、稼働率・点・障害の数を印字する(AC-15・R-3 の数字を見る道具)。
# 実行: python tools/gd.py run res://tools/bot_report.gd [easy]
extends SceneTree

const Sim := preload("res://core/sim.gd")
const Bots := preload("res://core/bots.gd")
const Score := preload("res://core/score.gd")


func _initialize() -> void:
	var easy := OS.get_cmdline_user_args().has("easy")
	print("難しさ: ", "やさしい" if easy else "ふつう")
	var sums := [0, 0, 0]
	for s in range(1, 11):
		var row := "種 %2d:" % s
		for k in 3:
			var r: Dictionary = Bots.play(Sim.new(s, Sim.MODE_PRACTICE, null, easy), k)
			sums[k] += int(r["uptime100"])
			row += "  %s %s%% 点 %d 障害 %d 直 %d 打 %d" % [["正解", "症状", "無し"][k], Score.pct1(r["uptime100"]), r["points"], r["incidents"], r["fixed"], r["keys"]]
		print(row)
	var t: Dictionary = Bots.play(Sim.new(1, Sim.MODE_TRAINING, null, easy), 0)
	print("研修の夜 正解 bot: ", t)
	print("平均: 正解 %s%% / 症状 %s%% / 何もしない %s%%" % [Score.pct1(sums[0] / 10), Score.pct1(sums[1] / 10), Score.pct1(sums[2] / 10)])
	quit()
