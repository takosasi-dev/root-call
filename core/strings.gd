# 文言とコマンドの出力(INV-7・画面設計書 §6)。サーバーとサービスの名前、コマンドの語、補完の候補もここに置く。
# 文言を足したら tools/subset_font.py を回し直す(同梱の字体はここの文字に絞ってある)。
extends RefCounted

const NAME := "RootCall"
const VERSION := "v0.2.0"
const URL := "https://takosasi-dev.github.io/root-call/"

# サーバー(番号は servers.gd の WEB01〜MAIL)とサービス(§9.2)
const SERVERS := ["web01", "web02", "app01", "db01", "cache01", "mail01"]
const SERVICES := ["nginx", "nginx", "app", "postgresql", "redis", "postfix"]
const JUMP := "jump"
const PROMPT := "oncall@%s:~$ "

# コマンドの語(§9.5)
const W_SSH := "ssh"
const W_EXIT := "exit"
const W_STATUS := "status"
const W_HELP := "help"
const W_CLEAR := "clear"
const W_HISTORY := "history"
const W_SUDO := "sudo"
const W_SYSTEMCTL := "systemctl"
const W_RESTART := "restart"
const W_START := "start"
const W_DF := "df"
const W_FREE := "free"
const W_JOURNALCTL := "journalctl"
const W_CERTBOT := "certbot"
const W_POSTQUEUE := "postqueue"
# やさしいの短い形(renew・backup は A_RENEW・A_BACKUP と同じ語)
const W_VACUUM := "vacuum"
const W_FLUSH := "flush"
const A_BACKUP := "backup"
const A_VACUUM := "--vacuum-size=200M"
const A_RENEW := "renew"
const A_FLUSH := "-f"
const A_DF := "-h"
const A_FREE := "-m"
const FORBIDDEN_WORDS := ["rm", "reboot", "chmod", "shutdown", "kill"]

# 補完の候補(§9.4)
const C_FIRST_JUMP := ["ssh", "status", "help", "clear", "history"]
const C_FIRST_SERVER := ["exit", "ssh", "sudo", "systemctl", "df", "free", "journalctl", "certbot", "postqueue", "help", "clear", "history"]
const C_EASY := ["restart", "vacuum", "renew", "flush", "backup"]
const C_SUDO := ["systemctl", "journalctl", "certbot", "postqueue"]
const C_SYSTEMCTL := ["status", "restart", "start"]

# 誤りと断る文(§9.5)
const E_NOT_FOUND := "%s: コマンドが見つかりません"
const E_NEED_SUDO := "権限がありません。sudo を付けて実行する"
const E_NO_UNIT := "Unit %s.service が見つかりません"
const E_JUMP := "jump では使えない。ssh でサーバーへ入る"
const E_FORBIDDEN := "当番のマニュアルで禁止されている操作"
const E_NO_HOST := "ssh: %s というサーバーは無い"
const E_NOT_HERE := "%s: このサーバーでは使えない"

# 実行の結果(§9.5〜§9.7)
const R_SSH := "%s に入った"
const R_APP_FAIL := "app の起動に失敗: db01:5432 に繋がらない"
const R_APP_SLOW := "起動した。cache01:6379 に繋がらない(遅いまま)"
const R_NGINX_502 := "nginx を再起動した。上流が応答しない(HTTP 502 のまま)"
const R_DISK_FAIL := "%s の起動に失敗: ディスクがいっぱい"
const R_RESTARTED := "%s を再起動した"
const R_BACKUP := "バックアップを取り直した"
const R_VACUUM := "古いログを消した。ディスク %d%%"
const R_CERT := "証明書を更新した"
const R_QUEUE := "送信待ちを送り出した(%d 通)"
const R_FIXED := "直った(%s 秒)"
const R_DF := "/dev/sda1  使用率 %d%%"
const R_FREE := "メモリ  使用率 %d%%"
const R_UNIT := "%s.service: %s"
const R_LOG := "  最後のログ: %s"
const ST_RUNNING := "動いている"
const ST_STOPPED := "止まっている"
const ST_RESTARTING := "再起動中"
const LOG_OK := "異常なし"
const LOG_CRASH := "プロセスが異常終了した"
const LOG_DISK := "No space left on device(ディスクがいっぱい)"
const LOG_OOM := "メモリ不足で強制終了された"
const LOG_DB := "db01:5432 に繋がらない"
const LOG_LEAK := "メモリの使用が増え続けている"
const LOG_CACHE := "cache01:6379 に繋がらない"
const STATUS_LINE := "%-8s %-11s %s"
const HISTORY_LINE := "%3d  %s"

const HELP := [
	"使えるコマンド:",
	"  ssh <サーバー>            サーバーへ入る      exit  jump へ戻る",
	"  status                    6 台の状態(jump で)",
	"  systemctl status <サービス>  状態と最後のログ   df -h / free -m  ディスク / メモリ",
	"  sudo systemctl restart <サービス>  再起動",
	"  help / clear / history    説明 / 画面を消す / 履歴",
]
const HELP_TABLE := [
	"障害と直し方:",
	"  停止            sudo systemctl restart <サービス>",
	"  ディスクの逼迫  sudo journalctl --vacuum-size=200M",
	"  メモリの漏れ    sudo systemctl restart app",
	"  証明書の期限切れ  sudo certbot renew",
	"  送信待ちの詰まり  sudo postqueue -f",
	"  バックアップの失敗  sudo systemctl start backup",
]

const HELP_EASY := [
	"やさしい: sudo は省いてよい。直すコマンドは短い形でも通る",
	"  restart(再起動)  vacuum(ログを消す)  renew(証明書)  flush(送信待ち)  backup(取り直す)",
	"  直したいサーバーに入って、空の行で Tab を押すと、直すコマンドが入る",
]

# 研修の夜の案内(§9.11)
const GUIDE := [
	"障害の行の下に、直し方の下書きが出る。そのとおりに打てば直る",
	"ssh <サーバー名> でサーバーに入り、exit で jump に戻る",
	"Tab で続きを補える(行末なら → でも同じ)",
]

const GUIDE_EASY := [
	"赤い札が原因。障害の行の下の下書きのとおりに打てば直る",
	"ssh <サーバー名> でサーバーに入る。入ったら空の行で Tab → Enter で直る",
	"Tab で続きを補える(行末なら → でも同じ)",
]

# アラートの文(§9.6・§9.7)。種類の番号は incidents.gd
const KIND_TEXT := ["", "%s 停止", "ディスク %d%%", "メモリ %d%%", "証明書の期限切れ", "送信待ち %d 通", "バックアップの失敗"]
const IMPACT_502 := "HTTP 502(上流が応答しない)"
const IMPACT_DB := "DB に接続できない"
const IMPACT_SLOW := "応答が遅い(キャッシュに繋がらない)"
const EXPLAIN := ["影響: この札は巻き込まれているだけ。矢印をたどって、上流の原因を直す",
	"停止: サービスが止まっている。再起動すれば戻る",
	"ディスクの逼迫: ディスクがいっぱいになりかけている。古いログを消して空ける。放っておくと止まる",
	"メモリの漏れ: メモリを使い切りかけている。再起動すれば戻る。放っておくと止まる",
	"証明書の期限切れ: HTTPS の証明書が切れた。更新すれば戻る",
	"送信待ちの詰まり: メールが送られずにたまっている。送り出せば戻る",
	"バックアップの失敗: 夜のバックアップが失敗した。止まりはしないが、朝までに取り直す"]
const UPSTREAM := "上流を見る(web → app → db・cache)"
const IMPACT_FOLD := "影響 %d 台(%s)"
const IMPACT_FOLD_NOTE := "巻き込まれているだけ。上の原因の行を直せば戻る"
const IMPACT_SEP := "・"
const CAUSE := "原因"
const HINT_ARROW := " → "
const HINT_MORE := " …"

# 画面(画面設計書 §6)
const S0_START := "クリックかキーで始める"
const S0_KEYBOARD := "キーボードで遊ぶゲーム"
const TOUCH := "このゲームはキーボードで遊ぶ。PC で開いてほしい"
const IME := "日本語入力を切って(半角英数で)遊んでほしい"
const TAGLINE := "夜間当番。症状ではなく、原因から直す"
const B_TRAINING := "研修の夜"
const B_DAILY := "今日の夜"
const B_PRACTICE := "練習の夜(毎回ちがう並び)"
const B_SETTINGS := "設定"
const REC_FIRST := "1回目 %s点"
const REC_TODAY_BEST := "今日の最高 %s点"
const REC_BEST := "最高 %s点"
const REC_NONE := "まだ遊んでいない"
const LOAD_FAILED := "保存を読めなかったので、記録を初めからにした"
const BAR_UPTIME := "稼働率 %s%%"
const BAR_MTTR := "平均の復旧 %s 秒"
const BAR_MTTR_NONE := "平均の復旧 —"
const BAR_KEYS := "打鍵 %d"
const ESC := "Esc"
const MONITOR := "監視"
const ALERTS := "アラート"
const MARK_OK := "●"
const MARK_WARN := "▲"
const MARK_DOWN := "■"
const MARK_IMPACT := "◆"
const CARD_OK := "正常"
const CARD_WARN := "注意"
const CARD_DOWN := "停止"
const CARD_RESTART := "再起動中"
const CARD_IMPACT := "影響"
const UNTIL_STOP := "停止まで %d秒"
const TERMINAL := "端末"
const RUNNING := "(実行中 …)"
const DAWN := "夜が明けた"
const RES_POINTS := "%s点"
const RES_NEW_BEST := "最高 +%s(新しい記録)"
const RES_TO_BEST := "最高まで −%s"
const RES_TODAY_BEST := "(今日の最高 %s点)"
const RES_UPTIME := "稼働率 %s%%"
const RES_MTTR := "平均の復旧 %s 秒"
const RES_KEYS := "打鍵 %d"
const RES_FIXED := "直した数 %d"
const RES_CHART := "夜の健全さの推移(上が満点)"
const RES_BACKUP_OK := "バックアップ 済み"
const RES_BACKUP_NG := "バックアップ 未対応 −%d"
const RES_TRAINING_DONE := "研修を終えた。次は今日の夜へ"
const B_RETRY := "もう1回"
const B_COPY := "コピー"
const B_TITLE := "タイトルへ"
const COPIED := "コピーを試した。貼れない時は枠から写す"
const SAVE_FAILED := "このブラウザでは記録を残せない"
const SETTINGS := "設定"
const SET_VOLUME := "音量"
const SET_SHAKE := "画面の揺れ"
const SET_FLASH := "点滅を弱める"
const SET_LEVEL := "難しさ"
const LEVEL := ["ふつう", "やさしい"]
const LEVEL_NOTE := "やさしい: 障害がゆっくり・sudo 省略・短いコマンド・空の行の Tab で直し方が入る"
const ON := "入"
const OFF := "切"
const B_BACK := "戻る"
const PAUSE := "一時停止"
const B_RESUME := "続ける"
const B_RESTART := "やり直す"

# 共有する文字(§9.12)
const SHARE_HEAD := "%s %s(%s)"
const SHARE_BODY := "稼働率 %s%% / 平均の復旧 %s 秒 / 打鍵 %d"
const SHARE_BACKUP := " / バックアップ 未対応"
const MODE_LABEL := ["今日の夜", "研修の夜", "練習の夜"]
const DAILY_FIRST := "今日の夜・1回目"
const SHARE_EASY := "・やさしい"

# キーの確かめの画面(共通 §3 の 22。?keys=1 の時だけ)
const KEYS_TITLE := "キーの確かめ(押したキーを下に出す。Esc 2 回でタイトルへ)"
