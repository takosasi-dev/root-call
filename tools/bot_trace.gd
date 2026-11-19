# 1 つの種で正解 bot を回し、障害と端末の出力を時刻つきで印字する(bot が詰まる原因を見る道具)。
# 実行: python tools/gd.py run res://tools/bot_trace.gd <種> [bot の種類 0〜2]
extends SceneTree

const Sim := preload("res://core/sim.gd")
const Bots := preload("res://core/bots.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var s := int(args[0]) if args.size() > 0 else 7
	var sim := Sim.new(s, Sim.MODE_PRACTICE)
	var bot := Bots.new(int(args[1]) if args.size() > 1 else 0)
	for e: Dictionary in sim.plan:
		print("予定 %5.1f 秒 種類 %d サーバー %d" % [e["t"] / 120.0, e["kind"], e["server"]])
	var seen := 0
	while not sim.is_over():
		bot.act(sim)
		sim.step()
		for e: Dictionary in sim.events():
			if e["type"] != "key":
				print("%6.1f %s" % [sim.tick / 120.0, e])
		while seen < sim.lines.size():
			print("%6.1f   | %s" % [sim.tick / 120.0, sim.lines[seen][0]])
			seen += 1
		if sim.lines.size() >= 200:
			seen = mini(seen, sim.lines.size())
	print(sim.result())
	quit()
