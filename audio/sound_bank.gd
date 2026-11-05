class_name SoundBank
extends RefCounted
## sound_bank.gd (v6.12.0): every sound file the game plays, and the music, as data.
## ------------------------------------------------------------------
## The files are made by tools/gen_sounds.py (synthesized, see assets/audio/CREDITS.md); the
## engines are not files (audio/engine_voice.gd synthesizes them live).
##
## SFX: name -> {files (in SFX_DIR, without ".wav"; one is picked at random), bus, db (level),
##   pitch (± random share), loop, gap (s: the same sound not again sooner), voices (at most this
##   many at once; the oldest stops)}. A missing key takes DEFAULT's value.
## MUSIC: name -> file in MUSIC_DIR. RACE_MUSIC: the theme (world/themes.gd) -> its race music.
## Buses: Master (a limiter), Music, SFX and Engine under it (game/audio: GameAudio.setup_buses).

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const BUSES: PackedStringArray = ["Music", "SFX", "Engine"]

const DEFAULT := {"bus": "SFX", "db": 0.0, "pitch": 0.0, "loop": false, "gap": 0.0, "voices": 4}

const SFX := {
	# car loops (audio/car_audio.gd sets their volume and pitch every frame)
	"tyre_squeal": {"files": ["tyre_squeal"], "loop": true},
	"gravel": {"files": ["gravel"], "loop": true},
	"snow": {"files": ["snow"], "loop": true},
	"road": {"files": ["road"], "loop": true},
	"wind": {"files": ["wind"], "loop": true},
	"scrape": {"files": ["scrape"], "loop": true},
	"nitro": {"files": ["nitro"], "loop": true},
	# car one-shots
	"hit_light": {"files": ["hit_light"], "pitch": 0.08, "gap": 0.08, "voices": 3},
	"hit_medium": {"files": ["hit_medium"], "pitch": 0.08, "gap": 0.1, "voices": 3},
	"hit_heavy": {"files": ["hit_heavy"], "pitch": 0.06, "gap": 0.12, "voices": 2},
	"land": {"files": ["land"], "pitch": 0.08, "gap": 0.15, "voices": 2},
	"nitro_on": {"files": ["nitro_on"], "db": -2.0, "pitch": 0.04, "gap": 0.2, "voices": 2},
	"blowoff": {"files": ["blowoff"], "db": -3.0, "pitch": 0.06, "gap": 0.4, "voices": 2},
	"respawn": {"files": ["respawn"], "db": -3.0, "voices": 1},
	# race cues
	"count": {"files": ["count"], "db": -3.0, "voices": 2},
	"go": {"files": ["go"], "db": -2.0, "voices": 1},
	"checkpoint": {"files": ["checkpoint"], "db": -3.0, "voices": 2},
	"lap": {"files": ["lap"], "db": -2.0, "voices": 1},
	"finish": {"files": ["finish"], "db": -1.0, "voices": 1},
	"medal": {"files": ["medal"], "db": -2.0, "voices": 1},
	"best": {"files": ["best"], "db": -2.0, "voices": 1},
	"unlock": {"files": ["unlock"], "db": -2.0, "voices": 1},
	# menus, the shop, the terminal
	"ui_move": {"files": ["ui_move"], "db": -2.0, "pitch": 0.03, "gap": 0.035, "voices": 3},
	"ui_confirm": {"files": ["ui_confirm"], "db": -4.0, "gap": 0.05, "voices": 2},
	"ui_back": {"files": ["ui_back"], "db": -4.0, "gap": 0.05, "voices": 2},
	"ui_error": {"files": ["ui_error"], "db": -5.0, "gap": 0.2, "voices": 1},
	"cash": {"files": ["cash"], "db": -2.0, "voices": 2},
	"key": {"files": ["key1", "key2", "key3", "key4"], "db": -3.0, "pitch": 0.05, "voices": 4},
	"key_enter": {"files": ["key_enter"], "db": -3.0, "voices": 2},
}

const MUSIC := {"menu": "menu.ogg", "overdrive": "overdrive.ogg", "neon": "neon.ogg", "dust": "dust.ogg"}
## The race music for each theme (an unknown theme: overdrive).
const RACE_MUSIC := {
	"meadow": "overdrive", "seaside": "overdrive", "highland": "overdrive",
	"night": "neon", "dusk": "neon", "arctic": "neon",
	"desert": "dust", "canyon": "dust", "alpine": "dust", "autumn": "dust",
}
const MENU_MUSIC := "menu"


## Sound `name`'s definition with the defaults filled in ({} for an unknown name).
static func sfx(name: String) -> Dictionary:
	if not SFX.has(name):
		return {}
	var d: Dictionary = DEFAULT.duplicate()
	d.merge(SFX[name], true)
	return d


## The race music of track `t` (its theme's).
static func race_music(theme: String) -> String:
	return String(RACE_MUSIC.get(theme, "overdrive"))


static func sfx_path(file: String) -> String:
	return SFX_DIR + file + ".wav"


static func music_path(name: String) -> String:
	return MUSIC_DIR + String(MUSIC.get(name, ""))
