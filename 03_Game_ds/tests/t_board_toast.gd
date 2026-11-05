extends RefCounted
## M0 §7 item 4 "board full prompt" (N3): the board view owns a procedural toast,
## so the prompt needs no .tscn edit and no asset (ui_board_full_toast stays
## REFERENCE_ONLY and is never referenced).
##
## Headless-safe: BoardView.new() is never added to the tree, so _ready() (fonts,
## optional PLACEHOLDER frame) never runs and nothing is drawn. The toast state is
## pure data keyed on the view clock, which is what makes it testable without a
## viewport.

const BoardView = preload("res://src/view/board_view.gd")
const GAME_SCREEN := "res://src/view/game_screen.gd"
const MOVIE_SCENE := "res://src/render/movie_scene.gd"


func run(t) -> void:
	_defaults(t)
	_placement(t)
	_show_and_expire(t)
	_custom_duration(t)
	_clock_drives_lifetime(t)
	_source_wiring(t)


## §20.5 moved the board down to y=466 and the items bar starts at y=1731, so the
## toast strip has to sit above the bar and stay inside the 1080x1920 canvas.
func _placement(t) -> void:
	var bar: Rect2 = BoardView.TOAST_RECT
	t.eq(bar.size, Vector2(700, 84), "toast strip keeps its 700x84 size")
	t.ok(Rect2(0.0, 0.0, 1080.0, 1920.0).encloses(bar), "TOAST_RECT is fully inside 1080x1920",
			str(bar))
	t.ok(bar.end.y <= 1731.0, "toast sits above the items bar (y=1731)", str(bar.end.y))
	t.ok(bar.position.y >= BoardView.BOARD_ORIGIN.y, "toast is drawn over the board container",
			str(bar.position.y))
	t.ok(bar.position.y < BoardView.BOARD_ORIGIN.y + BoardView.BOARD_SIZE.y,
			"toast starts above the container bottom edge", str(bar.position.y))
	t.ok(absf(bar.get_center().x - 540.0) < 0.5, "toast is horizontally centred", str(bar.get_center()))


func _defaults(t) -> void:
	t.eq(BoardView.TOAST_SECONDS, 1.5, "TOAST_SECONDS is 1.5 s")
	var v = BoardView.new()
	t.eq(v.toast_text(), "", "toast_text starts empty")
	t.eq(v.toast_duration(), 1.5, "default toast duration is 1.5 s")
	t.eq(v.toast_alpha_at(0.0), 0.0, "no toast -> alpha 0")
	t.ok(not v.toast_active_at(0.0), "no toast -> inactive")
	v.free()


func _show_and_expire(t) -> void:
	var v = BoardView.new()
	v.show_toast("Board full")
	t.eq(v.toast_text(), "Board full", "show_toast stores the text")
	t.eq(v.toast_duration(), 1.5, "default seconds keeps the 1.5 s window")
	t.eq(v.toast_alpha_at(0.0), 1.0, "alpha is 1 at t=0")
	t.eq(v.toast_alpha_at(0.75), 1.0, "alpha is 1 at t=0.75")
	t.eq(v.toast_alpha_at(1.5), 0.0, "alpha is 0 at t=1.5")
	t.eq(v.toast_alpha_at(2.0), 0.0, "alpha stays 0 after the toast")
	t.ok(v.toast_active_at(0.0), "active at t=0")
	t.ok(not v.toast_active_at(1.5), "inactive at t=1.5")
	var mid: float = v.toast_alpha_at(1.375)
	t.ok(mid > 0.0 and mid < 1.0, "alpha fades linearly in the last 0.25 s", str(mid))
	v.free()


func _custom_duration(t) -> void:
	var v = BoardView.new()
	v.show_toast("Board is full", 2.0)
	t.eq(v.toast_duration(), 2.0, "custom seconds=2 is honoured")
	t.eq(v.toast_text(), "Board is full", "custom toast keeps its text")
	t.eq(v.toast_alpha_at(1.5), 1.0, "a 2 s toast is still opaque at 1.5 s")
	t.ok(v.toast_active_at(1.9), "a 2 s toast is active at 1.9 s")
	t.ok(not v.toast_active_at(2.0), "a 2 s toast ends at 2.0 s")
	v.free()


func _clock_drives_lifetime(t) -> void:
	var v = BoardView.new()
	v.show_toast("Board full")
	v.set_clock(0.5)
	t.ok(v.toast_active_at(0.5), "toast survives a clock advance inside its window")
	t.eq(v.toast_alpha_at(0.5), 1.0, "alpha stays 1 at t=0.5")
	v.set_clock(2.0)
	t.ok(not v.toast_active_at(2.0), "toast is gone once the clock passes 1.5 s")
	# a second prompt restarts the window at the current clock
	v.show_toast("Board full")
	t.ok(v.toast_active_at(2.0), "a new toast starts at the current clock")
	t.eq(v.toast_alpha_at(2.75), 1.0, "the restarted toast is opaque at 2.75 s")
	t.ok(not v.toast_active_at(3.6), "the restarted toast still expires 1.5 s later")
	v.free()


func _source_wiring(t) -> void:
	var game := FileAccess.get_file_as_string(GAME_SCREEN)
	t.ok(game.contains("SIM_BOARD_FULL"), "game_screen reacts to SIM_BOARD_FULL")
	t.ok(game.contains("board.full"), "game_screen reads the board.full locale key")
	t.ok(game.contains("show_toast"), "game_screen calls board.show_toast")
	t.ok(game.contains("set_clock"), "game_screen feeds the view clock to the board")
	var movie := FileAccess.get_file_as_string(MOVIE_SCENE)
	t.ok(movie.contains("board.full"), "movie_scene consumes the board.full locale key")
