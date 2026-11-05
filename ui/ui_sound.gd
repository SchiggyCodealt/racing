class_name UiSound
extends RefCounted
## ui_sound.gd (v6.12.0): the interface's sounds, by name.
## ------------------------------------------------------------------
## The screens in ui/ ask for a sound by name (UiSound.play("ui_move")) and the game plays it: the
## app sets `player` to its GameAudio's play (audio/sound_bank.gd has the names). Without a game
## (tests, previews) nothing is played, but `played` keeps the last names asked for, so tests can
## check them. ui/ never depends on the game's audio this way (as the terminal's commands).
## Names: ui_move (a selection or a value moves), ui_confirm (a button, open a screen), ui_back
## (close), ui_error (refused), key / key_enter (the terminal), cash (bought), unlock.

const KEEP := 64

## Called with the sound's name (the game: GameAudio.play).
static var player: Callable = Callable()
## The last names asked for, newest last (at most KEEP).
static var played: PackedStringArray = PackedStringArray()


static func play(name: String) -> void:
	played.append(name)
	if played.size() > KEEP:
		played = played.slice(played.size() - KEEP)
	if player.is_valid():
		player.call(name)


## How many of the last sounds were `name` (tests).
static func count(name: String) -> int:
	var n := 0
	for p in played:
		if p == name:
			n += 1
	return n


static func clear() -> void:
	played = PackedStringArray()
