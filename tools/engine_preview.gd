extends SceneTree
## engine_preview.gd (v6.12.0): renders each car's engine (audio/engine_voice.gd) to WAV files and
## measures it.
## ------------------------------------------------------------------
##   godot --headless --path . --script res://tools/engine_preview.gd -- [cars=racer,thunder] \
##       [out=/tmp/engines] [track=rookie-oval] [seconds=30] [rate=32000]
## For each car:
##   <car>_sweep.wav  idle, a free rev to the limiter, a second on the limiter, a lift (crackles)
##   <car>_drive.wav  the medal autopilot (with nitro) on the track from the start: the sim's own
##                    rpm, gear changes, braking and nitro, fed to the voice once per physics step
##   <car>_drive.csv  step, rpm, gear, load, boost, limiter (the analysis script reads it)
## Prints per car: the level at full load (RMS and peak, dBFS), the firing frequency the output
## carries at 3000 and 6000 rpm (Goertzel, against the expected rpm / 120 × cylinders) and the
## render cost (µs per sample).

var opts := {}


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out := str(opts.get("out", "/tmp/engines"))
	DirAccess.make_dir_recursive_absolute(out)
	var cars: PackedStringArray = str(opts.get("cars", ",".join(Cars.ids()))).split(",")
	var rate := float(opts.get("rate", "32000"))
	var secs := float(opts.get("seconds", "30"))
	var tid := str(opts.get("track", "rookie-oval"))
	for c in cars:
		_sweep(c, rate, out)
		_drive(c, rate, out, tid, secs)
		_measure(c, rate)
	quit()


func _sweep(id: String, rate: float, out: String) -> void:
	var v := EngineVoice.new(id, rate)
	var sp := Cars.spec(id)
	var buf := PackedFloat32Array()
	var blk := int(rate / 60.0)
	var t := 0.0
	var total := 7.0
	while t < total:
		var r: float
		var ld := 0.0
		var lim := false
		if t < 1.2:
			r = sp.idle_rpm
		elif t < 4.2:
			ld = 1.0
			r = sp.idle_rpm + (sp.redline - sp.idle_rpm) * pow((t - 1.2) / 3.0, 0.8)
		elif t < 5.2:
			ld = 1.0
			r = sp.redline
			lim = true
		else:
			r = sp.idle_rpm + (sp.redline - sp.idle_rpm) * exp(-(t - 5.2) * 2.2)
		v.rpm = r
		v.load = ld
		v.throttle = ld
		v.limiter = lim
		buf.append_array(v.render_mono(blk))
		t += blk / rate
	_save_wav("%s/%s_sweep.wav" % [out, id], buf, rate)


func _drive(id: String, rate: float, out: String, tid: String, secs: float) -> void:
	var tr := Tracks.build(tid)
	var spec := Cars.spec(id)
	var car := Car.new(tr, tr.start_idx, spec)
	var pilot := Autopilot.medal(tr, 20.0, 0.75, true, Autopilot.DECEL, spec)
	var v := EngineVoice.new(id, rate)
	var buf := PackedFloat32Array()
	var csv := PackedStringArray(["step,rpm,gear,load,boost,limiter,speed"])
	var acc := 0.0
	var steps := int(secs * 60.0)
	var idle_steps := 60 # a second standing at idle first
	var coast := Car.Controls.new()
	var usec := 0
	for s in steps + idle_steps:
		var c: Car.Controls = coast if s < idle_steps else pilot.drive(car)
		car.step(tr, c, 1.0 / 60.0)
		v.follow(car)
		acc += rate / 60.0
		var n := int(acc)
		acc -= n
		var t0 := Time.get_ticks_usec()
		buf.append_array(v.render_mono(n))
		usec += Time.get_ticks_usec() - t0
		csv.append("%d,%.1f,%d,%.3f,%.3f,%d,%.2f" % [s, car.rpm, car.gear, v.load, v.boost, 1 if v.limiter else 0, car.speed])
	_save_wav("%s/%s_drive.wav" % [out, id], buf, rate)
	var f := FileAccess.open("%s/%s_drive.csv" % [out, id], FileAccess.WRITE)
	f.store_string("\n".join(csv) + "\n")
	f.close()
	print("%s drive: %d samples, %.3f us a sample (%.3f ms a 60 Hz frame)" % [id, buf.size(), float(usec) / buf.size(), float(usec) / buf.size() * rate / 60.0 / 1000.0])


func _measure(id: String, rate: float) -> void:
	var ch := EngineVoice.of(id)
	var cyl := int(ch.cylinders)
	var sp := Cars.spec(id)
	var line := "%s (%s, %d cyl): RMS / peak dBFS" % [id, ch.name, cyl]
	for st: Array in [["idle", sp.idle_rpm, 0.0, 0.0], ["3000 on", 3000.0, 1.0, 0.0], ["6000 on", 6000.0, 1.0, 0.0], ["6000 off", 6000.0, 0.0, 0.0],
			["6000 nitro", 6000.0, 1.0, 1.0], ["redline", sp.redline * 0.97, 1.0, 0.0]]:
		var v := EngineVoice.new(id, rate)
		v.rpm = st[1]
		v.load = st[2]
		v.throttle = st[2]
		v.boost = st[3]
		v.render_mono(int(rate * 0.3))
		v.load = st[2] # (no lift: no crackles)
		var s := v.render_mono(int(rate * 0.5))
		var rms := 0.0
		var pk := 0.0
		for x in s:
			rms += x * x
			pk = maxf(pk, absf(x))
		rms = sqrt(rms / s.size())
		line += "  %s %.1f / %.1f" % [st[0], linear_to_db(rms), linear_to_db(pk)]
		if st[0] == "6000 on" or st[0] == "3000 on":
			var f := EngineVoice.firing_hz(cyl, float(st[1]))
			var p_f := goertzel(s, f, rate)
			var p_n := 0.5 * (goertzel(s, f * 0.75, rate) + goertzel(s, f * 1.25, rate))
			line += " (firing %.0f Hz +%.0f dB)" % [f, 10.0 * log(p_f / maxf(1e-12, p_n)) / log(10.0)]
	print(line)


## Power of `s` at frequency `f` (Goertzel).
static func goertzel(s: PackedFloat32Array, f: float, rate: float) -> float:
	var w := TAU * f / rate
	var c := 2.0 * cos(w)
	var s1 := 0.0
	var s2 := 0.0
	for x in s:
		var s0 := x + c * s1 - s2
		s2 = s1
		s1 = s0
	return (s1 * s1 + s2 * s2 - c * s1 * s2) / (s.size() * s.size())


static func _save_wav(path: String, buf: PackedFloat32Array, rate: float) -> void:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, clampi(roundi(buf[i] * 32767.0), -32768, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(rate)
	w.stereo = false
	w.data = data
	w.save_to_wav(path)
