class_name Unlocks
extends RefCounted
## unlocks.gd (v6.8.0): which tracks are open. The tracks open one at a time, in menu order:
## the first is always open, and every other one opens when a medal of MEDAL (bronze) or better
## is won on the track before it, with any car. An opened track stays open for good (the save
## file's career.tracks_open), even when a later version makes a medal harder or changes the
## track. The terminal's `unlock tracks` (SaveData.tracks_unlocked()) opens every track at once.
## ------------------------------------------------------------------
## A locked track can't be driven: no Drive and no Race the AI (game/app.gd refuses both with
## a message). Watch the AI and Train the AI work on every track (the AI lab pays nothing).
##
##   Unlocks.is_open(track_id)        -> bool (tracks the game doesn't know, e.g. a test road: true)
##   Unlocks.claim(track_id, medal)   after a finish that won `medal` ("author".."bronze" or ""):
##                                    opens the next track when the medal is bronze or better;
##                                    -> the id of the track this opened ("" when none was locked)
##   Unlocks.earns(medal)             -> true when `medal` is bronze or better
##   Unlocks.previous(id) / next(id)  -> the track before / after `id` in menu order ("" none)
##   Unlocks.lock_text(id)            -> "Bronze on Hairpin Valley to unlock" ("" when open)
##   Unlocks.open_count()             -> how many of the game's tracks are open
##   Unlocks.from_records(save)       -> the tracks a save from before v6.8.0 opens (SaveData's
##                                    one-time migration, on the raw save Dictionary)
##   Unlocks.catch_up(save)           -> (v6.23) the tracks its medals open that are not open yet
##                                    (SaveData, once whenever the game has more tracks than
##                                    when the save last ran: career.tracks_known)

## The medal (or better) on a track that opens the next one.
const MEDAL: String = "bronze"


static func is_open(track_id: String) -> bool:
	var i: int = Tracks.index_of(track_id)
	return i <= 0 or SaveData.tracks_unlocked() or SaveData.opened_tracks().has(track_id)


## True when `medal` ("author", "gold", "silver", "bronze" or "") is MEDAL or better.
static func earns(medal: String) -> bool:
	var k: int = Medals.ORDER.find(medal)
	return k >= 0 and k <= Medals.ORDER.find(MEDAL)


static func previous(track_id: String) -> String:
	var i: int = Tracks.index_of(track_id)
	return Tracks.ids()[i - 1] if i > 0 else ""


static func next(track_id: String) -> String:
	var i: int = Tracks.index_of(track_id)
	var ids: PackedStringArray = Tracks.ids()
	return ids[i + 1] if i >= 0 and i + 1 < ids.size() else ""


## A finish on `track_id` won `medal`: when it is bronze or better (on a track that is open),
## the next track opens for good. It is stored even when `unlock tracks` already opens it (so
## it stays open when the career is reset), but only a track that was locked is returned.
static func claim(track_id: String, medal: String) -> String:
	var nxt: String = next(track_id)
	if nxt == "" or not earns(medal) or not is_open(track_id):
		return ""
	var was_open: bool = is_open(nxt)
	SaveData.open_track(nxt)
	return "" if was_open else nxt


## What opens a locked track, for its tile and panel ("" when it is open).
static func lock_text(track_id: String) -> String:
	if is_open(track_id):
		return ""
	return "%s on %s to unlock" % [String(Medals.NAMES[MEDAL]), String(Tracks.def(previous(track_id)).get("name", ""))]


## The tracks a save's own best times open that are not open yet: the track after every open
## track with a best time (current, any car) of bronze or better. For a save that last ran when
## the game had fewer tracks (v6.23 added four after the finale): a medal won back then on what
## was the last track opens the first new one, as the finish would have. `save` is the raw save
## Dictionary (records, career.tracks_open), read only.
static func catch_up(save: Dictionary) -> PackedStringArray:
	var ids: PackedStringArray = Tracks.ids()
	var out: PackedStringArray = []
	var career: Variant = save.get("career")
	var open: Array = []
	if career is Dictionary and (career as Dictionary).get("tracks_open") is Array:
		open = career.tracks_open
	var recs: Variant = save.get("records")
	if not (recs is Dictionary):
		return out
	for i: int in ids.size() - 1:
		var tid: String = ids[i]
		var nxt: String = ids[i + 1]
		if open.has(nxt) or out.has(nxt) or not (recs.get(tid) is Dictionary):
			continue
		if i > 0 and not (open.has(tid) or out.has(tid)):
			continue
		for car: Variant in recs[tid]:
			var e: Variant = recs[tid][car]
			var time: Variant = (e as Dictionary).get("time") if e is Dictionary else null
			if not (time is float or time is int) or not (float(time) > 0.0) or not is_finite(float(time)) or not Cars.has_car(str(car)):
				continue
			if earns(Medals.medal_for(Medals.medal_times(Tracks.build(tid), str(car)), float(time))):
				out.append(nxt)
				break
	return out


static func open_count() -> int:
	var n: int = 0
	for id: String in Tracks.ids():
		if is_open(id):
			n += 1
	return n


## The tracks a save made before v6.8.0 (when every track was open) opens, in menu order: every
## track that has a best time (current or archived, any car), and the track after every track
## whose best time (current or archived, any car) is bronze or better. Archived times (made on an
## older version of the track) are compared with today's bronze time of that track and car.
## `save` is the raw save Dictionary (records, archive), read only.
static func from_records(save: Dictionary) -> PackedStringArray:
	var ids: PackedStringArray = Tracks.ids()
	var open: Dictionary = {}
	for i: int in ids.size():
		var tid: String = ids[i]
		var times: Array = [] # [car id, time]
		var recs: Variant = save.get("records")
		if recs is Dictionary and recs.get(tid) is Dictionary:
			for car: Variant in recs[tid]:
				times.append([str(car), (recs[tid][car] as Dictionary).get("time") if recs[tid][car] is Dictionary else null])
		var arch: Variant = (save.get("archive") as Dictionary).get("records") if save.get("archive") is Dictionary else null
		if arch is Dictionary and arch.get(tid) is Dictionary:
			for car: Variant in arch[tid]:
				if arch[tid][car] is Dictionary:
					for sig: Variant in arch[tid][car]:
						var e: Variant = arch[tid][car][sig]
						times.append([str(car), (e as Dictionary).get("time") if e is Dictionary else null])
		var driven: bool = false
		var medal: bool = false
		for ct: Array in times:
			var time: Variant = ct[1]
			if not (time is float or time is int) or not (float(time) > 0.0) or not is_finite(float(time)):
				continue
			driven = true
			if not medal and Cars.has_car(String(ct[0])):
				medal = earns(Medals.medal_for(Medals.medal_times(Tracks.build(tid), String(ct[0])), float(time)))
		if driven and i > 0:
			open[tid] = true
		if medal and i + 1 < ids.size():
			open[ids[i + 1]] = true
	var out: PackedStringArray = []
	for id: String in ids:
		if open.has(id):
			out.append(id)
	return out
