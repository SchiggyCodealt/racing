class_name BuiltTrack
extends RefCounted
## built_track.gd
## ------------------------------------------------------------------
## A built track: what TrackBuilder.build_track(def) makes from a track
## definition (data/tracks.json, the same data as web/src/tracks/trackData.js).
## The same fields as the JS built track (trackBuilder.js), in snake_case:
##
##   def          the definition it was built from (Dictionary, JSON data)
##   id, name     from the definition
##   theme        def.theme or "meadow"
##   closed       true for circuits, false for sprints
##   laps         circuits: def.laps (default 3); sprints: 1
##   N            segments along the spline (closed: count == N)
##   count        centre-line samples (sprints: N + 1)
##   seg_len      metres between samples (~2)
##   length       plan length of the centre line (m)
##   seg_count    segments between samples (closed: N, open: count - 1)
##   px, py, pz   sample positions (py = road height on the centre line)
##   tx, tz       unit tangent; nx, nz unit LEFT normal (= (tz, -tx))
##   hw           road half width (m); bank: signed bank angle (rad, + = left turn)
##   cp_samples   samples of the checkpoint gates, in order
##   start_idx    sample the cars start on; start_line: sample of the START line
##   finish_idx   sample of the finish line (circuits: 0)
##   kickers      [{foot, lip, land, height}] sample indices and lip height (m)
##   grid         wall segments and their grid (Collision.WallGrid)
##
## The per-sample arrays are PackedFloat32Array like the JS Float32Arrays, so
## every value is exactly the JS value (float32), read as a 64-bit float.

var def: Dictionary = {}
var id: String = ""
var name: String = ""
var theme: String = "meadow"
var closed: bool = true
var laps: int = 3
var N: int = 0
var count: int = 0
var seg_len: float = 0.0
var length: float = 0.0
var seg_count: int = 0
var px: PackedFloat32Array = PackedFloat32Array()
var py: PackedFloat32Array = PackedFloat32Array()
var pz: PackedFloat32Array = PackedFloat32Array()
var tx: PackedFloat32Array = PackedFloat32Array()
var tz: PackedFloat32Array = PackedFloat32Array()
var nx: PackedFloat32Array = PackedFloat32Array()
var nz: PackedFloat32Array = PackedFloat32Array()
var hw: PackedFloat32Array = PackedFloat32Array()
var bank: PackedFloat32Array = PackedFloat32Array()
var cp_samples: PackedInt32Array = PackedInt32Array()
var start_idx: int = 0
var finish_idx: int = 0
var start_line: int = 0
var kickers: Array[Dictionary] = []
var grid: Collision.WallGrid = null
## gates per lap count (TrackBuilder.get_gates)
var gate_cache: Dictionary = {}
## per-sample physics data, made by CarPhysics.track_phys on first use: slope and smoothed vertical curvature
var phys_slope: PackedFloat32Array = PackedFloat32Array()
var phys_kv: PackedFloat32Array = PackedFloat32Array()


## Sample index wrapped round a circuit / clamped to the ends of a sprint.
func wrap(i: int) -> int:
	if closed:
		return posmod(i, N)
	return clampi(i, 0, count - 1)


## Heading (yaw) of the road at sample i: forward = (sin yaw, cos yaw).
func heading(i: int) -> float:
	return atan2(tx[i], tz[i])


## Race distance in metres for `laps` laps (TrackBuilder.race_length).
func race_length(n_laps: int = -1) -> float:
	return TrackBuilder.race_length(self, laps if n_laps < 0 else n_laps)


## Short fingerprint of the layout ("count:length"), as ghosts and medals use it.
func signature() -> String:
	return "%d:%d" % [count, JsMath.roundi(length)]
