extends RefCounted
## terminal.gd (v6.7.0): what the terminal's commands do, as one table.
## ------------------------------------------------------------------
## The terminal (ui/terminal_screen.gd) opens from Settings (its Terminal row) or with the ` key
## on the menu and on Settings, never during a race. A command line is a command name and its
## arguments, separated by spaces, in any case: `money 5000`, `points set 200`, `car vortex`,
## `unlock all`. `help` lists the commands and `help <command>` explains one.
##
## Data-driven: COMMANDS holds every command, {name, args (its usage after the name), help (one
## line for `help`), more (the lines `help <name>` adds), run (the method that does it), complete
## (what Tab offers for the first argument: words, "@cars" every car id, "@commands" every
## command name), wipes (true: it loses progress, so it only runs when the line ends with
## "confirm"; without it the command says what it would do and how to confirm)}. A command
## method takes the arguments (lower case, PackedStringArray) and an Out to print to. A new
## command is one entry here and one method.
## Everything that changes the career goes through the save file's own functions, which write the
## file at once: SaveData.add_money / add_points (never below 0), give_car, unlock_tracks,
## reset_career, set_upgrades (v6.11.0), set_cup_place (v6.14.0: cup), and Economy.buy / buy_upgrade (the car picker's shop). `changed` then tells the screen to
## redraw the menu. Nothing a command is given can raise a script error: a bad command or
## argument prints a short message saying what to type instead.
##
##   var term := preload("res://game/terminal.gd").new()
##   term.run("money 5000")  -> {lines, changed, close, clear}
##       lines: [kind, text] with kind "ok" (a result), "info" (help, notes), "gain" / "loss"
##       (money or points up / down), "error" (what was wrong and what to type), "warn" (a
##       command that asks first), or ["row", label, value] (consecutive rows make a table)
##       changed: the career changed (redraw the menu); close: close the terminal; clear: clear its log
##   term.complete("mo")     -> {line: "money ", options: ["money"]}  (several matches: the line
##       completed as far as they agree, and all of them in options)
##   term.names()            -> every command name, in table order

## v6.17.0: `reset everything` wiped the save file (the app drops its copies of networks and the cup).
signal wiped

## The largest amount one command adds, takes or sets.
const MAX_AMOUNT: int = 1_000_000_000

const COMMANDS: Array[Dictionary] = [
	{name = "help", args = "[command]", help = "list the commands, or explain one", run = "_help",
		more = ["help lists every command; help <command> explains one, e.g. help money."], complete = ["@commands"]},
	{name = "money", args = "<n> | set <n>", help = "add money (a minus takes it away), or set it", run = "_money",
		more = ["money 5000 adds $5,000; money -2000 takes $2,000 away (money never goes below $0).",
			"money set 12000 makes it exactly $12,000. money on its own shows what you have.",
			"Commas are fine (5,000); at most 1,000,000,000 at a time."], complete = ["set"]},
	{name = "points", args = "<n> | set <n>", help = "add career points (a minus takes them away), or set them", run = "_points",
		more = ["points 200 adds 200 career points; points -50 takes 50 away (never below 0).",
			"points set 1000 makes them exactly 1,000. points on its own shows what you have."], complete = ["set"]},
	{name = "car", args = "<car> | all", help = "own a car without paying for it (or every car)", run = "_car",
		more = ["car vortex gives you the Vortex for free; car all gives you every car. Names in any case.",
			"car on its own lists the cars and what they cost in the shop. buy <car> pays for one instead."], complete = ["all", "@cars"]},
	{name = "buy", args = "<car> [part]", help = "buy a car, or a part's next level, with your money", run = "_buy",
		more = ["buy kestrel pays the Kestrel's price from your money, like BUY on the car picker.",
			"buy kestrel engine pays for the Kestrel's next engine level, like its chip on the car picker",
			"(parts: engine, tyres, nitro, loose)."], complete = ["@cars"]},
	{name = "upgrade", args = "<car> <part> <level> | <car> max | all max", help = "set a car's upgrades without paying", run = "_upgrade",
		more = ["upgrade dune engine 7 sets the Dune's engine to level 7 (0 to 10, free; parts: engine, tyres, nitro, loose).",
			"upgrade dune max: every part of the Dune at level 10; upgrade dune stock: every part back to 0.",
			"upgrade all max / upgrade all stock: every car you own. upgrade dune shows its levels; upgrade alone, every car's.",
			"Only cars you own (car <name> gives you one). buy <car> <part> pays for a level instead."], complete = ["all", "@cars"]},
	{name = "unlock", args = "all | cars | tracks", help = "own every car and open every track", run = "_unlock",
		more = ["unlock all: every car is yours and every track is open, for good (the save file keeps it).",
			"unlock cars: only the cars; unlock tracks: only the tracks (without it, bronze on a track opens the next)."],
		complete = ["all", "cars", "tracks"]},
	{name = "cup", args = "[<cup> <level> <place>]", help = "show the trophy cabinet, or set a cup's place at a level", run = "_cup",
		more = ["cup lists the championships and your best place in each at each level (the trophy cabinet).",
			"cup rookie pro 1 records 1st (a gold trophy) in the Rookie Cup at Pro without racing it; 0 takes it away.",
			"It pays nothing. Cups: rookie, asphalt, technical, dirt-snow, finale; levels: rookie, amateur, pro, expert, elite."],
		complete = ["rookie", "asphalt", "technical", "dirt-snow", "finale"]},
	{name = "status", args = "", help = "your money, points, cars, upgrades, medals and open tracks", run = "_status",
		more = ["status shows your money, career points, the cars you own and their upgrades, the medals you hold and the tracks open."]},
	{name = "reset", args = "career | everything", help = "start the career over, or everything back to a fresh install (asks first)", run = "_reset", wipes = true,
		more = ["reset career sets money and points to 0, keeps only the Racer (stock) and makes every medal and AI win pay again.",
			"Tracks opened by medals stay open (those only unlock tracks opened lock again). Best times, ghosts, AI networks",
			"and settings stay. It asks first: type yes (or reset career confirm) to do it.",
			"reset everything puts the game back as it was when first installed: money, points, cars, upgrades, opened tracks,",
			"paid rewards, trophies, the cup in progress, best times, medals, ghosts, scores, archived records and your AI",
			"networks all go; your settings stay. A backup of the save file is written next to it first.",
			"It asks first: type yes (or reset everything confirm) to do it."], complete = ["career", "everything"]},
	{name = "clear", args = "", help = "clear the terminal", run = "_clear", more = ["clear empties the terminal (Ctrl+L too)."]},
	{name = "exit", args = "", help = "close the terminal (Esc or ` too)", run = "_exit", more = ["exit closes the terminal, as Esc and ` do."]},
]


## What a command prints and asks for (handed to every command method).
class Out:
	var lines: Array = []
	var changed: bool = false
	var close: bool = false
	var clear: bool = false
	## The line ended with "confirm" (a command that wipes progress runs only then).
	var confirmed: bool = false
	## The line as typed, without "confirm" (for the confirm hint).
	var line: String = ""
	## (v6.18.0) confirm() asked: the next line may answer "yes" (Terminal.run).
	var asked: bool = false

	func add(kind: String, text: String) -> void:
		lines.append([kind, text])

	func row(label: String, value: String) -> void:
		lines.append(["row", label, value])

	## A command that wipes progress: true when the line was confirmed; else say what it would do
	## (`what`) and how to confirm, and return false.
	func confirm(what: String) -> bool:
		if confirmed:
			return true
		add("warn", what)
		add("warn", "Nothing has changed yet. Type yes to do it (or %s confirm); anything else leaves it." % line)
		asked = true
		return false

	func to_dict() -> Dictionary:
		return {lines = lines, changed = changed, close = close, clear = clear}


## (v6.18.0) The command line that asked first and waits for "yes" ("" none): see run().
var _pending: String = ""


# ---------------------------------------------------------------- running a line

## Run one command line (see the header for what comes back). An empty line does nothing.
func run(line: String) -> Dictionary:
	var out := Out.new()
	var words := _words(line)
	if words.is_empty():
		return out.to_dict()
	# (v6.18.0) the answer to a command that asked first: yes (or y) runs it, no (or n) drops it;
	# any other line drops it too and runs as usual
	if _pending != "":
		var asked_line := _pending
		_pending = ""
		if words.size() == 1 and (words[0] == "yes" or words[0] == "y"):
			return run(asked_line + " confirm")
		if words.size() == 1 and (words[0] == "no" or words[0] == "n"):
			out.add("info", "Left as it is: %s was not run." % asked_line)
			return out.to_dict()
	var cmd := find(words[0])
	if cmd.is_empty():
		var near := _nearest(words[0])
		out.add("error", "Unknown command %s.%s Type help for the list." % [_q(words[0]), " Did you mean %s?" % near if near != "" else ""])
		return out.to_dict()
	var args: PackedStringArray = words.slice(1)
	if cmd.get("wipes", false) and not args.is_empty() and args[args.size() - 1] == "confirm":
		out.confirmed = true
		args = args.slice(0, args.size() - 1)
	out.line = " ".join(PackedStringArray([String(cmd.name)]) + args)
	call(String(cmd.run), args, out)
	if out.asked:
		_pending = out.line
	return out.to_dict()


## The command called `name` (any case), or {}.
func find(name: String) -> Dictionary:
	var n := name.to_lower()
	for c: Dictionary in COMMANDS:
		if c.name == n:
			return c
	return {}


func names() -> PackedStringArray:
	var out: PackedStringArray = []
	for c: Dictionary in COMMANDS:
		out.append(String(c.name))
	return out


## A line's words, lower case (tabs and runs of spaces separate them).
static func _words(line: String) -> PackedStringArray:
	return line.strip_edges().to_lower().replace("\t", " ").split(" ", false)


## A word as the player typed it, quoted (cut short when very long).
static func _q(word: String) -> String:
	return "\"%s\"" % (word if word.length() <= 24 else word.left(24) + "…")


## The command name closest to a mistyped `word`, or "".
func _nearest(word: String) -> String:
	var best := ""
	var score := 0.55
	for n: String in names():
		var s := n.similarity(word.to_lower())
		if n.begins_with(word.to_lower()) and word.length() >= 2:
			s = maxf(s, 0.9)
		if s > score:
			score = s
			best = n
	return best


## A whole number from `s`: "5000", "5,000", "+5000", "-200", "$1_000". Null when it isn't one;
## a number above MAX_AMOUNT gives MAX_AMOUNT + 1 (the caller says it is too much).
static func parse_amount(s: String) -> Variant:
	var t := s.strip_edges().replace(",", "").replace("_", "")
	var neg := false
	if t.begins_with("+") or t.begins_with("-") or t.begins_with("−"):
		neg = not t.begins_with("+")
		t = t.substr(1)
	if t.begins_with("$"):
		t = t.substr(1)
	if t == "":
		return null
	for ch in t:
		if ch < "0" or ch > "9":
			return null
	t = t.lstrip("0")
	if t.length() > 10:
		return -(MAX_AMOUNT + 1) if neg else MAX_AMOUNT + 1
	var n := t.to_int() if t != "" else 0
	n = mini(n, MAX_AMOUNT + 1)
	return -n if neg else n


## The car id for `word` (an id or a name, any case), or "".
static func car_id(word: String) -> String:
	var w := word.to_lower()
	for id: String in Cars.ids():
		if id == w or String(Cars.get_car(id).name).to_lower() == w:
			return id
	return ""


static func _car_name(id: String) -> String:
	return String(Cars.get_car(id).name)


static func _car_list() -> String:
	return ", ".join(Cars.ids())


# ---------------------------------------------------------------- Tab

## Complete the word being typed: the command name, or a command's first argument (see
## COMMANDS `complete`). One match: the word and a space; several: as far as they agree, and
## `options` lists them; none: the line as it is.
func complete(line: String) -> Dictionary:
	var at := line.rfind(" ") + 1 # (the word being typed starts here)
	var before := line.substr(0, at)
	var word := line.substr(at).to_lower()
	var done := _words(before)
	var pool: PackedStringArray = []
	if done.is_empty():
		pool = names()
	elif done.size() == 1:
		var cmd := find(done[0])
		for w: String in cmd.get("complete", []):
			match w:
				"@cars":
					pool.append_array(Cars.ids())
				"@commands":
					pool.append_array(names())
				_:
					pool.append(w)
	var hits: PackedStringArray = []
	for w: String in pool:
		if w.begins_with(word) and not hits.has(w):
			hits.append(w)
	if hits.is_empty():
		return {line = line, options = PackedStringArray()}
	if hits.size() == 1:
		return {line = before + hits[0] + " ", options = hits}
	var common := hits[0]
	for w: String in hits:
		while not w.begins_with(common):
			common = common.left(common.length() - 1)
	return {line = before + (common if common.length() > word.length() else line.substr(at)), options = hits}


# ---------------------------------------------------------------- the commands

func _help(args: PackedStringArray, out: Out) -> void:
	if args.is_empty():
		for c: Dictionary in COMMANDS:
			out.row(("%s %s" % [c.name, c.args]).strip_edges(), String(c.help))
		out.add("info", "help <command> explains one. Tab completes a command, Up / Down bring back what you typed, Esc or ` closes.")
		return
	var c := find(args[0])
	if c.is_empty() or args.size() > 1:
		out.add("error", "help: no command %s. The commands: %s." % [_q(" ".join(args)), ", ".join(names())])
		return
	out.add("ok", ("%s %s" % [c.name, c.args]).strip_edges())
	for l: String in c.get("more", [c.help]):
		out.add("info", l)


func _money(args: PackedStringArray, out: Out) -> void:
	_amount(args, out, "money")


func _points(args: PackedStringArray, out: Out) -> void:
	_amount(args, out, "points")


## money / points: add n, take it away (a minus) or set it.
func _amount(args: PackedStringArray, out: Out, what: String) -> void:
	var money := what == "money"
	var fmt := func(n: int) -> String: return UiFormat.money(n) if money else "%s pts" % UiFormat.points(n)
	var have: int = SaveData.get_money() if money else SaveData.get_points()
	var title := what.capitalize()
	if args.is_empty():
		out.add("ok", "%s: %s" % [title, fmt.call(have)])
		out.add("info", "%s <n> adds n (%s -500 takes 500 away), %s set <n> sets it." % [what, what, what])
		return
	var setting := args[0] == "set"
	var rest: PackedStringArray = args.slice(1) if setting else args
	var usage := "%s set <n>" % what if setting else "%s <n> or %s set <n>" % [what, what]
	if rest.size() != 1:
		out.add("error", "%s: %s. Try: %s" % [what, "how much?" if rest.is_empty() else "one number only", "%s set 10000" % what if setting else "%s 5000" % what])
		return
	var n: Variant = parse_amount(rest[0])
	if n == null:
		out.add("error", "%s: %s is not a whole number. Try: %s (e.g. %s)" % [what, _q(rest[0]), usage, "%s 5000" % what])
		return
	if absi(int(n)) > MAX_AMOUNT:
		out.add("error", "%s: at most %s at a time." % [what, UiFormat.points(MAX_AMOUNT)])
		return
	if setting and int(n) < 0:
		out.add("error", "%s: it can't be below 0. Try: %s set 0" % [what, what])
		return
	var delta: int = int(n) - have if setting else int(n)
	var now: int = SaveData.add_money(delta) if money else SaveData.add_points(delta)
	var moved := now - have
	var sign := "+" if moved > 0 else "−"
	var amount: String = fmt.call(absi(moved))
	if moved > 0:
		out.add("gain", "%s %s%s: now %s" % [title, sign, amount, fmt.call(now)])
	elif moved < 0:
		out.add("loss", "%s %s%s: now %s" % [title, sign, amount, fmt.call(now)])
	else:
		out.add("info", "%s unchanged: %s" % [title, fmt.call(now)])
	if not setting and have + delta < 0:
		out.add("info", "(money never goes below $0)" if money else "(points never go below 0)")
	out.changed = moved != 0


func _car(args: PackedStringArray, out: Out) -> void:
	if args.is_empty():
		for id: String in Cars.ids():
			out.row(_car_name(id), "yours" if SaveData.owns_car(id) else "%s in the shop" % UiFormat.money(Economy.price(id)))
		out.add("info", "car <name> gives you one for free, car all every car; buy <name> pays for one.")
		return
	var ids: PackedStringArray = []
	if args.size() == 1 and args[0] == "all":
		ids = Cars.ids()
	else:
		for w: String in args:
			var id := car_id(w)
			if id == "":
				out.add("error", "car: there is no car called %s. The cars: %s (or all)." % [_q(w), _car_list()])
				return
			if not ids.has(id):
				ids.append(id)
	var given: PackedStringArray = []
	var had: PackedStringArray = []
	for id: String in ids:
		if SaveData.give_car(id):
			given.append(_car_name(id))
		else:
			had.append(_car_name(id))
	if not given.is_empty():
		out.add("gain", "Now yours: %s (free)." % ", ".join(given))
		out.changed = true
	if not had.is_empty():
		out.add("info", "You already own every car." if given.is_empty() and args[0] == "all" else "Already yours: %s." % ", ".join(had))
	out.add("ok", "You own %d of %d cars." % [SaveData.owned_cars().size(), Cars.ids().size()])


func _buy(args: PackedStringArray, out: Out) -> void:
	if args.size() < 1 or args.size() > 2:
		out.add("error", "buy: which car? Try: buy kestrel (or buy kestrel engine for its next engine level). The cars: %s." % _car_list())
		return
	var id := car_id(args[0])
	if id == "":
		out.add("error", "buy: there is no car called %s. The cars: %s." % [_q(args[0]), _car_list()])
		return
	if args.size() == 2:
		_buy_part(id, args[1], out)
		return
	var r := Economy.buy(id)
	match String(r.error):
		"":
			out.add("loss", "Bought the %s for %s: %s left." % [_car_name(id), UiFormat.money(int(r.price)), UiFormat.money(SaveData.get_money())])
			out.changed = true
		"owned":
			out.add("info", "You already own the %s." % _car_name(id))
		"money":
			out.add("error", "buy: the %s costs %s and you have %s: %s short. Try: money %d" % [_car_name(id), UiFormat.money(int(r.price)),
				UiFormat.money(SaveData.get_money()), UiFormat.money(int(r.short)), int(r.short)])
		_:
			out.add("error", "buy: the %s can't be bought." % _car_name(id))


## buy <car> <part>: the part's next level with the career's money (Economy.buy_upgrade).
func _buy_part(id: String, word: String, out: Out) -> void:
	var part := Upgrades.part_id(word)
	if part == "":
		out.add("error", "buy: there is no part called %s. The parts: %s." % [_q(word), _part_list()])
		return
	var pname := String(Upgrades.part(part).name).to_lower()
	var r := Economy.buy_upgrade(id, part)
	match String(r.error):
		"":
			out.add("loss", "Bought the %s's %s level %d (%s) for %s: %s left." % [_car_name(id), pname, int(r.level), Upgrades.effect(part, int(r.level)),
				UiFormat.money(int(r.price)), UiFormat.money(SaveData.get_money())])
			out.changed = true
		"locked":
			out.add("error", "buy: you don't own the %s. Try: buy %s (or car %s), then its parts." % [_car_name(id), id, id])
		"max":
			out.add("info", "The %s's %s is at level %d already, the top." % [_car_name(id), pname, Upgrades.MAX_LEVEL])
		"money":
			out.add("error", "buy: the %s's %s level %d costs %s and you have %s: %s short. Try: money %d" % [_car_name(id), pname,
				SaveData.get_upgrades(id)[Upgrades.index_of(part)] + 1, UiFormat.money(int(r.price)), UiFormat.money(SaveData.get_money()),
				UiFormat.money(int(r.short)), int(r.short)])
		_:
			out.add("error", "buy: that can't be bought.")


static func _part_list() -> String:
	return ", ".join(Upgrades.ids())


## A car's levels for the terminal: "engine 2, tyres 0, nitro 1, loose 3" (with the short part ids).
static func _levels_text(levels: PackedInt32Array) -> String:
	var parts: PackedStringArray = []
	var ids := Upgrades.ids()
	for i in ids.size():
		parts.append("%s %d" % [ids[i], levels[i]])
	return ", ".join(parts)


## What the upgrades bought for car `id` cost at the shop's prices.
static func upgrades_value(id: String) -> int:
	var lv := SaveData.get_upgrades(id)
	var out := 0
	var ids := Upgrades.ids()
	for i in ids.size():
		for k in range(1, lv[i] + 1):
			out += Upgrades.price(id, ids[i], k)
	return out


func _upgrade(args: PackedStringArray, out: Out) -> void:
	if args.is_empty():
		for id: String in Cars.ids():
			out.row(_car_name(id), _levels_text(SaveData.get_upgrades(id)) if SaveData.owns_car(id) else "not yours")
		out.add("info", "upgrade <car> <part> <level> sets one (0 to %d), upgrade <car> max every part, upgrade all max every car; buy <car> <part> pays." % Upgrades.MAX_LEVEL)
		return
	var all := args[0] == "all"
	var id := "" if all else car_id(args[0])
	if not all and id == "":
		out.add("error", "upgrade: there is no car called %s. The cars: %s (or all)." % [_q(args[0]), _car_list()])
		return
	var ids: PackedStringArray = []
	if all:
		for c: String in SaveData.owned_cars():
			ids.append(c)
	else:
		ids.append(id)
	if args.size() == 1:
		if all:
			out.add("error", "upgrade: try upgrade all max or upgrade all stock.")
			return
		var lv := SaveData.get_upgrades(id)
		var pids := Upgrades.ids()
		for i in pids.size():
			var nxt := Upgrades.price(id, pids[i], lv[i] + 1)
			out.row(String(Upgrades.PARTS[i].name), "level %d of %d%s" % [lv[i], Upgrades.MAX_LEVEL,
				", next %s" % UiFormat.money(nxt) if nxt > 0 else " (the top)"])
		if not SaveData.owns_car(id):
			out.add("info", "You don't own the %s: buy %s (or car %s) first." % [_car_name(id), id, id])
		return
	var levels := PackedInt32Array()
	var what := ""
	if args.size() == 2 and (args[1] == "max" or args[1] == "stock"):
		levels = Upgrades.stock()
		if args[1] == "max":
			levels.fill(Upgrades.MAX_LEVEL)
		what = "every part at level %d" % levels[0]
	elif args.size() == 3 and not all:
		var part := Upgrades.part_id(args[1])
		if part == "":
			out.add("error", "upgrade: there is no part called %s. The parts: %s." % [_q(args[1]), _part_list()])
			return
		var n: Variant = parse_amount(args[2])
		if n == null or args[2].begins_with("+") or args[2].begins_with("-") or int(n) < 0 or int(n) > Upgrades.MAX_LEVEL:
			out.add("error", "upgrade: the level is 0 to %d. Try: upgrade %s %s %d" % [Upgrades.MAX_LEVEL, id, part, Upgrades.MAX_LEVEL])
			return
		levels = SaveData.get_upgrades(id)
		levels[Upgrades.index_of(part)] = int(n)
		what = "%s level %d (%s)" % [String(Upgrades.part(part).name).to_lower(), int(n), Upgrades.effect(part, int(n))]
	else:
		out.add("error", "upgrade: try upgrade %s engine 3, upgrade %s max or upgrade all max (parts: %s)." % [
			"dune" if all else id, "dune" if all else id, _part_list()])
		return
	if ids.is_empty():
		out.add("info", "You own no cars to upgrade.")
		return
	for c: String in ids:
		if not SaveData.owns_car(c):
			out.add("error", "upgrade: you don't own the %s. Try: car %s (free) or buy %s, then upgrade it." % [_car_name(c), c, c])
			return
	var changed := false
	for c: String in ids:
		var before := SaveData.get_upgrades(c)
		var now := levels.duplicate()
		SaveData.set_upgrades(c, now)
		changed = changed or before != SaveData.get_upgrades(c)
	if all:
		out.add("gain" if changed else "info", "Every car you own (%d): %s%s." % [ids.size(), what, "" if changed else " already"])
	else:
		out.add("gain" if changed else "info", "The %s: %s%s. Now %s." % [_car_name(id), what, "" if changed else " already", _levels_text(SaveData.get_upgrades(id))])
	out.changed = out.changed or changed


func _unlock(args: PackedStringArray, out: Out) -> void:
	var what := args[0] if args.size() == 1 else ""
	if not (what in ["all", "cars", "tracks"]):
		out.add("error", "unlock: try unlock all (every car and track), unlock cars or unlock tracks.")
		return
	if what != "tracks":
		var given: PackedStringArray = []
		for id: String in Cars.ids():
			if SaveData.give_car(id):
				given.append(_car_name(id))
		if given.is_empty():
			out.add("info", "Cars: every car was already yours.")
		else:
			out.add("gain", "Cars: every car is yours (new: %s)." % ", ".join(given))
			out.changed = true
	if what != "cars":
		if SaveData.unlock_tracks(true):
			out.add("gain", "Tracks: every track is open, for good (the save file keeps it).")
			out.changed = true
		else:
			out.add("info", "Tracks: every track was already open.")


func _status(_args: PackedStringArray, out: Out) -> void:
	out.row("Money", UiFormat.money(SaveData.get_money()))
	out.row("Points", "%s pts" % UiFormat.points(SaveData.get_points()))
	var own: PackedStringArray = []
	for id: String in SaveData.owned_cars():
		own.append(_car_name(id))
	out.row("Cars", "%s (%d of %d)" % [", ".join(own), own.size(), Cars.ids().size()])
	out.row("Upgrades", upgrades_row())
	var m := medal_counts()
	var parts: PackedStringArray = []
	for k: String in Medals.ORDER:
		parts.append("%d %s" % [int(m[k]), k])
	out.row("Medals", "%s (the best of each track and car; %d of %d tracks have one)" % [", ".join(parts), int(m.tracks), Tracks.ids().size()])
	out.row("Tracks", tracks_row())
	out.row("Cups", cups_row())


## The status row of the upgrades: each upgraded car's levels ("Racer E3 T1 N0 L0") and what
## they cost against every part of every car.
static func upgrades_row() -> String:
	var cars: PackedStringArray = []
	var spent := 0
	for id: String in SaveData.owned_cars():
		var lv := SaveData.get_upgrades(id)
		if not Upgrades.is_stock(lv):
			cars.append("%s %s" % [_car_name(id), Upgrades.code(lv)])
			spent += upgrades_value(id)
	if cars.is_empty():
		return "none: every car stock (%s buys every part of every car)" % UiFormat.money(Upgrades.total_all())
	return "%s (%s of the %s every part of every car costs)" % [", ".join(cars), UiFormat.money(spent), UiFormat.money(Upgrades.total_all())]


## The status row of the tracks: how many are open, and what opens the next locked one.
static func tracks_row() -> String:
	var n := Tracks.ids().size()
	if SaveData.tracks_unlocked():
		return "all %d open (unlock tracks)" % n
	var open := Unlocks.open_count()
	if open >= n:
		return "all %d open" % n
	for id: String in Tracks.ids():
		if not Unlocks.is_open(id):
			return "%d of %d open; next: %s (%s on %s)" % [open, n, String(Tracks.def(id).get("name", id)), Unlocks.MEDAL,
				String(Tracks.def(Unlocks.previous(id)).get("name", ""))]
	return "%d of %d open" % [open, n]


## The medals the best times hold: {author, gold, silver, bronze: how many track-and-car pairs
## hold that medal as their best, tracks: how many tracks have a medal with any car}.
static func medal_counts() -> Dictionary:
	var out: Dictionary = {tracks = 0}
	for k: String in Medals.ORDER:
		out[k] = 0
	for tid: String in Tracks.ids():
		var t: BuiltTrack = Tracks.build(tid)
		var any := false
		for cid: String in Cars.ids():
			var rec: Dictionary = SaveData.get_record(tid, cid)
			if rec.is_empty():
				continue
			var medal := Medals.medal_for(Medals.medal_times(t, cid), float(rec.time))
			if medal != "":
				out[medal] = int(out[medal]) + 1
				any = true
		if any:
			out.tracks = int(out.tracks) + 1
	return out


## v6.14.0: the trophy cabinet, or one cup's place at one level (no pay).
func _cup(args: PackedStringArray, out: Out) -> void:
	if args.is_empty():
		var tro := SaveData.cup_trophies()
		for id: String in Cups.ids():
			var t: Dictionary = tro.get(id, {})
			var parts: PackedStringArray = []
			for lv: String in Opponents.ids():
				var p := int(t.get(lv, 0))
				if p > 0:
					parts.append("%s %s" % [Opponents.level_name(lv), Cups.trophy(p) if Cups.trophy(p) != "" else Field.place_name(p)])
			out.row(Cups.name_of(id), ", ".join(parts) if not parts.is_empty() else "-")
		out.add("info", "cup <cup> <level> <place> sets a place (1-3 win trophies, 0 takes it away); it pays nothing.")
		return
	if args.size() != 3:
		out.add("error", "cup: give a cup, a level and a place, e.g. cup rookie pro 1 (or cup on its own for the cabinet).")
		return
	var cid := args[0]
	if Cups.cup(cid).is_empty():
		out.add("error", "cup: there is no cup called %s. The cups: %s." % [_q(args[0]), ", ".join(Cups.ids())])
		return
	var lv := args[1]
	if Opponents.rank(lv) < 0:
		out.add("error", "cup: there is no level called %s. The levels: %s." % [_q(args[1]), ", ".join(Opponents.ids())])
		return
	var n: Variant = parse_amount(args[2])
	if n == null or int(n) < 0 or int(n) > Field.AI_COUNT + 1:
		out.add("error", "cup: the place is a whole number from 1 to %d (0 takes it away), not %s." % [Field.AI_COUNT + 1, _q(args[2])])
		return
	SaveData.set_cup_place(cid, lv, int(n))
	if int(n) == 0:
		out.add("ok", "%s at %s: no place now" % [Cups.name_of(cid), Opponents.level_name(lv)])
	else:
		var kind := Cups.trophy(int(n))
		out.add("ok", "%s at %s: %s%s (nothing paid)" % [Cups.name_of(cid), Opponents.level_name(lv), Field.place_name(int(n)), (", a %s trophy" % kind) if kind != "" else ""])
	out.changed = true


## The status row of the cups: how many trophies of how many.
static func cups_row() -> String:
	var tro := SaveData.cup_trophies()
	var won := 0
	for id: String in Cups.ids():
		for lv: String in Opponents.ids():
			if Cups.trophy(int((tro.get(id, {}) as Dictionary).get(lv, 0))) != "":
				won += 1
	return "%d of %d trophies (%d cups at %d levels)" % [won, Cups.ids().size() * Opponents.ids().size(), Cups.ids().size(), Opponents.ids().size()]


func _reset(args: PackedStringArray, out: Out) -> void:
	if args.size() == 1 and args[0] == "everything":
		_reset_everything(out)
		return
	if args.size() != 1 or args[0] != "career":
		out.add("error", "reset: try reset career (start the career over) or reset everything (back to a fresh install); both ask first.")
		return
	if not out.confirm("This starts the career over: money and points back to 0, only the Racer, and every medal and AI win pays again. Tracks opened by medals stay open; those only unlock tracks opened lock again. Best times, ghosts, AI networks and settings stay."):
		return
	SaveData.reset_career()
	var own: PackedStringArray = []
	for id: String in SaveData.owned_cars():
		own.append(_car_name(id))
	out.add("loss", "The career starts over: %s, %s pts, the %s." % [UiFormat.money(SaveData.get_money()), UiFormat.points(SaveData.get_points()),
		", ".join(own)])
	out.changed = true


## v6.17.0: reset everything (SaveData.reset_everything: a backup first, then a fresh install, the
## settings kept); `wiped` tells the app to drop what it holds from the old save.
func _reset_everything(out: Out) -> void:
	if not out.confirm("This puts the game back to a fresh install: money, points, cars (only the Racer, stock), upgrades, opened tracks (only Rookie Oval), paid rewards, trophies, the cup in progress, best times, medals, ghosts, scores, archived records and every AI network you trained all go. Your settings stay. A backup of the save file is written first."):
		return
	var r: Dictionary = SaveData.reset_everything()
	if not bool(r.ok):
		out.add("error", "reset everything: the backup could not be written (%s), so nothing was reset." % String(r.backup))
		return
	out.add("loss", "Everything is back to a fresh install: %s, %s pts, the Racer (stock), Rookie Oval open; no best times, medals, ghosts, scores, trophies or AI networks." % [
		UiFormat.money(SaveData.get_money()), UiFormat.points(SaveData.get_points())])
	out.add("info", "Kept: your settings (graphics, sound, display).")
	out.add("ok", "Backup of the old save: %s" % String(r.backup))
	if String(r.kept) != "":
		out.add("info", "The backup from before is kept as %s" % String(r.kept))
	out.add("info", "To undo it: close the game, then rename the backup to %s (replacing the new one)." % SaveData.path.get_file())
	out.changed = true
	wiped.emit()


func _clear(_args: PackedStringArray, out: Out) -> void:
	out.clear = true


func _exit(_args: PackedStringArray, out: Out) -> void:
	out.close = true
