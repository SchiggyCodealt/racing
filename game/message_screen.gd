extends "res://ui/dialog_screen.gd"
## message_screen.gd
## ------------------------------------------------------------------
## A short message over the menu in the interface's dialog style (the web game used the
## browser's alert()): "Could not load network: …", "AI not ready: …". One OK button; Enter,
## Space, Esc, Backspace or the pad's A / B close it (the menu_accept / menu_back actions),
## as do the Close button and a click beside the panel.
## ask() is the same with a question and two buttons (v6.5.0: buying a car): the yes button
## (Enter, Space, the pad's A) runs its callback, Cancel (Esc, Backspace, the pad's B, Close, a
## click beside the panel) only closes.
##   show_message(title, text)
##   ask(title, text, yes_text, on_yes: Callable)

var _text: Label
var _ok: Button
var _yes: Button
var _on_yes: Callable = Callable()


func _init() -> void:
	super("Message")
	max_width = 560.0
	body.add_child(UiStyle.gap(0, UiStyle.S4))
	_text = UiStyle.label("", "text", UiStyle.FS_M, UiStyle.TEXT, 0.0, false, false, false, 24)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 1
	body.add_child(_text)
	body.add_child(UiStyle.gap(0, UiStyle.S5))
	var row := UiStyle.hbox(UiStyle.S4, BoxContainer.ALIGNMENT_END)
	_ok = UiStyle.button("OK", "PrimaryButton", 40)
	_ok.custom_minimum_size.x = 120
	_ok.pressed.connect(close)
	row.add_child(_ok)
	_yes = UiStyle.button("", "PrimaryButton", 40)
	_yes.custom_minimum_size.x = 120
	_yes.visible = false
	_yes.pressed.connect(confirm)
	row.add_child(_yes)
	body.add_child(row)


## Show `text` under `title` (replaces a message that is still open).
func show_message(title: String, text: String) -> void:
	_set_texts(title, text)
	_on_yes = Callable()
	_yes.visible = false
	_ok.text = "OK"
	_ok.theme_type_variation = "PrimaryButton"
	open()


## Ask a question: `yes_text` on the yes button (which calls `on_yes`, then closes), Cancel beside it.
func ask(title: String, text: String, yes_text: String, on_yes: Callable) -> void:
	_set_texts(title, text)
	_on_yes = on_yes
	_yes.text = yes_text
	_yes.visible = true
	_ok.text = "Cancel"
	_ok.theme_type_variation = ""
	open()


## True while a question (ask) is open.
var asking: bool:
	get:
		return visible and _yes.visible


## The yes button of a question: run its callback and close.
func confirm() -> void:
	var cb := _on_yes
	_on_yes = Callable()
	close()
	if cb.is_valid():
		cb.call()


func _set_texts(title: String, text: String) -> void:
	var head: Label = _title_label()
	if head != null:
		head.text = title
	_text.text = text


## The message's text (tests).
func text() -> String:
	return _text.text


func _title_label() -> Label:
	var head := body.get_child(0)
	for c in head.get_children():
		if c is Label:
			return c
	return null


## Keys and pad while it is open (the app forwards its input): any accept or back key closes a
## message; a question takes accept as yes and back as Cancel.
func handle_keys(inp: Object) -> void:
	if asking:
		if inp.consume(["menu_accept", "PadA"]):
			inp.clear_pressed()
			confirm()
			return
		if inp.consume(["menu_back", "menu", "PadB"]):
			close()
	elif inp.consume(["menu_accept", "menu_back", "menu", "PadA", "PadB"]):
		close()
	inp.clear_pressed()
