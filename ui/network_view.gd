class_name NetworkView
extends Control
## network_view.gd
## ------------------------------------------------------------------
## Live diagram of a neural network (web/src/ui/networkView.js):
##   - nodes in columns, one per layer, labelled on the input / output side
##   - connections blue (positive) / red (negative), thicker = stronger, brighter when the
##     signal flowing through them is strong
##   - nodes glow warm (positive) or cool (negative) with their activation
## draw_net(net) with net = {sizes: [18, 12, 2], weights: [per layer: o * n_in + i],
## acts: [per layer: activations]} (the AI's network after its last step). Labels come from
## UiData.network_labels().

var net: Dictionary = {}
var _labels: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


## Draw `n` (see the header) on the next frame.
func draw_net(n: Dictionary) -> void:
	net = n
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if net.is_empty() or w < 10:
		return
	if _labels.is_empty():
		_labels = UiData.network_labels()
	var inputs: Array = _labels.get("inputs", [])
	var outputs: Array = _labels.get("outputs", [])
	var sizes: Array = net.sizes
	var top := 14.0
	var bottom := 14.0
	# input labels: smaller type when the rows are close (a short panel), and only every other
	# label when even that would overprint
	var row_in := minf(26.0, (h - top - bottom) / maxf(1, sizes[0]))
	var in_size := int(clampf(roundf(row_in), 8, 12))
	var every_other := row_in < 7
	var f := UiStyle.face("text")
	var label_w := 0.0
	for l in inputs:
		label_w = maxf(label_w, f.get_string_size("%s -0.00" % l, HORIZONTAL_ALIGNMENT_LEFT, -1, in_size).x)
	var left := label_w + 18.0
	var right := 80.0
	var n_layers := sizes.size()
	var xs: Array[float] = []
	var ys: Array = []
	var max_n := 1
	for l in n_layers:
		xs.append(left + (w - left - right) * l / maxf(1, n_layers - 1))
		var n: int = sizes[l]
		max_n = maxi(max_n, n)
		var g := minf(26.0, (h - top - bottom) / maxf(1, n))
		var total := g * (n - 1)
		var col: Array[float] = []
		for i in n:
			col.append(h / 2.0 - total / 2.0 + i * g)
		ys.append(col)
	var r := clampf((h - top - bottom) / max_n * 0.36, 3.0, 8.0)
	# connections
	for l in n_layers - 1:
		var wts: Variant = net.weights[l]
		var n_in: int = sizes[l]
		var src: Variant = net.acts[l]
		for o in sizes[l + 1]:
			for i in n_in:
				var wt: float = wts[o * n_in + i]
				var mag := minf(1.0, absf(wt) / 2.0)
				var flow := 0.25 + 0.75 * minf(1.0, absf(float(src[i]) * wt))
				var a := 0.08 + 0.6 * mag * flow
				var c := Color(70 / 255.0, 160 / 255.0, 1.0, a) if wt >= 0 else Color(1.0, 85 / 255.0, 85 / 255.0, a)
				draw_line(Vector2(xs[l], ys[l][i]), Vector2(xs[l + 1], ys[l + 1][o]), c, 0.3 + 2.6 * mag, true)
	# nodes
	for l in n_layers:
		for i in sizes[l]:
			var a: float = net.acts[l][i]
			var p := Vector2(xs[l], ys[l][i])
			draw_circle(p, r, _activation_color(a), true, -1.0, true)
			draw_arc(p, r, 0, TAU, 24, Color(1, 1, 1, 0.75), 1.0, true)
			if l == 0:
				if every_other and i % 2 == 1:
					continue
				var t := "%s %.2f" % [inputs[i] if i < inputs.size() else "in %d" % i, a]
				var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, in_size).x
				draw_string(f, Vector2(p.x - r - 4 - tw, p.y + in_size * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, in_size, UiStyle.TEXT_2)
			elif l == n_layers - 1:
				var nm: String = outputs[i] if i < outputs.size() else "out %d" % i
				var hint := ""
				if i == 0:
					hint = " left" if a > 0.05 else " right" if a < -0.05 else ""
				else:
					hint = " brake" if a < 0 else " gas"
				draw_string(f, Vector2(p.x + r + 5, p.y - 7 + 4), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiStyle.TEXT)
				draw_string(f, Vector2(p.x + r + 5, p.y + 7 + 4), "%.2f%s" % [a, hint], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiStyle.TEXT_2)


static func _activation_color(a: float) -> Color:
	var t := minf(1.0, absf(a))
	var base := Color8(37, 39, 44)
	var hot := Color8(255, 196, 61) if a >= 0 else Color8(92, 170, 255)
	return base.lerp(hot, t)
