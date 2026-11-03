class_name CraftJob
extends RefCounted
## 一个进行中的制作任务：只存数据和一次性算好的配置，不持有 RecipeDef
## （定义可能被热重载，任务要能活过资源刷新，所以只存键）。
##
## 单独成文件是为了让 UI 能把它当类型用（内嵌在 autoload 里的类没法写进类型标注）。

var recipe_key: String
var facility_key: String
## 这一批做几份（1 = 普通单份；中间品配方可以一次多份）
var batches: int = 1
var total_seconds: float
var remaining_seconds: float


## 0..1 的完成度
func progress() -> float:
	if total_seconds <= 0.0:
		return 1.0
	return clampf(1.0 - remaining_seconds / total_seconds, 0.0, 1.0)
