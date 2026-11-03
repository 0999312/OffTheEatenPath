extends GutTest
## `Music` 是纯接口层：目录扫描与「随机但不连着重复」这两条规则都能在不开音频设备时验证。
## 素材是 Cozy Tunes 的 14 首（单座许可），见 `assets/audio/music/README.md`。

const EXPECTED_TRACKS := 14


func test_all_music_files_are_listed() -> void:
	var tracks := Music.available_tracks()
	assert_eq(tracks.size(), EXPECTED_TRACKS, "assets/audio/music/ 里的曲目数应与预期一致")
	assert_true(tracks.has("Cuddle_Clouds"), "曲目名取文件名（空格换成下划线）")


func test_has_track_checks_the_directory() -> void:
	assert_true(Music.has_track("Cuddle_Clouds"))
	assert_false(Music.has_track("not_a_track"))


func test_pick_random_avoids_the_current_track() -> void:
	var tracks: Array[String] = ["a", "b"]
	assert_eq(Music.pick_random(tracks, "a"), "b", "两首里正在播 a，只能挑 b")
	assert_eq(Music.pick_random(tracks, "b"), "a", "反过来也一样")


func test_pick_random_returns_empty_when_nothing_else_is_left() -> void:
	var single: Array[String] = ["a"]
	var none: Array[String] = []
	assert_eq(Music.pick_random(single, "a"), "", "只剩正在播的那首时不重复播")
	assert_eq(Music.pick_random(none, ""), "", "空目录返回空串，调用方据此安静地什么都不做")


func test_pick_random_can_return_any_track() -> void:
	var tracks: Array[String] = ["a", "b", "c"]
	var picked := Music.pick_random(tracks, "")
	assert_true(tracks.has(picked), "没有正在播的曲目时，候选项里的任意一首都可能被选中")
