extends SceneTree
## run_tests.gd: runs every tests/test_*.gd (headless) and exits non-zero on a failure.
## ------------------------------------------------------------------
##   godot --headless --path <copy> --script res://tests/run_tests.gd [-- sim ui ...]
## (names after "--" run only those test files: "sim" runs tests/test_sim.gd.)
##
## A test file (one per area: test_sim.gd, test_world.gd, test_ui.gd, ...):
##   extends RefCounted
##   func run(t) -> bool:
##       t.check(1 + 1 == 2, "arithmetic works")      # prints "ok   ..." or "FAIL ..."
##       t.section("walls")                            # optional heading
##       return true                                   # last line: reaching it means no script error
## A script error stops the file's run() without returning true: that counts as a failure,
## as does a file that doesn't load or has no run(). Tests run in this SceneTree (no scene
## is loaded); a test that needs nodes can add them under t.tree.root and free them after.


## Handed to every test file's run().
class Checker:
	var tree: SceneTree
	var passed: int = 0
	var failed: int = 0
	var failures: PackedStringArray = []
	var file: String = ""

	func check(ok: bool, msg: String) -> bool:
		print("%s %s" % ["ok  " if ok else "FAIL", msg])
		if ok:
			passed += 1
		else:
			failed += 1
			failures.append("%s: %s" % [file, msg])
		return ok

	func section(title: String) -> void:
		print("-- ", title)


func _initialize() -> void:
	# (deferred: the root window enters the tree only after _initialize, and tests that add
	# nodes under t.tree.root need them inside the tree: sizes, containers, visibility)
	_run_all.call_deferred()


func _run_all() -> void:
	var only: PackedStringArray = OS.get_cmdline_user_args()
	var files: PackedStringArray = []
	for f: String in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd"):
			var area: String = f.trim_prefix("test_").trim_suffix(".gd")
			if only.is_empty() or only.has(area) or only.has(f):
				files.append(f)
	files.sort()
	var t := Checker.new()
	t.tree = self
	var t_all: int = Time.get_ticks_msec()
	for f: String in files:
		t.file = f
		print("\n== tests/%s" % f)
		var t0: int = Time.get_ticks_msec()
		var script: Variant = load("res://tests/" + f)
		if not (script is GDScript) or not (script as GDScript).can_instantiate():
			t.check(false, "%s loads" % f)
			continue
		var obj: Object = (script as GDScript).new()
		if not obj.has_method("run"):
			t.check(false, "%s has run(t)" % f)
			continue
		var before: int = t.failed
		var done: Variant = obj.call("run", t)
		if not (done is bool and done):
			t.check(false, "%s ran to the end (a script error stopped it)" % f)
		print("== %s: %s in %.1f s" % [f, "all passed" if t.failed == before else "%d FAILED" % (t.failed - before), (Time.get_ticks_msec() - t0) / 1000.0])
	print("\n%d checks passed, %d failed (%d test files, %.1f s)" % [t.passed, t.failed, files.size(), (Time.get_ticks_msec() - t_all) / 1000.0])
	for s: String in t.failures:
		print("  FAILED ", s)
	quit(1 if t.failed or files.is_empty() else 0)
