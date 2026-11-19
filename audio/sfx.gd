# 効果音の再生(仕様書 §9.13・FR-26)。assets/sfx/*.wav を読み、プレイヤーを順繰りに使って重ねて鳴らす。
# 音量 0 か、unlock() の前(最初のクリック・キーの前)なら鳴らさない。読めないファイルは音なしで続ける。作りは ParryDuel の audio/sfx.gd。
extends Node

const NAMES: Array = ["key", "alert", "escalated", "fixed", "cmd_error", "forbidden", "bell", "over", "select"]
const VOICES := 8

var volume := 75  # 0〜100
var unlocked := false
var played := 0  # 再生を始めた回数(テストが読む)

var _streams := {}
var _voices: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for sound_name: String in NAMES:
		var path := "res://assets/sfx/" + sound_name + ".wav"
		if ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			if stream != null:
				_streams[sound_name] = stream
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)
	set_volume(volume)


func unlock() -> void:
	unlocked = true


# 25〜100 は 2 乗で dB に直す(100 → 0 dB、75 → −5 dB、50 → −12 dB、25 → −24 dB)。0 は鳴らさない。
func set_volume(percent: int) -> void:
	volume = clampi(percent, 0, 100)
	var db := linear_to_db(pow(volume / 100.0, 2.0)) if volume > 0 else -80.0
	for voice in _voices:
		voice.volume_db = db


func play(sound_name: String) -> void:
	if not unlocked or volume <= 0 or not _streams.has(sound_name):
		return
	var voice := _voices[_next]
	_next = (_next + 1) % VOICES
	voice.stream = _streams[sound_name]
	voice.play()
	played += 1
