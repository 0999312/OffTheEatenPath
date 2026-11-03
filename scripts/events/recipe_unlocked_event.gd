class_name RecipeUnlockedEvent
extends Event
## 一条配方被研究出来了：灶台从此能看到、能做。

var recipe_key: String


func _init(p_recipe_key: String) -> void:
	recipe_key = p_recipe_key
