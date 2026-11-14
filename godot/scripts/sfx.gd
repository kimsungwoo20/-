extends Node
# 효과음 재생기. 화면에 보이는 곳의 소리만 내고, 같은 소리는 짧은 간격 안에 겹치지 않게 한다.
# M 키로 소리를 끄고 켠다. 화면 없는 실행(점검·자동 대전)에서는 아무것도 하지 않는다.

const NAMES = ["select", "order", "bite", "spit", "snap", "death", "built", "ready", "research", "alarm", "error", "win", "lose"]
const GAP = {"bite": 0.07, "spit": 0.09, "snap": 0.08, "death": 0.06, "ready": 0.3, "alarm": 8.0, "error": 0.25, "select": 0.05, "order": 0.05}
const VOL = {"bite": -14.0, "spit": -15.0, "snap": -10.0, "death": -12.0, "select": -10.0, "order": -9.0, "error": -8.0, "alarm": -6.0}
const POOL = 10

static var muted = false

var streams = {}
var players = []
var last = {}
var enabled = true

func _ready():
	enabled = DisplayServer.get_name() != "headless"
	if not enabled:
		return
	for n in NAMES:
		var s = load("res://sounds/%s.wav" % n)
		if s != null:
			streams[n] = s
	for i in POOL:
		var p = AudioStreamPlayer.new()
		add_child(p)
		players.append(p)

# pos 가 주어지면 카메라에 보이는 곳일 때만 낸다
func play(name, pos = null, cam = null):
	if not enabled or muted or not streams.has(name):
		return
	if pos != null and cam != null:
		var half = get_viewport().get_visible_rect().size / cam.zoom / 2.0 + Vector2(60, 60)
		var d = (pos - cam.position).abs()
		if d.x > half.x or d.y > half.y:
			return
	var now = Time.get_ticks_msec() / 1000.0
	if now - last.get(name, -99.0) < GAP.get(name, 0.0):
		return
	last[name] = now
	for p in players:
		if not p.playing:
			p.stream = streams[name]
			p.volume_db = VOL.get(name, -6.0)
			p.pitch_scale = randf_range(0.93, 1.07) if GAP.has(name) and name not in ["alarm", "error"] else 1.0
			p.play()
			return
