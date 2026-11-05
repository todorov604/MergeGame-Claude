extends SceneTree

## headless 测试入口：
##   godot --headless --path 02_Game -s res://tests/run_tests.gd
## 结束哨兵：TEST-RUN-END checks=<n> failures=<n>；断言数少于 MIN_CHECKS 视为异常（防止静默跳过后假 PASS）。

const TestResults = preload("res://tests/test_results.gd")
## 与当前实测 checks 精确一致：任何测试脚本整体消失/被跳过都会使计数低于此值而失败。
## 增删测试时同步更新本常量与 README。
const MIN_CHECKS := 717
const TEST_SCRIPTS := [
	preload("res://tests/test_event_evaluator.gd"),
	preload("res://tests/test_core_defects.gd"),
	preload("res://tests/test_merge_gate.gd"),
	preload("res://tests/test_direct_order.gd"),
	preload("res://tests/test_validator.gd"),
	preload("res://tests/test_resource_guard.gd"),
	preload("res://tests/test_sim.gd"),
	preload("res://tests/test_board_view.gd"),
	preload("res://tests/test_order_view.gd"),
	preload("res://tests/test_timeline_model.gd"),
	preload("res://tests/test_timeline_player.gd"),
	preload("res://tests/test_view_layer.gd"),
	preload("res://tests/test_theme_doc.gd"),
	preload("res://tests/test_autosave.gd"),
	preload("res://tests/test_p0_features.gd"),
	preload("res://tests/test_manifest_snapshot.gd"),
]


func _initialize() -> void:
	var results = TestResults.new()
	for script in TEST_SCRIPTS:
		var test = script.new()
		test.run(results)
	print("")
	print("TEST-RUN-END checks=%d failures=%d" % [results.checks, results.failures.size()])
	if results.failures.is_empty() and results.checks >= MIN_CHECKS:
		print("PASS  %d checks" % results.checks)
		quit(0)
	else:
		for failure in results.failures:
			print("FAIL  " + failure)
		if results.checks < MIN_CHECKS:
			print("FAIL  断言数 %d 少于最小期望 %d（疑似测试被静默跳过）" % [results.checks, MIN_CHECKS])
		print("FAILED  %d/%d checks failed" % [results.failures.size(), results.checks])
		quit(1)
