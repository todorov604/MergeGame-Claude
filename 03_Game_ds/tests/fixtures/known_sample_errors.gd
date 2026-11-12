extends RefCounted
## 样例工程（`data/sample_project.json`）里的**已知内容错误**过滤。
##
## 2026-11-12（AGENTS §6.35）：那份 JSON 是操作者的内容，他随时会改；里面出现的
## 「任务行重复 / 棋子等级超出该实体上限 / 柜子压到障碍」属于**内容问题**，
## 不该让"验证器有没有回归"这类测试变红。
##
## 用法：
##     var extra := KnownSampleErrors.extra(report.codes())
##     t.eq(extra, [], "没有**新**的错误码", str(extra))
##
## 操作者把数据改干净后，`codes()` 里就没有这些码，`extra()` 依然返回空 —— 不用改测试。

## 已知的、属于操作者内容而非代码回归的错误码（按出现次数计）。
const KNOWN := [
	"ORDER_MISSION_DUP", "ORDER_MISSION_DUP",
	"SLOT_LEVEL_RANGE",
	"SAFE_OVERLAP",
]


## 从 `codes` 里扣掉已知码（按次数），返回剩下的"新错误"。
static func extra(codes: Array) -> Array:
	var budget: Array = KNOWN.duplicate()
	var out: Array = []
	for raw in codes:
		var code := String(raw)
		var idx := budget.find(code)
		if idx >= 0:
			budget.remove_at(idx)
		else:
			out.append(code)
	return out


## 便捷判断：除了已知内容问题，没有别的错误。
static func clean(codes: Array) -> bool:
	return extra(codes).is_empty()
