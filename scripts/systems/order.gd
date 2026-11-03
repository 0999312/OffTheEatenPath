class_name Order
extends RefCounted
## 订单板上的一条委托：把某道菜做够数量交给客人，换铜币与一小份稀有材料。
##
## 为什么是 RefCounted 而不是 Resource：订单是运行时状态（会随存档变化），
## 不是编辑器里配置的静态内容；Resource 的引用语义反而容易让存档与内存共用一份。

## 自增编号（同一局内唯一，存档恢复后继续使用）
var id: int = 0
## 菜品完整键（kind == FOOD 的物品）
var dish_key: String = ""
## 需要交付的份数
var quantity: int = 1
## 交付后的铜币酬劳
var reward_coins: int = 0
## 额外赠送的材料完整键（空 = 没有）
var bonus_material: String = ""
## 额外赠送的份数
var bonus_amount: int = 0
## 是不是玩家招牌菜点的单（酬劳已经加过价，只用于界面标注）
var is_signature: bool = false
## 这道菜所属菜系（用于界面提示「招牌菜系」）
var signature_theme_key: String = ""
## 该菜系当前的招牌权重；只影响被抽中的概率，不改酬劳。1.0 = 没有菜系加成
var signature_theme_boost: float = 1.0


func to_dict() -> Dictionary:
	return {
		"id": id,
		"dish": dish_key,
		"quantity": quantity,
		"reward": reward_coins,
		"bonus": bonus_material,
		"bonus_amount": bonus_amount,
		"signature": is_signature,
		"signature_theme": signature_theme_key,
		"signature_boost": signature_theme_boost,
	}


static func from_dict(data: Dictionary) -> Order:
	var order := Order.new()
	order.id = int(data.get("id", 0))
	order.dish_key = String(data.get("dish", ""))
	order.quantity = maxi(1, int(data.get("quantity", 1)))
	order.reward_coins = maxi(0, int(data.get("reward", 0)))
	order.bonus_material = String(data.get("bonus", ""))
	order.bonus_amount = maxi(0, int(data.get("bonus_amount", 0)))
	order.is_signature = bool(data.get("signature", false))
	order.signature_theme_key = String(data.get("signature_theme", ""))
	order.signature_theme_boost = maxf(1.0, float(data.get("signature_boost", 1.0)))
	return order
