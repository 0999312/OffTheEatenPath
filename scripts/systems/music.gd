class_name Music
extends RefCounted
## 背景音乐的接口层：曲目放在 `assets/audio/music/`，随机轮播。
##
## 为什么不做成 autoload：音乐没有状态要跨场景保有（`SoundManager` 自己就是常驻节点），
## 这里只是一层「文件名 → 资源 → SoundManager.music」的薄封装，静态函数够了。
##
## 素材约定：放进 `assets/audio/music/`，文件名（不含扩展名）就是曲目名，例如
## `assets/audio/music/white_space.ogg` → `Music.play("white_space")`。
## 一个文件都没有时，`play()` 只 push 一条 warning 并返回 false，不会影响游戏。
##
## 曲目来自 Cozy Tunes（pizzadoggy，单座许可）：只能随游戏使用，不得把音频文件
## 再分发给仓库外的人；`assets/audio/music/Cozy_Tunes_EULA.pdf` 是许可原文。

const MUSIC_ROOT := "res://assets/audio/music/"
const SUPPORTED := [".ogg", ".mp3", ".wav"]
const DEFAULT_CROSSFADE := 1.5

## 打包后 DirAccess 在 Web 上列不出被 remap 的音频条目，所以先按已知曲目探一遍；
## 目录里另外放进去的曲目仍会被列出来（开发时丢文件即可，不必改这个常量）。
const KNOWN_TRACKS: Array[String] = [
	"Cuddle_Clouds",
	"Drifting_Memories",
	"Evening_Harmony",
	"Far_Far_Away",
	"Floating_Dream",
	"Forgotten_Biomes",
	"Gentle_Breeze",
	"Golden_Gleam",
	"Polar_Lights",
	"Strange_Worlds",
	"Sunlight_Through_Leaves",
	"Wanderer's_Tale",
	"What_Clouds_Are_Made_Of",
	"Wildflowers_By_The_River",
]

## 提前多少秒开始预取下一首：盖住解码与文件读取的那一下卡顿
const PREFETCH_LEAD := 25.0

static var _current_track := ""
static var _player: AudioStreamPlayer
static var _warned := false
## 预取好的下一首（曲目名 + 资源路径）；空串表示没有
static var _prefetch_track := ""
static var _prefetch_path := ""


## 目录里现有的曲目名（按字母序），没有素材时是空数组
static func available_tracks() -> Array[String]:
	var tracks: Array[String] = []
	for track in KNOWN_TRACKS:
		if _resource_path(track) != "":
			tracks.append(track)
	var dir := DirAccess.open(MUSIC_ROOT)
	if dir != null:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not dir.current_is_dir() and not entry.ends_with(".import"):
				var ext := entry.get_extension().to_lower()
				if SUPPORTED.has("." + ext):
					var track_name := entry.get_basename()
					if not tracks.has(track_name):
						tracks.append(track_name)
			entry = dir.get_next()
		dir.list_dir_end()
	tracks.sort()
	return tracks


static func has_track(track: String) -> bool:
	return _resource_path(track) != ""


## 从候选里随机挑一首，尽量避开正在播的这首次（只有一首可选时才允许重复）。
## 抽出来单独成函数是为了能在测试里用固定输入验证「不重复」这条规则。
static func pick_random(tracks: Array[String], current: String = "") -> String:
	var pool: Array[String] = []
	for track in tracks:
		if track != current:
			pool.append(track)
	if pool.is_empty():
		return ""
	return pool[randi_range(0, pool.size() - 1)]


## 随机播一首；目录为空时返回 false，让调用方安静地什么都不做。
## 预取过的下一首已经在内存里，就用它，省掉切歌时的读取与解码。
static func play_random(crossfade: float = DEFAULT_CROSSFADE) -> bool:
	var tracks := available_tracks()
	if tracks.is_empty():
		return false
	if not _prefetch_track.is_empty() and tracks.has(_prefetch_track):
		return play(_prefetch_track, crossfade)
	var track := pick_random(tracks, _current_track)
	if track.is_empty():
		return play(tracks[0], crossfade)
	return play(track, crossfade)


## 播放一首；素材缺失时返回 false（同一条曲目的缺失只警告一次，避免刷屏）
static func play(track: String, crossfade: float = DEFAULT_CROSSFADE) -> bool:
	var manager := _manager()
	if manager == null:
		return false
	var path := _resource_path(track)
	if path.is_empty():
		if not _warned:
			_warned = true
			push_warning("[Music] 还没有背景音乐素材（%s%s.*），先安静着。" % [MUSIC_ROOT, track])
		return false
	var resource := _take_prefetched(track)
	if resource == null:
		# CACHE_MODE_IGNORE：播完这台就放掉，别把整张专辑留在资源缓存里
		resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as AudioStream
	if resource == null:
		push_error("[Music] 音乐加载失败：%s" % path)
		return false
	_player = manager.play_music(resource, crossfade)
	_current_track = track
	_drop_prefetch()
	return true


## 快到尾巴时把下一首读到内存里（后台线程），真正切歌时就不用等磁盘了。
## 由 `GameBootstrap` 的低频轮询调用，重复调用是安全的。
static func warm_next(crossfade: float = DEFAULT_CROSSFADE) -> void:
	if not _prefetch_track.is_empty():
		return
	if _player == null or not is_instance_valid(_player) or not _player.playing:
		return
	var stream := _player.stream
	if stream == null:
		return
	var left := stream.get_length() - _player.get_playback_position()
	if left > PREFETCH_LEAD + crossfade:
		return
	var tracks := available_tracks()
	var track := pick_random(tracks, _current_track)
	if track.is_empty():
		return
	var path := _resource_path(track)
	if path.is_empty():
		return
	_prefetch_track = track
	_prefetch_path = path
	ResourceLoader.load_threaded_request(path, "", false, ResourceLoader.CACHE_MODE_IGNORE)


## 预取的那首是不是已经就绪了（测试里用来说明「预取真的发生了」）
static func prefetched_track() -> String:
	return _prefetch_track


static func _take_prefetched(track: String) -> AudioStream:
	if _prefetch_path.is_empty() or track != _prefetch_track:
		return null
	var path := _prefetch_path
	var status := ResourceLoader.load_threaded_get_status(path)
	var stream: AudioStream = null
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		# 还没读完就同步读一次：只剩这一首可选，等它比切到别的曲子更划算
		stream = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as AudioStream
	elif status == ResourceLoader.THREAD_LOAD_LOADED:
		stream = ResourceLoader.load_threaded_get(path) as AudioStream
	_drop_prefetch()
	return stream


static func _drop_prefetch() -> void:
	_prefetch_track = ""
	_prefetch_path = ""


## 当前这首是不是快到尾巴了：提前 crossfade 秒返回 true，
## 让下一首的淡入刚好叠在旧曲的淡出上，而不是等播完再硬切。
static func needs_next(crossfade: float = DEFAULT_CROSSFADE) -> bool:
	if _player == null or not is_instance_valid(_player):
		return true
	if not _player.playing:
		return true
	var stream := _player.stream
	if stream == null:
		return true
	var length := stream.get_length()
	if length <= crossfade:
		return false
	return _player.get_playback_position() >= length - crossfade


static func stop(fade_out: float = 0.6) -> void:
	var manager := _manager()
	_current_track = ""
	_player = null
	_drop_prefetch()
	if manager == null:
		return
	manager.music.stop(fade_out)


static func is_playing() -> bool:
	var manager := _manager()
	if manager == null:
		return false
	return manager.is_music_playing()


static func current_track() -> String:
	return _current_track


## 音乐总线音量（0–1 线性）；没有 `Music` 总线时退到 Master
static func set_volume(linear: float) -> void:
	var index := AudioServer.get_bus_index("Music")
	if index < 0:
		index = 0
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(index, linear <= 0.001)


static func get_volume() -> float:
	var index := AudioServer.get_bus_index("Music")
	if index < 0:
		index = 0
	return db_to_linear(AudioServer.get_bus_volume_db(index))


static func _resource_path(track: String) -> String:
	for ext in SUPPORTED:
		var path := MUSIC_ROOT + track + String(ext)
		if ResourceLoader.exists(path):
			return path
	return ""


static func _manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("SoundManager")
