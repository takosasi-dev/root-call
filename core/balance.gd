# 調整値(仕様書 §9.10・INV-7)。秒で書いた値は tick(1/120 秒)の整数で持つ。
# 夜の障害の重み、障害で変わる値、演出の時間もここに置く。ほかのファイルに数値の調整値を書かない。
extends RefCounted

const TICK_HZ := 120
const MAX_STEPS_PER_FRAME := 8
const NIGHT_TICKS := 28800  # 240 秒

# コマンドの実行の時間(tick)
const T_SSH := 60
const T_LOOK := 36
const T_RESTART := 240
const T_BACKUP := 360
const T_VACUUM := 240
const T_CERT := 360
const T_QUEUE := 240

# 悪化して止まるまで(tick)
const DISK_ESCALATE := 2400
const LEAK_ESCALATE := 3000

const LINE_MAX := 80
const HISTORY_MAX := 20
const SCREEN_MAX := 200  # 端末の行のさかのぼり(非機能 §2)
const BACKUP_PENALTY := 300

# 障害で変わる値(%・通)
const DISK_NORMAL := 41
const DISK_ALERT := 96
const DISK_FULL := 100
const MEM_NORMAL := 38
const MEM_ALERT := 91
const MEM_FULL := 100
const QUEUE_STUCK := 1200

# 今日の夜・練習の夜の並び(§9.8)
const SCHED_FIRST := 600
const SCHED_END := 27000
# [この tick より前なら, 間隔の最小, 間隔の幅]
const SCHED_GAPS := [[7200, 1800, 1200], [18000, 1200, 960], [NIGHT_TICKS, 840, 720]]
# [種類, サーバー, 重み]。種類 0 は「停止 web01 と 停止 web02 の同時」。種類とサーバーの番号は incidents.gd・servers.gd
const SCHED_TABLE := [
	[1, 0, 3], [1, 1, 3], [1, 2, 3], [1, 3, 3], [1, 4, 2], [1, 5, 2],
	[2, 3, 2], [2, 5, 1], [3, 2, 2], [4, 0, 1], [4, 1, 1],
	[5, 5, 2], [6, 3, 1], [0, 0, 1],
]

# 日替わりの種(共通 §3 の 13)
const DAY_SEED_MUL := 2654435761
const DAY_SALT := 0x5243
const EPOCH_YEAR := 2026

# テスト用の bot(§9.14)
const BOT_KEY_TICKS := 12

# 設定(共通 §3 の 17)
const VOLUMES := [0, 25, 50, 75, 100]
const DEFAULT_VOLUME := 75

# 演出(§9.13・画面設計書 §8)。ms
const SHAKE_PX := 4.0
const SHAKE_MS := 120
const FLASH_MS := 300
const FIXED_MS := 300
const COUNT_MS := 600
const OVER_MS := 600
const RETRY_LOCK_MS := 300
const CURSOR_BLINK_MS := 500
const REDUCED_FLASH_ALPHA := 0.2
