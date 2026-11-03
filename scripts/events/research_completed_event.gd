class_name ResearchCompletedEvent
extends Event
## 一次研究出结果了（成功或失败都会发）。
##
## `burned` 是这次失败烧掉的材料键；成功后为空。
## `succeeded` 单独给一个字段，而不是塞进 outcome：outcome 描述的是失败的类型，
## 成功时它没有意义（枚举里也没有「成功」这一档）。

var signature: String
var outcome: int
var recipe_key: String
var succeeded: bool
var burned: Array[String]


func _init(
	p_signature: String,
	p_outcome: int,
	p_recipe_key: String,
	p_succeeded: bool,
	p_burned: Array[String] = [],
) -> void:
	signature = p_signature
	outcome = p_outcome
	recipe_key = p_recipe_key
	succeeded = p_succeeded
	burned = p_burned
