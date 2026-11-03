class_name OfflineSummary
extends RefCounted
## 一次离线结算的结果，`OfflinePanel` 直接显示这个对象。
##
## 「离线」在本作里是解锁项（第 16 封信之后才有），所以摘要里带 `offline_unlocked`：
## 没解锁时面板显示预告，不显示收益。

## 超过这个时长才值得弹结算（短时间重开游戏不该打扰玩家）
const MIN_ELAPSED_SECONDS := 60.0

## 离开的时长（秒）
var elapsed_seconds: float = 0.0
## 期间净增的库存：[{key, name, type_id, kind, delta}]（kind 用来让成品排在材料前面）
var gains: Array[Dictionary] = []
## 期间铜币净变化（可能为负：期间有设备升级之类的支出）
var coins_gained: int = 0
## 期间订单板刷新的次数（离线时委托也在更新）
var orders_refreshed: int = 0
## 期间新解锁的信件键
var letter_keys: Array[String] = []
## 结算前的离线状态：false 表示这次结算时还没解锁离线
var offline_unlocked: bool = false
## 这次结算刚好解锁了离线
var unlocked_now: bool = false


## 有没有值得给玩家看的东西
func has_gains() -> bool:
	return not gains.is_empty() or coins_gained != 0 or not letter_keys.is_empty() or orders_refreshed > 0


## 是否应该真的弹面板（否则静默结算）
func is_meaningful() -> bool:
	return offline_unlocked and elapsed_seconds >= MIN_ELAPSED_SECONDS and has_gains()


## 「3 小时 12 分」这样的时长文案（随当前语言）
func elapsed_text() -> String:
	var total := int(elapsed_seconds)
	var days := total / 86400
	var hours := (total % 86400) / 3600
	var minutes := (total % 3600) / 60
	if days > 0:
		return I18n.t("ui.offline.elapsed_days", [days, hours])
	if hours > 0:
		return I18n.t("ui.offline.elapsed_hours", [hours, minutes])
	if minutes > 0:
		return I18n.t("ui.offline.elapsed_minutes", [minutes])
	return I18n.t("ui.offline.elapsed_less_minute")
