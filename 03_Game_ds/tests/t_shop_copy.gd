extends RefCounted
## 底栏文案（JSON shop）的唯一来源：实机与成片都读 ShopCopy.from_project()。

const ShopCopy := preload("res://src/core/shop_copy.gd")


func run(t) -> void:
	# 没有 shop 节点 → 与 movie_scene 的老常量完全一致（画面不变）
	var plain: Dictionary = ShopCopy.from_project({"meta": {"title": "X"}})
	t.eq(String(plain.get("title", "")), "壳木壳木，CamelCamel", "缺省标题不变")
	t.eq(String(plain.get("subtitle", "")), "美宜制作，Made by MeiXuan", "缺省副标题不变")
	t.eq(int(plain.get("reward", -1)), 88, "缺省金币=88")

	# 完整 shop → 三个字段都生效
	var full: Dictionary = ShopCopy.from_project({
		"shop": {"title": "测试标题", "subtitle": "测试副标题", "reward": 32}
	})
	t.eq(String(full.get("title", "")), "测试标题", "shop.title 生效")
	t.eq(String(full.get("subtitle", "")), "测试副标题", "shop.subtitle 生效")
	t.eq(int(full.get("reward", -1)), 32, "shop.reward 生效")

	# 只写一部分 → 其它字段回落到缺省
	var part: Dictionary = ShopCopy.from_project({"shop": {"reward": 7}})
	t.eq(String(part.get("title", "")), "壳木壳木，CamelCamel", "只配 reward 时标题回缺省")
	t.eq(int(part.get("reward", -1)), 7, "只配 reward 时数量生效")

	# 脏数据：负数 / 字符串 / 空串
	var dirty: Dictionary = ShopCopy.from_project({"shop": {"reward": -5, "title": ""}})
	t.eq(int(dirty.get("reward", -1)), 0, "负数奖励夹到 0")
	t.eq(String(dirty.get("title", "")), "壳木壳木，CamelCamel", "空标题回缺省")
	var as_text: Dictionary = ShopCopy.from_project({"shop": {"reward": "45"}})
	t.eq(int(as_text.get("reward", -1)), 45, "字符串数字也认")

	# 非字典的 shop 不崩
	var broken: Dictionary = ShopCopy.from_project({"shop": 5})
	t.eq(int(broken.get("reward", -1)), 88, "shop 不是字典时回缺省")
