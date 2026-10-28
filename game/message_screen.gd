extends "res://ui/dialog_screen.gd"
## message_screen.gd
## ------------------------------------------------------------------
## A short message over the menu in the interface's dialog style (the web game used the
## browser's alert()): "Could not load network: …", "AI not ready: …". One OK button; Enter,
## Space, Esc, Backspace or the pad's A / B close it (the menu_accept / menu_back actions),
## as do the Close button and a click beside the panel.
##   show_message(title, text)

var _text: Label
var _ok: Button


func _init() -> void:
	super("Message")
	max_width = 560.0
	body.add_child(UiStyle.gap(0, UiStyle.S4))
	_text = UiStyle.label("", "text", UiStyle.FS_M, UiStyle.TEXT, 0.0, false, false, false, 24)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 1
	body.add_child(_text)
	body.add_child(UiStyle.gap(0, UiStyle.S5))
	var row := UiStyle.hbox(0, BoxContainer.ALIGNMENT_END)
	_ok = UiStyle.button("OK", "PrimaryButton", 40)
	_ok.custom_minimum_size.x = 120
	_ok.pressed.connect(close)
	row.add_child(_ok)
	body.add_child(row)


## Show `text` under `title` (replaces a message that is still open).
func show_message(title: String, text: String) -> void:
	var head: Label = _title_label()
	if head != null:
		head.text = title
	_text.text = text
	open()


func _title_label() -> Label:
	var head := body.get_child(0)
	for c in head.get_children():
		if c is Label:
			return c
	return null


## Keys and pad while it is open (the app forwards its input): any accept or back key closes it.
func handle_keys(inp: Object) -> void:
	if inp.consume(["menu_accept", "menu_back", "menu", "PadA", "PadB"]):
		close()
	inp.clear_pressed()
