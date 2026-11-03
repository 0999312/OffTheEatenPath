class_name UIKeys
extends RefCounted
## 面板 ID 常量。
##
## 面板 ID 在三个地方出现：GameBootstrap.PANEL_DEFS（登记）、HUD/桌面热点（打开）、
## 面板之间互相打开（如信箱 → 信件详情）。集中在这一个文件，避免三处各写一遍字符串。

## 本游戏的命名空间（DLC / UGC 将来可以另立命名空间）
const NS := "idle_food"

## 框架自检面板（P0 遗留，调试用）
const DIAGNOSTIC := "idle_food:diagnostic_panel"

const CRAFT := "idle_food:craft"
const RESEARCH := "idle_food:research"
const ORDERS := "idle_food:orders"
const CATALOG := "idle_food:catalog"
## 图鉴条目详情（弹层，由图鉴列表打开）
const CATALOG_DETAIL := "idle_food:catalog_detail"
const FACILITY := "idle_food:facility"
const MERCHANT := "idle_food:merchant"
## 仓库：清点手上材料/成品，按商人收购价出手（第三轮反馈「缺仓库显示」）
const WAREHOUSE := "idle_food:warehouse"
const MAIL := "idle_food:mail"
const SETTINGS := "idle_food:settings"
## 致谢与第三方许可（发布合规要求能在游戏里查到）
const CREDITS := "idle_food:credits"

## 弹窗
const LETTER_DETAIL := "idle_food:letter_detail"
const OFFLINE := "idle_food:offline"

## 环境提示（走 UIManager 的 TOAST 层，不是面板）
const TOAST_MESSAGE := "idle_food:toast_message"

## 底部按钮栏的固定入口（顺序 = 显示顺序）；设置单独放在最右
static func bar_entries() -> Array[Dictionary]:
	return [
		{"id": CRAFT, "label": "灶台", "hint": "制作食物"},
		{"id": RESEARCH, "label": "研究台", "hint": "试着组合出新的做法"},
		{"id": CATALOG, "label": "图鉴", "hint": "美食图鉴"},
		{"id": FACILITY, "label": "设备", "hint": "升级设备"},
		{"id": MERCHANT, "label": "商人", "hint": "购买材料"},
		{"id": MAIL, "label": "信箱", "hint": "读信"},
	]
