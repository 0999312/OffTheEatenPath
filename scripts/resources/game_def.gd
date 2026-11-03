class_name GameDef
extends CodecResource
## 全部静态内容定义的基类：《随食出发》里的材料、食物、配方、设备、信件、世界条目
## 都是它的子类，统一挂在 DataRegistry 下，用 `namespace:id` 形式的键互相引用。
##
## 为什么继承 CodecResource 而不是裸 Resource：
## - 框架已提供 DFU 风格 Codec（MapCodec.build / Codec.record），一份字段声明同时给出
##   校验、JSON 序列化（P5 存档复用）与往返测试，不必自己再写一套编解码；
## - 静态内容仍以 `.tres` 落盘，Inspector 可编辑，Codec 只在需要序列化的场合介入。
##
## 字段约定：
## - `id` 是路径部分（如 `item/coffee_bean`），不含命名空间；
## - `namespace` 默认 `game`；将来 DLC / UGC 内容可换命名空间而互不冲突；
## - 两者拼起来才是完整键（`game:item/coffee_bean`），配方、信件等引用一律用完整键。

const DEFAULT_NAMESPACE := "game"

## 命名空间（DLC / UGC 预留）
@export var namespace_id: String = DEFAULT_NAMESPACE
## 路径部分，如 `item/coffee_bean`
@export var id: String = ""
## 玩家可见名称
@export var display_name: String = ""
## 图鉴里的说明文字
@export_multiline var description: String = ""

## 完整键：`namespace:id`
func get_key() -> String:
	return "%s:%s" % [namespace_id, id]

## 转成框架的 ResourceLocation（注册表用它做键）
func get_resource_location() -> ResourceLocation:
	return ResourceLocation.new(namespace_id, id)

## id 与 namespace 是否满足 ResourceLocation 的合法字符规则
func is_key_valid() -> bool:
	return ResourceLocation.validate_namespace(namespace_id).is_success() \
		and ResourceLocation.validate_path(id).is_success()

## 取玩家可见文案。P3 起 `.tres` 里存的是 `data.*` 翻译键，此处按当前语言取值；
## 未迁移的定义仍可能是纯文本（运行时拼接的也走这里），原样返回以便兼容。
## 返回空串表示该字段没有内容，调用方自行兜底。
func localized(field: StringName = &"display_name") -> String:
	var raw := str(get(field))
	if raw.is_empty():
		return ""
	if raw.begins_with("data."):
		return I18n.t(raw)
	return raw

# ─── Codec ───

static func get_type_id() -> String:
	return "game_def"

## 基类字段的编解码；子类在自己 get_codec() 里先取这一份，再追加自己的字段
static func base_fields() -> Array:
	return [
		_opt_string("namespace_id", DEFAULT_NAMESPACE),
		_opt_string("id", ""),
		_opt_string("display_name", ""),
		_opt_string("description", ""),
	]

## 按 base_fields() 的字段顺序把值写回实例
static func apply_base(def: GameDef, values: Array) -> void:
	def.namespace_id = values[0]
	def.id = values[1]
	def.display_name = values[2]
	def.description = values[3]

static func get_codec() -> Codec:
	return Codec.record(MapCodec.build(base_fields(), func(...values): return _from_base(values)))

static func _from_base(values: Array) -> GameDef:
	var def := GameDef.new()
	apply_base(def, values)
	return def

# ─── 字段编解码小工具（子类复用） ───

## 可选 String 字段：解码缺失时用默认值，编码等于默认值时裁剪
static func _opt_string(prop: String, default_value: String) -> MapCodec:
	return Codec.STRING().optional_field_of(prop, default_value).for_getter(
		func(obj: Variant) -> String: return str(obj.get(prop)))

static func _opt_int(prop: String, default_value: int) -> MapCodec:
	return Codec.INT().optional_field_of(prop, default_value).for_getter(
		func(obj: Variant) -> int: return int(obj.get(prop)))

static func _opt_float(prop: String, default_value: float) -> MapCodec:
	return Codec.FLOAT().optional_field_of(prop, default_value).for_getter(
		func(obj: Variant) -> float: return float(obj.get(prop)))

static func _opt_bool(prop: String, default_value: bool) -> MapCodec:
	return Codec.BOOL().optional_field_of(prop, default_value).for_getter(
		func(obj: Variant) -> bool: return bool(obj.get(prop)))

## Array[MaterialStack] 字段
static func _opt_stacks(prop: String) -> MapCodec:
	return MaterialStack.get_codec().list_of().optional_field_of(prop, []).for_getter(
		func(obj: Variant) -> Array: return obj.get(prop))

## Array[String] 字段（如候选材料池）
static func _opt_strings(prop: String) -> MapCodec:
	return Codec.STRING().list_of().optional_field_of(prop, []).for_getter(
		func(obj: Variant) -> Array: return obj.get(prop))

## Array[float] 字段
static func _opt_floats(prop: String) -> MapCodec:
	return Codec.FLOAT().list_of().optional_field_of(prop, []).for_getter(
		func(obj: Variant) -> Array: return obj.get(prop))

## Array[int] 字段（如采集点各级收获数、升级花费）
static func _opt_ints(prop: String) -> MapCodec:
	return Codec.INT().list_of().optional_field_of(prop, []).for_getter(
		func(obj: Variant) -> Array: return obj.get(prop))

## Array[FacilityUpgrade] 字段
static func _opt_upgrades(prop: String) -> MapCodec:
	return FacilityUpgrade.get_codec().list_of().optional_field_of(prop, []).for_getter(
		func(obj: Variant) -> Array: return obj.get(prop))
