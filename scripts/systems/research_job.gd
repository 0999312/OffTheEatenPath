class_name ResearchJob
extends RefCounted
## 一次研究尝试：把一组材料放进研究台，等一段时间看结果。
##
## 与 CraftJob 分开而不是合并：研究有计划外的「失败」，还要记住烧掉了什么、
## 命中哪个配方，这些字段在制作里没有意义。

## 组合签名（材料键排序后 `+` 连接），也是研究记录的键
var signature: String = ""
## 投入的材料键（每样 1 份）
var materials: Array[String] = []
## 命中的待解锁配方键（没命中则空）
var recipe_key: String = ""
## 结果档位，取值见 GameState.ResearchOutcome
var outcome: int = 0
## 是否成功（成功时 recipe_key 指向被解锁的配方）
var succeeded: bool = false
## 失败时被烧掉的材料键
var burned: Array[String] = []
## 开始时实际扣掉的份数（材料键 → 份数，可能因概率多于 1 份）
var charged: Dictionary = {}
## 总耗时 / 剩余耗时（秒）
var total_seconds: float = 0.0
var remaining_seconds: float = 0.0

## 进度 0..1
func progress() -> float:
	if total_seconds <= 0.0:
		return 1.0
	return clampf(1.0 - remaining_seconds / total_seconds, 0.0, 1.0)

## 是否已经出结果
func is_done() -> bool:
	return remaining_seconds <= 0.0
