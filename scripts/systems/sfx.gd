class_name Sfx
extends RefCounted
## 界面音效的唯一出口：`意图 → 音频文件 → SoundManager`。
##
## 为什么不让各处自己 `preload` + `play_ui_sound`：
## 同一个动作（比如「买到东西」）会在多个面板触发，音效散落各处就会漂移——
## 有的地方是 click_001、有的是 click_004，改一套手感要翻十个文件。
## 这里做一张意图表，调用方只说「我在做什么」，不关心哪个文件。
##
## 素材全部来自 Kenney Interface Sounds（`addons/kenney_interface_sounds/`，CC0）。
## 第一轮试玩曾换成 Cozy SFX Sampler，但第二轮反馈「太活泼、不符合原风格」，
## 最终回到 Kenney 原包，只挑同族里 3–6 kHz / >6 kHz 占比低的文件（见
## `docs/plans/2026-10-29-audio-harshness-inventory.md`）。
## 环境音 KNOCK / DISH_CLINK 来自 Kenney Impact Sounds（CC0），放 `assets/audio/sfx/`。

## 一个动作 = 一个意图；NONE 表示「这次不响」（调用方显式静音时用）
enum Intent {
	NONE,
	CLICK,
	TAB,
	OPEN,
	CLOSE,
	CONFIRM,
	DENY,
	COIN,
	BUY,
	SELL,
	UPGRADE,
	CRAFT_DONE,
	LETTER,
	MILESTONE,
	RESEARCH_OK,
	RESEARCH_FAIL,
	KNOCK,
	DISH_CLINK,
	# 来访：门口有动静（轻铃），与 UI 的 LETTER 区分开
	VISIT,
	# 委托交付：比零卖更响的一下，让玩家知道这单结掉了
	ORDER_DONE,
}

const SOUND_ROOT := "res://addons/kenney_interface_sounds/"

## 意图 → 文件。相对路径由 `SOUND_ROOT` 补全，`res://` 开头的原样使用。
## 选文件的标准：同族、时长接近原用途、3–6 kHz 与 >6 kHz 能量占比都低。
const FILES := {
	Intent.CLICK: "click_002.wav",
	Intent.TAB: "switch_003.wav",
	# open / close 一族在 Kenney 里普遍高频（>6 kHz 占 45–95%），改用同包的
	# maximize / minimize 系列：语义接近「面板掀开 / 收起」，两个频段能量都是 0。
	# OPEN 用更短的 maximize_009（228 ms，主频 1.4 kHz），CLOSE 用 minimize_008（245 ms）。
	Intent.OPEN: "maximize_009.wav",
	Intent.CLOSE: "minimize_008.wav",
	Intent.CONFIRM: "select_004.wav",
	Intent.DENY: "error_005.wav",
	Intent.COIN: "drop_002.wav",
	Intent.BUY: "glass_002.wav",
	Intent.SELL: "drop_003.wav",
	Intent.UPGRADE: "confirmation_004.wav",
	Intent.CRAFT_DONE: "confirmation_001.wav",
	Intent.LETTER: "bong_001.wav",
	Intent.MILESTONE: "confirmation_004.wav",
	Intent.RESEARCH_OK: "confirmation_001.wav",
	Intent.RESEARCH_FAIL: "error_005.wav",
	# 氛围层的环境音：Cup 与敲门声来自 Kenney Impact Sounds（CC0），放 assets/audio/sfx/
	Intent.KNOCK: "res://assets/audio/sfx/knock.ogg",
	Intent.DISH_CLINK: "res://assets/audio/sfx/dish_clink.ogg",
	# 来访铃：Kenney bong_001 的副本，改名是为了语义（敲门声不再代表来访）
	Intent.VISIT: "res://assets/audio/sfx/visit_bell.wav",
	Intent.ORDER_DONE: "drop_004.wav",
}

## 同一文件被两个意图复用时，靠降调区分（调用方仍然只说「在做什么」）：
## UPGRADE 与 MILESTONE 共用 confirmation_004，RESEARCH_OK 与 CRAFT_DONE 共用
## confirmation_001，RESEARCH_FAIL 与 DENY 共用 error_005。降调比升调安全——
## 升调会把能量推回 3–6 kHz，正是这一轮要压的频段。
const PITCH_BY_INTENT := {
	Intent.UPGRADE: 0.92,
	Intent.RESEARCH_OK: 0.94,
	Intent.RESEARCH_FAIL: 0.90,
}

## 池级增益（dB）：Kenney 这批素材峰值贴近 0 dBFS，叠加播放时偏响；
## 试玩反馈「整体音效有些过大」，统一压低 4 dB。只影响经过 Sfx 的音效，
## 不动音乐（音乐走 Music 池与 Music 总线，见 `addons/sound_manager/`）。
const GAIN_DB := -4.0

## 缓存已加载的音频，避免每次播放都走一次资源查找
static var _cache: Dictionary = {}


## 该意图对应的音频；没有登记或文件缺失时返回 null
static func stream(intent: int) -> AudioStream:
	if not FILES.has(intent):
		return null
	if _cache.has(intent):
		return _cache[intent] as AudioStream
	var path := String(FILES[intent])
	if not path.begins_with("res://"):
		path = SOUND_ROOT + path
	var resource := load(path) as AudioStream
	if resource == null:
		push_error("[Sfx] 音效加载失败：%s" % FILES[intent])
		return null
	_cache[intent] = resource
	return resource


static func has_stream(intent: int) -> bool:
	return stream(intent) != null


## 播放一个意图。`pitch` 用来做细微变化（同一动作连续触发时不至于像复读机）；
## `volume_db` 是相对池级增益的偏移（负数更轻），用来把「铜板落地」这类
## 环境音压到界面音之后（第七轮反馈 14）。
static func play(intent: int, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if intent == Intent.NONE or Engine.is_editor_hint():
		return
	var resource := stream(intent)
	if resource == null:
		return
	var manager := _manager()
	if manager == null:
		return
	var played_pitch := effective_pitch(intent, pitch)
	var player: AudioStreamPlayer
	if is_equal_approx(played_pitch, 1.0):
		player = manager.play_ui_sound(resource)
	else:
		player = manager.play_ui_sound_with_pitch(resource, played_pitch)
	# 池级增益：播放是 call_deferred 的，这里同步改音量，播放时已生效
	if player != null:
		player.volume_db = GAIN_DB + volume_db


## 意图自带的默认音高（同一文件被两个意图复用时用来区分）
static func effective_pitch(intent: int, pitch: float = 1.0) -> float:
	if is_equal_approx(pitch, 1.0) and PITCH_BY_INTENT.has(intent):
		return float(PITCH_BY_INTENT[intent])
	return pitch


## 所有已登记的意图（测试用来确保每个都指向真实文件）
static func registered_intents() -> Array[int]:
	var result: Array[int] = []
	for key in FILES.keys():
		result.append(int(key))
	result.sort()
	return result


static func _manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("SoundManager")
