class_name FacilityUpgradedEvent
extends Event
## 设备升了一级。

var facility_key: String
var level: int


func _init(p_facility_key: String, p_level: int) -> void:
	facility_key = p_facility_key
	level = p_level
