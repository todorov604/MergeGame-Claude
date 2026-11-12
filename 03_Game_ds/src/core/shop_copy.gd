extends RefCounted
## 底栏文案的唯一来源（实机 / 成片共用）。
##
## JSON 顶层 `shop` 节点可以覆盖底栏的标题、副标题和金币数量：
##
##   "shop": { "title": "...", "subtitle": "...", "reward": 88 }
##
## 缺省值与 `movie_scene` 里的 BAR_TITLE / BAR_SUBTITLE / BAR_COIN_REWARD 完全一致，
## 所以老数据（没有 shop 节点）画面一个字都不会变。
##
## 2026-11-11：操作者要求"游戏里下面的金币数量要 label 实现 Json 化"。

const DEFAULT_TITLE := "壳木壳木，CamelCamel"
const DEFAULT_SUBTITLE := "美宜制作，Made by MeiXuan"
const DEFAULT_REWARD := 88


## project.shop -> {title, subtitle, reward}，永远返回三个键。
static func from_project(project: Dictionary) -> Dictionary:
	var shop: Dictionary = {}
	if typeof(project) == TYPE_DICTIONARY:
		var raw = project.get("shop", null)
		if typeof(raw) == TYPE_DICTIONARY:
			shop = raw
	var title := String(shop.get("title", DEFAULT_TITLE))
	if title.is_empty():
		title = DEFAULT_TITLE
	var subtitle := String(shop.get("subtitle", DEFAULT_SUBTITLE))
	if subtitle.is_empty():
		subtitle = DEFAULT_SUBTITLE
	var reward := DEFAULT_REWARD
	var raw_reward = shop.get("reward", null)
	if typeof(raw_reward) == TYPE_INT or typeof(raw_reward) == TYPE_FLOAT:
		reward = maxi(0, int(raw_reward))
	elif typeof(raw_reward) == TYPE_STRING and String(raw_reward).is_valid_int():
		reward = maxi(0, int(raw_reward))
	return {"title": title, "subtitle": subtitle, "reward": reward}
