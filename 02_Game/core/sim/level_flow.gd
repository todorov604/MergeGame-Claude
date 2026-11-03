extends RefCounted

## 关卡顺序（M0 冻结规格 §2）：levels 数组顺序即关卡顺序，无 next 指针。
## 切关后的棋盘/订单/生成器重置由 SimState 负责，本类只管关卡顺序。
## 不依赖 Node / SceneTree。

var levels: Array = []
var index := 0


## 保存关卡数组（不强转、不拷贝），从第 0 关开始。
func setup(levels_array: Array) -> void:
	levels = levels_array
	index = 0


func current_level() -> Dictionary:
	if index < 0 or index >= levels.size():
		return {}
	var level_v: Variant = levels[index]
	if typeof(level_v) != TYPE_DICTIONARY:
		return {}
	var level: Dictionary = level_v
	return level


func has_next() -> bool:
	return index + 1 < levels.size()


## 有下一关则前进一步并返回 true；否则返回 false 且不改 index。
func next() -> bool:
	if not has_next():
		return false
	index += 1
	return true


func level_id() -> String:
	var level := current_level()
	var id_v: Variant = level.get("id")
	if typeof(id_v) == TYPE_STRING:
		return String(id_v)
	return ""


func snapshot() -> Dictionary:
	return {"index": index, "id": level_id()}
