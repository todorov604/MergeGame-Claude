extends SceneTree

## headless 测试入口：
##   godot --headless --path 02_Game -s res://tests/run_tests.gd

const TestResults = preload("res://tests/test_results.gd")
const TEST_SCRIPTS := [
	preload("res://tests/test_event_evaluator.gd"),
	preload("res://tests/test_core_defects.gd"),
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
]


func _initialize() -> void:
	var results = TestResults.new()
	for script in TEST_SCRIPTS:
		var test = script.new()
		test.run(results)
	print("")
	if results.failures.is_empty():
		print("PASS  %d checks" % results.checks)
		quit(0)
	else:
		for failure in results.failures:
			print("FAIL  " + failure)
		print("FAILED  %d/%d checks failed" % [results.failures.size(), results.checks])
		quit(1)
