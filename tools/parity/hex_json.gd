class_name HexJson
extends RefCounted
## Exact number transfer between Godot and node for the parity tools (see hexjson.mjs):
## Godot's JSON parser is not correctly rounded for 17-digit numbers, so non-integer
## numbers travel as "#<16 hex digits>" holding their IEEE-754 bits.


static func to_hex(v: float) -> String:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_double(0, v)
	var s: String = "#"
	for k in range(7, -1, -1):
		s += "%02x" % b[k]
	return s


static func from_hex(s: String) -> float:
	var b := PackedByteArray()
	b.resize(8)
	for k in 8:
		b[7 - k] = s.substr(1 + k * 2, 2).hex_to_int()
	return b.decode_double(0)


## Turns every "#hex" string inside v (arrays and dictionaries, recursively) into a float.
static func decode(v: Variant) -> Variant:
	if v is String:
		var s: String = v
		if s.length() == 17 and s.begins_with("#"):
			return from_hex(s)
		return s
	if v is Array:
		var out: Array = []
		for x: Variant in v:
			out.append(decode(x))
		return out
	if v is Dictionary:
		var out: Dictionary = {}
		var d: Dictionary = v
		for k: Variant in d:
			out[k] = decode(d[k])
		return out
	return v


## The reverse: non-integer floats (also inside packed float arrays) become "#hex" strings.
static func encode(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			if f == floorf(f) and absf(f) < 9.0e15:
				return int(f)
			return to_hex(f)
		TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT32_ARRAY:
			var out: Array = []
			for x: Variant in v:
				out.append(encode(x))
			return out
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			var d: Dictionary = v
			for k: Variant in d:
				out[k] = encode(d[k])
			return out
	return v


static func read(path: String) -> Variant:
	return decode(JSON.parse_string(FileAccess.get_file_as_string(path)))


static func write(path: String, v: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(encode(v)))
	f.close()
