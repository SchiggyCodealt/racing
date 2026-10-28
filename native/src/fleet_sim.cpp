// fleet_sim.cpp
// ------------------------------------------------------------------
// FleetSim (see fleet_sim.h): sensors, network, race gates, fitness and the
// elimination rules for a whole population, mirroring ai/sensors.gd,
// ai/network.gd and Trainer.step() in ai/trainer.gd; car physics in car_sim.cpp.
//
// Threads: the cars are independent within a step, except for the "cut off"
// rule, which needs the time of the first finish. Each thread steps its cars
// (every T-th car) through a chunk of up to CHUNK steps, then the threads'
// findings are merged (first finish, deaths, wall count, best times). A
// thread sees its own cars' finishes at once and the others' at the next
// chunk; that changes nothing, because a car can only be cut off
// finish_cutoff × first finish + finish_slack (>= 5 s) after the first finish
// while a chunk lasts 1 s. So every thread count gives the same results.
#include "fleet_sim.h"
#include "car_sim.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>

#include <algorithm>
#include <thread>

using namespace godot;

namespace trackrush {

namespace {

constexpr double PI = 3.14159265358979323846;
// ai/sensors.gd constants
constexpr int NR = 9;
constexpr int INPUT_COUNT = 18;
constexpr double SENSOR_ANGLES[NR] = { 90, 60, 35, 15, 0, -15, -35, -60, -90 };
constexpr double SENSOR_RANGE = 100.0;
constexpr double AIM_BASE = 10.0, AIM_TIME = 0.6, AIM_FAR = 2.5;
constexpr double TURN_FROM = 25.0, TURN_TO = 60.0, TURN_SCALE = 1.6;
constexpr double CORNER_WINDOWS[3][2] = { { 0, 50 }, { 50, 110 }, { 110, 200 } };
constexpr double CORNER_GRIP = 14.5, MARGIN_SCALE = 20.0;
constexpr int MIRROR_NEGATE[5] = { NR + 1, NR + 2, NR + 3, NR + 4, NR + 5 };
// steps per thread chunk (must stay well under 5 s of steps, see the header)
constexpr int CHUNK = 60;
// fewer car-steps than this in a chunk: one thread (starting threads costs more)
constexpr int MIN_PARALLEL = 400;
// get_view_states(): numbers per car
constexpr int VIEW_STRIDE = 35;

const char *REASON_NAMES[8] = { "", "finished", "wall", "backwards", "stalled", "too slow", "cut off", "time" };

inline int posmod(int a, int b) {
	int v = a % b;
	if ((v < 0 && b > 0) || (v > 0 && b < 0)) {
		v += b;
	}
	return v;
}
inline double maxf(double a, double b) { return a > b ? a : b; }
inline double minf(double a, double b) { return a < b ? a : b; }
// Sensors.clamp1
inline double clamp1(double v) { return v > 1.0 ? 1.0 : (v < -1.0 ? -1.0 : v); }
// JsMath.roundi: JS Math.round (halves up)
inline int js_roundi(double x) {
	double f = std::floor(x);
	return (int)(x - f >= 0.5 ? f + 1.0 : f);
}

// Sensors.heading_at: unwrapped road heading at a fractional sample position s.
double heading_at(const Track &h, double s) {
	const std::vector<double> &theta = h.head_theta;
	int n = h.head_n;
	if (h.closed) {
		double lap = std::floor(s / n);
		double r = s - lap * n;
		int i = std::min(n - 1, (int)std::floor(r));
		double t = r - i;
		double a = theta[i];
		double b = i + 1 < n ? theta[i + 1] : theta[0] + h.head_total;
		return a + (b - a) * t + lap * h.head_total;
	}
	if (s <= 0.0) {
		return theta[0];
	}
	if (s >= n - 1) {
		return theta[n - 1];
	}
	int i2 = (int)std::floor(s);
	double t2 = s - i2;
	return theta[i2] + (theta[i2 + 1] - theta[i2]) * t2;
}

// Sensors.sharpest: largest road curvature between samples l and r (range-maximum table).
double sharpest(const Track &h, int l, int r) {
	if (h.closed) {
		int span = std::min(r - l, h.head_n - 1);
		l = posmod(l, h.head_n);
		r = l + span;
	} else {
		if (l < 0) {
			l = 0;
		}
		if (r > h.head_len - 1) {
			r = h.head_len - 1;
		}
		if (r < l) {
			return 0.0;
		}
	}
	int k = 0;
	int v = r - l + 1;
	while (v > 1) {
		v >>= 1;
		k += 1;
	}
	const std::vector<double> &t = h.head_sparse[k];
	double a = t[l];
	double b = t[r - (1 << k) + 1];
	return a > b ? a : b;
}

// Sensors.bearing: angle (+ = left) from the car's heading to the centre line at sample s.
double bearing(const Track &track, const CarState &car, double s, double fx, double fz) {
	int i;
	double t;
	if (track.closed) {
		int n = track.N;
		s = std::fmod(std::fmod(s, n) + n, n); // Sensors.fposmod_js
		i = std::min(n - 1, (int)std::floor(s));
		t = s - i;
	} else if (s >= track.count - 1) {
		i = track.count - 2;
		t = 1.0;
	} else if (s <= 0.0) {
		i = 0;
		t = 0.0;
	} else {
		i = (int)std::floor(s);
		t = s - i;
	}
	int j = track.closed ? (i + 1) % track.N : i + 1;
	double x = track.px[i] + (track.px[j] - track.px[i]) * t - car.x;
	double z = track.pz[i] + (track.pz[j] - track.pz[i]) * t - car.z;
	return std::atan2(x * fz - z * fx, x * fx + z * fz);
}

// --- Dictionary readers -----------------------------------------------------------------

double num(const Dictionary &d, const char *key, double fallback) {
	Variant v = d.get(key, fallback);
	return (double)v;
}

std::vector<double> doubles(const Variant &v) {
	std::vector<double> out;
	if (v.get_type() == Variant::PACKED_FLOAT32_ARRAY) {
		PackedFloat32Array a = v;
		out.resize(a.size());
		for (int64_t k = 0; k < a.size(); k++) {
			out[k] = (double)a[k]; // exact: float32 -> double
		}
	} else if (v.get_type() == Variant::PACKED_FLOAT64_ARRAY) {
		PackedFloat64Array a = v;
		out.assign(a.ptr(), a.ptr() + a.size());
	} else if (v.get_type() == Variant::ARRAY) {
		Array a = v;
		out.resize(a.size());
		for (int64_t k = 0; k < a.size(); k++) {
			out[k] = (double)a[k];
		}
	}
	return out;
}

std::vector<int32_t> ints(const Variant &v) {
	std::vector<int32_t> out;
	if (v.get_type() == Variant::PACKED_INT32_ARRAY) {
		PackedInt32Array a = v;
		out.assign(a.ptr(), a.ptr() + a.size());
	} else if (v.get_type() == Variant::ARRAY) {
		Array a = v;
		out.resize(a.size());
		for (int64_t k = 0; k < a.size(); k++) {
			out[k] = (int32_t)(int64_t)a[k];
		}
	}
	return out;
}

} // namespace

FleetSim::FleetSim() {
	for (int k = 0; k < NR; k++) {
		double r = (SENSOR_ANGLES[k] * PI) / 180.0;
		ray_cos[k] = std::cos(r);
		ray_sin[k] = std::sin(r);
	}
}

// ---- setup -------------------------------------------------------------------------------

// Trainer.spec_data(): the CarSpec fields with their JS names + the derived constants.
void FleetSim::set_spec(const Dictionary &d) {
	Spec &s = spec;
#define SPEC(field, key) s.field = num(d, key, s.field)
	SPEC(mass, "mass"); SPEC(inertia, "inertia"); SPEC(cg_to_front, "cgToFront"); SPEC(cg_to_rear, "cgToRear");
	SPEC(cg_height, "cgHeight"); SPEC(wheel_radius, "wheelRadius");
	SPEC(mu, "mu"); SPEC(handbrake, "handbrake"); SPEC(handbrake_fast, "handbrakeFast"); SPEC(handbrake_rate, "handbrakeRate");
	SPEC(load_sensitivity, "loadSensitivity"); SPEC(pac_b, "pacB"); SPEC(pac_c, "pacC"); SPEC(pac_e, "pacE");
	SPEC(drag, "drag"); SPEC(downforce, "downforce"); SPEC(aero_front, "aeroFront"); SPEC(roll_resist, "rollResist");
	SPEC(idle_rpm, "idleRpm"); SPEC(redline, "redline"); SPEC(upshift_rpm, "upshiftRpm"); SPEC(downshift_rpm, "downshiftRpm");
	SPEC(launch_rpm, "launchRpm"); SPEC(final_drive, "finalDrive"); SPEC(reverse_ratio, "reverseRatio");
	SPEC(efficiency, "efficiency"); SPEC(shift_time, "shiftTime"); SPEC(drive_front, "driveFront"); SPEC(slide_drive, "slideDrive");
	SPEC(max_reverse, "maxReverse"); SPEC(brake_force, "brakeForce"); SPEC(brake_front, "brakeFront");
	SPEC(steer_lock, "steerLock"); SPEC(steer_rate, "steerRate"); SPEC(steer_ref_accel, "steerRefAccel");
	SPEC(steer_slip_gain, "steerSlipGain"); SPEC(steer_extra_fast, "steerExtraFast"); SPEC(steer_slow_speed, "steerSlowSpeed");
	SPEC(steer_fast_speed, "steerFastSpeed"); SPEC(steer_assist, "steerAssist"); SPEC(assist_from, "assistFrom");
	SPEC(assist_full, "assistFull");
	SPEC(esc, "esc"); SPEC(esc_gain, "escGain"); SPEC(esc_moment, "escMoment"); SPEC(esc_under, "escUnder");
	SPEC(esc_deadband, "escDeadband"); SPEC(esc_slow, "escSlow"); SPEC(esc_from, "escFrom"); SPEC(esc_handbrake_hold, "escHandbrakeHold");
	SPEC(radius, "radius"); SPEC(half_length, "halfLength"); SPEC(wall_restitution, "wallRestitution"); SPEC(max_rebound, "maxRebound");
	SPEC(wall_friction, "wallFriction"); SPEC(wall_crush, "wallCrush"); SPEC(wall_slide, "wallSlide"); SPEC(wall_rub, "wallRub");
	SPEC(wall_rub_build, "wallRubBuild"); SPEC(wall_align, "wallAlign"); SPEC(wall_align_gain, "wallAlignGain");
	SPEC(wall_align_accel, "wallAlignAccel"); SPEC(wall_yaw_stop, "wallYawStop"); SPEC(wall_latch, "wallLatch");
	SPEC(wall_latch_steps, "wallLatchSteps"); SPEC(wall_height, "wallHeight");
	SPEC(gravity, "gravity"); SPEC(lift_separation, "liftSeparation"); SPEC(min_flight, "minFlight"); SPEC(hard_landing, "hardLanding");
	SPEC(landing_loss, "landingLoss"); SPEC(air_steer, "airSteer"); SPEC(air_steer_tau, "airSteerTau"); SPEC(air_yaw_damp, "airYawDamp");
	SPEC(nitro_time, "nitroTime"); SPEC(nitro_force, "nitroForce"); SPEC(nitro_power, "nitroPower"); SPEC(nitro_top, "nitroTop");
	SPEC(nitro_fade, "nitroFade"); SPEC(max_speed, "maxSpeed");
	SPEC(wheelbase, "wheelbase"); SPEC(core, "core"); SPEC(peak_slip, "peakSlip"); SPEC(pac_slope0, "pacSlope0");
	SPEC(peak_steer, "peakSteer");
#undef SPEC
	s.substeps = (int)num(d, "substeps", s.substeps);
	if (s.substeps < 1) {
		s.substeps = 1;
	}
	s.gears = doubles(d.get("gears", Variant()));
	s.torque_rpm = doubles(d.get("torqueRpm", Variant()));
	s.torque_nm = doubles(d.get("torqueNm", Variant()));
	have_spec = !s.gears.empty() && !s.torque_rpm.empty() && s.torque_rpm.size() == s.torque_nm.size();
	run_over = true;
}

// Trainer.track_data(): the built track with every table the GDScript computed.
void FleetSim::set_track(const Dictionary &d) {
	Track &t = track;
	t.closed = (bool)d.get("closed", true);
	t.N = (int)(int64_t)d.get("N", 0);
	t.count = (int)(int64_t)d.get("count", 0);
	t.seg_count = (int)(int64_t)d.get("seg_count", 0);
	t.start_idx = (int)(int64_t)d.get("start_idx", 0);
	t.finish_idx = (int)(int64_t)d.get("finish_idx", 0);
	t.seg_len = num(d, "seg_len", 2.0);
	t.length = num(d, "length", 0.0);
	t.px = doubles(d.get("px", Variant()));
	t.py = doubles(d.get("py", Variant()));
	t.pz = doubles(d.get("pz", Variant()));
	t.tx = doubles(d.get("tx", Variant()));
	t.tz = doubles(d.get("tz", Variant()));
	t.nx = doubles(d.get("nx", Variant()));
	t.nz = doubles(d.get("nz", Variant()));
	t.hw = doubles(d.get("hw", Variant()));
	t.bank = doubles(d.get("bank", Variant()));
	t.phys_slope = doubles(d.get("phys_slope", Variant()));
	t.phys_kv = doubles(d.get("phys_kv", Variant()));
	t.cell = num(d, "grid_cell", 12.0);
	t.min_x = num(d, "grid_min_x", 0.0);
	t.min_z = num(d, "grid_min_z", 0.0);
	t.cols = (int)(int64_t)d.get("grid_cols", 0);
	t.rows = (int)(int64_t)d.get("grid_rows", 0);
	t.seg_d = doubles(d.get("grid_seg_d", Variant()));
	t.inward = doubles(d.get("grid_inward", Variant()));
	t.cell_start = ints(d.get("grid_cell_start", Variant()));
	t.cell_segs = ints(d.get("grid_cell_segs", Variant()));
	t.seg_cell = ints(d.get("grid_seg_cell", Variant()));
	t.gate_prog = doubles(d.get("gate_prog", Variant()));
	t.gate_kind = ints(d.get("gate_kind", Variant()));
	t.race_len = num(d, "race_len", 0.0);
	t.head_theta = doubles(d.get("head_theta", Variant()));
	t.head_total = num(d, "head_total", 0.0);
	t.head_n = (int)(int64_t)d.get("head_n", 0);
	t.head_len = (int)(int64_t)d.get("head_len", 0);
	t.head_sparse.clear();
	Array sparse = d.get("head_sparse", Array());
	for (int64_t k = 0; k < sparse.size(); k++) {
		t.head_sparse.push_back(doubles(sparse[k]));
	}
	const size_t n = (size_t)t.count;
	have_track = n >= 2 && t.px.size() == n && t.pz.size() == n && t.py.size() == n && t.nx.size() == n && t.nz.size() == n &&
			t.hw.size() == n && t.bank.size() == n && t.tx.size() == n && t.tz.size() == n && t.phys_slope.size() == n &&
			t.phys_kv.size() == n && !t.gate_prog.empty() && t.gate_prog.size() == t.gate_kind.size() &&
			(int)t.cell_start.size() == t.cols * t.rows + 1 && !t.head_theta.empty() && !t.head_sparse.empty();
	run_over = true;
}

void FleetSim::set_rules(const Dictionary &d) {
	Rules &r = rules;
	r.stall_time = num(d, "stall_time", r.stall_time);
	r.backwards = num(d, "backwards", r.backwards);
	r.min_pace = num(d, "min_pace", r.min_pace);
	r.gate_slack = num(d, "gate_slack", r.gate_slack);
	r.time_slack = num(d, "time_slack", r.time_slack);
	r.finish_cutoff = num(d, "finish_cutoff", r.finish_cutoff);
	r.finish_slack = num(d, "finish_slack", r.finish_slack);
	r.ref_speed = num(d, "ref_speed", r.ref_speed);
	r.walls_crash = (bool)d.get("walls_crash", false);
	r.laps = (int)(int64_t)d.get("laps", 1);
	r.speed_scale = num(d, "speed_scale", r.speed_scale);
}

// The networks of the population: layer sizes and every network's weights and biases,
// one after the other (NeuralNetwork.params() layout: per layer the weights, then the biases).
void FleetSim::set_networks(const PackedInt32Array &p_sizes, const PackedFloat32Array &p_params, int count) {
	sizes.assign(p_sizes.ptr(), p_sizes.ptr() + p_sizes.size());
	per_net = 0;
	act_count = 0;
	for (size_t l = 0; l < sizes.size(); l++) {
		act_count += sizes[l];
		if (l + 1 < sizes.size()) {
			per_net += sizes[l] * sizes[l + 1] + sizes[l + 1];
		}
	}
	bool ok = sizes.size() >= 2 && sizes[0] == INPUT_COUNT && sizes.back() == 2 && count >= 0 &&
			(int64_t)per_net * count == p_params.size();
	if (!ok) {
		ERR_PRINT("FleetSim.set_networks: sizes or parameter count do not match");
		net_count = 0;
		params.clear();
		run_over = true;
		return;
	}
	params.assign(p_params.ptr(), p_params.ptr() + p_params.size());
	net_count = count;
	run_over = true;
}

void FleetSim::set_threads(int n) {
	threads = std::max(1, std::min(64, n));
}

int FleetSim::get_threads() const {
	return threads;
}

// ---- a track run ------------------------------------------------------------------------------

// Trainer.begin_track_run(): every car on the start line, the run's limits.
void FleetSim::begin_run() {
	agents.clear();
	run_over = true;
	if (!have_spec || !have_track || net_count <= 0) {
		ERR_PRINT("FleetSim.begin_run: set_spec, set_track and set_networks first");
		return;
	}
	race_len = track.race_len;
	ref_time = race_len / rules.ref_speed;
	time_limit = race_len / rules.min_pace + rules.time_slack;
	sim_time = 0.0;
	first_finish = INFINITY;
	std::fill(std::begin(deaths), std::end(deaths), 0);
	wall_cars = 0;
	best_lap = INFINITY;
	best_finish = INFINITY;
	agents.resize(net_count);
	for (int k = 0; k < net_count; k++) {
		Agent &a = agents[k];
		car_init(a.car, spec, track, track.start_idx);
		a.prev_x = a.car.x;
		a.prev_y = a.car.y;
		a.prev_z = a.car.z;
		a.prev_yaw = a.car.yaw;
		a.start_prog = a.car.prog;
		a.max_prog = a.car.prog;
		a.acts.assign(act_count, 0.0f);
		a.gate_deadline = gate_deadline_for(a, a.start_prog, 0.0);
	}
	run_over = false;
}

// Trainer.gate_deadline()
double FleetSim::gate_deadline_for(const Agent &a, double from_prog, double now) const {
	const int n = (int)track.gate_prog.size();
	double g = track.gate_prog[std::min(a.next_gate, n - 1)];
	double metres = maxf(0.0, (g - from_prog) * track.seg_len);
	return now + metres / rules.min_pace + rules.gate_slack;
}

// Trainer.score()
double FleetSim::score(const Agent &a, double now) const {
	double metres = maxf(0.0, (maxf(a.car.prog, a.max_prog - 3.0) - a.start_prog) * track.seg_len);
	double frac = minf(1.0, metres / race_len);
	double f = 1000.0 * frac + (200.0 * a.next_gate) / (int)track.gate_prog.size();
	if (a.race_finished) {
		f += 500.0 * minf(1.5, ref_time / a.finish_time);
	} else if (now > 1.0) {
		f += 50.0 * minf(1.0, metres / now / rules.ref_speed);
	}
	return f;
}

// Sensors.sense(): the 18 inputs (32-bit floats) and the ray distances.
void FleetSim::sense(Agent &a) const {
	const CarState &car = a.car;
	float *inputs = a.inputs;
	double fx = std::sin(car.yaw);
	double fz = std::cos(car.yaw);
	double lx = fz;
	double lz = -fx;
	double ox = car.x + fx * 1.5;
	double oz = car.z + fz * 1.5;
	for (int k = 0; k < NR; k++) {
		double c = ray_cos[k];
		double s = ray_sin[k];
		double d = raycast(track, ox, oz, fx * c + lx * s, fz * c + lz * s, SENSOR_RANGE);
		inputs[k] = (float)(d / SENSOR_RANGE);
		a.rays[k] = (float)d;
	}
	double u = car.forward_speed;
	inputs[NR] = (float)(u / rules.speed_scale);
	inputs[NR + 1] = (float)clamp1(car.side_speed / 8.0); // side_speed: + = moving to the car's left
	inputs[NR + 2] = (float)clamp1(car.yaw_rate / 1.5);

	// Where the road goes, and how fast the next corners can be taken.
	double s0 = track.closed ? car.prog - car.laps * track.N : car.prog; // progress within the lap, samples
	double inv = 1.0 / track.seg_len;
	double L = (AIM_BASE + AIM_TIME * (u > 0.0 ? u : 0.0)) * inv;
	inputs[NR + 3] = (float)clamp1(bearing(track, car, s0 + L, fx, fz) / (PI / 2.0));
	inputs[NR + 4] = (float)clamp1(bearing(track, car, s0 + AIM_FAR * L, fx, fz) / PI);
	double turn = heading_at(track, s0 + TURN_TO * inv) - heading_at(track, s0 + TURN_FROM * inv);
	inputs[NR + 5] = (float)std::tanh(turn / TURN_SCALE);
	int i0 = js_roundi(s0);
	for (int w = 0; w < 3; w++) {
		double kappa = sharpest(track, i0 + js_roundi(CORNER_WINDOWS[w][0] * inv), i0 + js_roundi(CORNER_WINDOWS[w][1] * inv));
		double vc = kappa > 1e-6 ? std::sqrt(CORNER_GRIP / kappa) : rules.speed_scale;
		if (vc > rules.speed_scale) {
			vc = rules.speed_scale;
		}
		inputs[NR + 6 + w] = (float)clamp1((vc - u) / MARGIN_SCALE);
	}
}

// NeuralNetwork.forward(): float32 weights and activations, double sums, tanh.
// p: the network's parameters; acts: every layer's activations (layer 0 = the inputs).
void FleetSim::forward(const float *p, float *acts, const float *inputs) const {
	const int n0 = sizes[0];
	for (int i = 0; i < n0; i++) {
		acts[i] = inputs[i];
	}
	float *inp = acts;
	for (size_t l = 0; l + 1 < sizes.size(); l++) {
		const int n_in = sizes[l];
		const int n_out = sizes[l + 1];
		const float *w = p;
		const float *b = p + n_in * n_out;
		p = b + n_out;
		float *out = inp + n_in;
		for (int o = 0; o < n_out; o++) {
			double s = (double)b[o];
			const float *wo = w + o * n_in;
			for (int i = 0; i < n_in; i++) {
				s += (double)wo[i] * (double)inp[i];
			}
			out[o] = (float)std::tanh(s);
		}
		inp = out;
	}
}

// Sensors.drive_network(): the network on the mirrored inputs, then on the real ones;
// steer = (s - s') / 2, throttle = (t + t') / 2, stored as 32-bit floats in the output layer.
void FleetSim::drive(int k, Agent &a) const {
	const float *src = a.inputs;
	float *dst = a.mirrored;
	for (int i = 0; i < NR; i++) {
		dst[i] = src[NR - 1 - i];
	}
	for (int i = NR; i < INPUT_COUNT; i++) {
		dst[i] = src[i];
	}
	for (int i : MIRROR_NEGATE) {
		dst[i] = -src[i];
	}
	const float *p = params.data() + (size_t)k * per_net;
	float *acts = a.acts.data();
	float *out = acts + (act_count - 2);
	forward(p, acts, a.mirrored);
	double ms = out[0];
	double mt = out[1];
	forward(p, acts, a.inputs);
	out[0] = (float)(0.5 * ((double)out[0] - ms));
	out[1] = (float)(0.5 * ((double)out[1] + mt));
	a.ctrl.steer = out[0];
	a.ctrl.throttle = out[1];
	a.ctrl.handbrake = false;
	a.ctrl.nitro = 0.0;
}

// One car through one step: the body of the loop in Trainer.step().
void FleetSim::step_agent(Agent &a, int k, double dt, double now, double cutoff, ThreadStats &st) const {
	CarState &car = a.car;
	a.prev_x = car.x;
	a.prev_y = car.y;
	a.prev_z = car.z;
	a.prev_yaw = car.yaw;
	sense(a);
	drive(k, a);
	car_step(car, spec, track, a.ctrl, dt);
	// RaceState.update(): timer, gates in order, lap and finish times
	bool events = false;
	if (!a.race_finished) {
		a.race_time += dt;
		const int n_gates = (int)track.gate_prog.size();
		while (a.next_gate < n_gates && car.prog >= track.gate_prog[a.next_gate]) {
			int kind = track.gate_kind[a.next_gate];
			if (kind == 1 || kind == 2) {
				double lap_time = a.race_time - a.lap_start;
				if (lap_time < st.best_lap) {
					st.best_lap = lap_time; // Trainer.record_time
				}
				a.lap_start = a.race_time;
			}
			if (kind == 2) {
				a.race_finished = true;
				a.finish_time = a.race_time;
				if (a.race_time < st.best_finish) {
					st.best_finish = a.race_time;
				}
			}
			a.next_gate += 1;
			events = true;
		}
	}
	if (events && !a.race_finished) {
		a.gate_deadline = gate_deadline_for(a, track.gate_prog[a.next_gate - 1], now);
	}

	if (car.prog > a.max_prog + 3.0) {
		a.max_prog = car.prog;
		a.last_improve = now;
	}
	a.fitness = score(a, now);
	if (car.hit_wall && !a.touched_wall) {
		a.touched_wall = true;
		st.wall_cars += 1;
	}

	int reason = 0;
	if (a.race_finished) {
		reason = 1; // finished
		a.finished = true;
		if (a.finish_time < st.first_finish) {
			st.first_finish = a.finish_time;
		}
	} else if (car.hit_wall && rules.walls_crash) {
		reason = 2; // wall
	} else if ((a.max_prog - car.prog) * track.seg_len > rules.backwards) {
		reason = 3; // backwards
	} else if (now - a.last_improve > rules.stall_time) {
		reason = 4; // stalled
	} else if (now > a.gate_deadline) {
		reason = 5; // too slow
	} else if (now > cutoff) {
		reason = 6; // cut off
	} else if (now > time_limit) {
		reason = 7; // time
	}
	if (reason != 0) {
		a.alive = false;
		a.reason = reason;
		st.deaths[reason] += 1;
		a.prev_x = car.x; // parked: no interpolation wobble
		a.prev_y = car.y;
		a.prev_z = car.z;
		a.prev_yaw = car.yaw;
	}
	st.car_steps += 1;
}

int FleetSim::alive_in(int first, int stride) const {
	int n = 0;
	for (int k = first; k < (int)agents.size(); k += stride) {
		if (agents[k].alive) {
			n++;
		}
	}
	return n;
}

// One thread's share of a chunk: cars first, first + stride, ... for up to n_steps steps,
// stopping when none of them is alive. The step clock and the first-finish time follow
// Trainer.step() (the clock adds dt each step exactly like the trainer's sim_time).
void FleetSim::run_cars(int first, int stride, int n_steps, double dt, double start_time, ThreadStats &st) {
	double now = start_time;
	const int n = (int)agents.size();
	if (alive_in(first, stride) == 0) {
		return;
	}
	for (int s = 0; s < n_steps; s++) {
		now += dt;
		double ff = first_finish < st.first_finish ? first_finish : st.first_finish;
		double cutoff = ff != INFINITY ? ff * rules.finish_cutoff + rules.finish_slack : INFINITY;
		bool any_alive = false;
		for (int k = first; k < n; k += stride) {
			Agent &a = agents[k];
			if (!a.alive) {
				continue;
			}
			step_agent(a, k, dt, now, cutoff, st);
			if (a.alive) {
				any_alive = true;
			}
		}
		st.steps = s + 1;
		if (!any_alive) {
			break;
		}
	}
}

// Advance up to max_steps steps of dt; stops early at the end of the run (no car alive).
// Returns the steps done. Trainer.step_many() calls it and handles the run's end.
int FleetSim::step(int max_steps, double dt) {
	if (run_over || max_steps <= 0) {
		return 0;
	}
	int done = 0;
	while (done < max_steps && !run_over) {
		const int chunk = std::min(CHUNK, max_steps - done);
		const int alive = alive_count();
		int nt = std::min(threads, std::max(1, alive));
		if (chunk * alive < MIN_PARALLEL) {
			nt = 1;
		}
		std::vector<ThreadStats> stats(nt);
		const double t0 = sim_time;
		if (nt == 1) {
			run_cars(0, 1, chunk, dt, t0, stats[0]);
		} else {
			std::vector<std::thread> pool;
			pool.reserve(nt - 1);
			for (int t = 1; t < nt; t++) {
				pool.emplace_back([this, t, nt, chunk, dt, t0, &stats]() { run_cars(t, nt, chunk, dt, t0, stats[t]); });
			}
			run_cars(0, nt, chunk, dt, t0, stats[0]);
			for (std::thread &th : pool) {
				th.join();
			}
		}
		// merge what the threads found
		int steps = 0;
		for (const ThreadStats &st : stats) {
			steps = std::max(steps, st.steps);
			for (int r = 0; r < 8; r++) {
				deaths[r] += st.deaths[r];
			}
			wall_cars += st.wall_cars;
			best_lap = std::min(best_lap, st.best_lap);
			best_finish = std::min(best_finish, st.best_finish);
			first_finish = std::min(first_finish, st.first_finish);
			car_steps += st.car_steps;
		}
		if (steps == 0) {
			run_over = true; // (no car was alive)
			break;
		}
		for (int s = 0; s < steps; s++) {
			sim_time += dt; // the same additions as each thread's clock
		}
		done += steps;
		if (alive_count() == 0) {
			run_over = true;
		}
	}
	return done;
}

bool FleetSim::is_run_over() const {
	return run_over;
}

int FleetSim::alive_count() const {
	return alive_in(0, 1);
}

int FleetSim::agent_count() const {
	return (int)agents.size();
}

// ---- results --------------------------------------------------------------------------------

double FleetSim::get_sim_time() const {
	return sim_time;
}

double FleetSim::get_first_finish() const {
	return first_finish;
}

int FleetSim::get_wall_cars() const {
	return wall_cars;
}

Dictionary FleetSim::get_deaths() const {
	Dictionary d;
	for (int r = 1; r < 8; r++) {
		if (deaths[r] > 0) {
			d[REASON_NAMES[r]] = deaths[r];
		}
	}
	return d;
}

double FleetSim::get_best_lap() const {
	return best_lap;
}

double FleetSim::get_best_finish() const {
	return best_finish;
}

int64_t FleetSim::get_car_steps() const {
	return car_steps;
}

PackedFloat64Array FleetSim::get_fitness() const {
	PackedFloat64Array out;
	out.resize(agents.size());
	for (size_t k = 0; k < agents.size(); k++) {
		out.set(k, agents[k].fitness);
	}
	return out;
}

PackedInt32Array FleetSim::get_reasons() const {
	PackedInt32Array out;
	out.resize(agents.size());
	for (size_t k = 0; k < agents.size(); k++) {
		out.set(k, agents[k].reason);
	}
	return out;
}

// What the view draws of every car (VIEW_STRIDE numbers each; see Trainer.sync_agents()).
PackedFloat64Array FleetSim::get_view_states() const {
	PackedFloat64Array out;
	out.resize(agents.size() * VIEW_STRIDE);
	double *o = out.ptrw();
	for (const Agent &a : agents) {
		const CarState &c = a.car;
		const double v[VIEW_STRIDE] = {
			c.x, c.y, c.z, c.yaw, c.pitch, c.roll, c.steer_angle, c.wheel_rot, c.vx, c.vz,
			c.speed, c.forward_speed, c.side_speed, c.steer, c.throttle, c.slip,
			c.grounded ? 1.0 : 0.0, c.drifting ? 1.0 : 0.0, c.braking ? 1.0 : 0.0, c.hit_wall ? 1.0 : 0.0,
			(double)c.wall_hits, c.wall_impact, c.wall_scrape, c.wall_x, c.wall_y, c.wall_z, c.wall_nx, c.wall_nz,
			(double)c.idx, c.prog, c.yaw_rate, a.prev_x, a.prev_y, a.prev_z, a.prev_yaw,
		};
		std::copy(v, v + VIEW_STRIDE, o);
		o += VIEW_STRIDE;
	}
	return out;
}

int FleetSim::view_stride() const {
	return VIEW_STRIDE;
}

PackedFloat32Array FleetSim::get_rays(int k) const {
	PackedFloat32Array out;
	if (k >= 0 && k < (int)agents.size()) {
		out.resize(NR);
		for (int i = 0; i < NR; i++) {
			out.set(i, agents[k].rays[i]);
		}
	}
	return out;
}

PackedFloat32Array FleetSim::get_inputs(int k) const {
	PackedFloat32Array out;
	if (k >= 0 && k < (int)agents.size()) {
		out.resize(INPUT_COUNT);
		for (int i = 0; i < INPUT_COUNT; i++) {
			out.set(i, agents[k].inputs[i]);
		}
	}
	return out;
}

PackedFloat32Array FleetSim::get_acts(int k) const {
	PackedFloat32Array out;
	if (k >= 0 && k < (int)agents.size()) {
		const std::vector<float> &acts = agents[k].acts;
		out.resize(acts.size());
		for (size_t i = 0; i < acts.size(); i++) {
			out.set(i, acts[i]);
		}
	}
	return out;
}

// The whole car state with the JS names, like Car.to_state() (tests compare them).
Dictionary FleetSim::get_car_state(int k) const {
	Dictionary d;
	if (k < 0 || k >= (int)agents.size()) {
		return d;
	}
	const CarState &c = agents[k].car;
	d["x"] = c.x; d["y"] = c.y; d["z"] = c.z; d["vx"] = c.vx; d["vy"] = c.vy; d["vz"] = c.vz; d["yaw"] = c.yaw;
	d["speed"] = c.speed; d["forwardSpeed"] = c.forward_speed; d["sideSpeed"] = c.side_speed;
	d["grounded"] = c.grounded; d["airTime"] = c.air_time; d["drifting"] = c.drifting; d["idx"] = c.idx;
	d["lat"] = c.lat; d["bank"] = c.bank; d["groundY"] = c.ground_y; d["prog"] = c.prog; d["laps"] = c.laps;
	d["hitWall"] = c.hit_wall; d["wallHits"] = c.wall_hits; d["steer"] = c.steer; d["throttle"] = c.throttle;
	d["yawRate"] = c.yaw_rate; d["steerAngle"] = c.steer_angle; d["pitch"] = c.pitch; d["roll"] = c.roll;
	d["rpm"] = c.rpm; d["gear"] = c.gear; d["braking"] = c.braking; d["slip"] = c.slip; d["wheelRot"] = c.wheel_rot;
	d["wallImpact"] = c.wall_impact; d["wallScrape"] = c.wall_scrape; d["wallX"] = c.wall_x; d["wallY"] = c.wall_y;
	d["wallZ"] = c.wall_z; d["wallNx"] = c.wall_nx; d["wallNz"] = c.wall_nz;
	d["nitro"] = c.nitro; d["boost"] = c.boost; d["boosting"] = c.boosting;
	d["_sc"] = c.sc; d["_ax"] = c.ax; d["_ay"] = c.ay; d["_fyr"] = c.fyr; d["_shift"] = c.shift; d["_gear"] = c.gear_;
	d["_pitchV"] = c.pitch_v; d["_rollV"] = c.roll_v; d["_t"] = c.t; d["_nx"] = c.nx; d["_nz"] = c.nz; d["_hw"] = c.hw;
	d["_ground"] = c.ground; d["_slipF"] = c.slip_f; d["_slipR"] = c.slip_r; d["_tcCut"] = c.tc_cut; d["_hb"] = c.hb;
	d["_escOff"] = c.esc_off; d["_airRs"] = c.air_rs; d["_wallT"] = c.wall_t; d["_wallNow"] = c.wall_now; d["_rubT"] = c.rub_t;
	return d;
}

// One car's training bookkeeping (Trainer.Agent fields and its race), for tests.
Dictionary FleetSim::get_agent(int k) const {
	Dictionary d;
	if (k < 0 || k >= (int)agents.size()) {
		return d;
	}
	const Agent &a = agents[k];
	d["alive"] = a.alive;
	d["finished"] = a.finished;
	d["fitness"] = a.fitness;
	d["start_prog"] = a.start_prog;
	d["max_prog"] = a.max_prog;
	d["last_improve"] = a.last_improve;
	d["gate_deadline"] = a.gate_deadline;
	d["death_reason"] = REASON_NAMES[a.reason];
	d["touched_wall"] = a.touched_wall;
	d["next_gate"] = a.next_gate;
	d["race_time"] = a.race_time;
	d["finish_time"] = a.finish_time;
	d["race_finished"] = a.race_finished;
	return d;
}

double FleetSim::debug_sharpest(int l, int r) const {
	return sharpest(track, l, r);
}

double FleetSim::debug_heading(double s) const {
	return heading_at(track, s);
}

String FleetSim::version() const {
	return "trackrush-native 1";
}

void FleetSim::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_spec", "spec"), &FleetSim::set_spec);
	ClassDB::bind_method(D_METHOD("set_track", "track"), &FleetSim::set_track);
	ClassDB::bind_method(D_METHOD("set_rules", "rules"), &FleetSim::set_rules);
	ClassDB::bind_method(D_METHOD("set_networks", "sizes", "params", "count"), &FleetSim::set_networks);
	ClassDB::bind_method(D_METHOD("set_threads", "n"), &FleetSim::set_threads);
	ClassDB::bind_method(D_METHOD("get_threads"), &FleetSim::get_threads);
	ClassDB::bind_method(D_METHOD("begin_run"), &FleetSim::begin_run);
	ClassDB::bind_method(D_METHOD("step", "max_steps", "dt"), &FleetSim::step);
	ClassDB::bind_method(D_METHOD("is_run_over"), &FleetSim::is_run_over);
	ClassDB::bind_method(D_METHOD("alive_count"), &FleetSim::alive_count);
	ClassDB::bind_method(D_METHOD("agent_count"), &FleetSim::agent_count);
	ClassDB::bind_method(D_METHOD("get_sim_time"), &FleetSim::get_sim_time);
	ClassDB::bind_method(D_METHOD("get_first_finish"), &FleetSim::get_first_finish);
	ClassDB::bind_method(D_METHOD("get_wall_cars"), &FleetSim::get_wall_cars);
	ClassDB::bind_method(D_METHOD("get_deaths"), &FleetSim::get_deaths);
	ClassDB::bind_method(D_METHOD("get_best_lap"), &FleetSim::get_best_lap);
	ClassDB::bind_method(D_METHOD("get_best_finish"), &FleetSim::get_best_finish);
	ClassDB::bind_method(D_METHOD("get_car_steps"), &FleetSim::get_car_steps);
	ClassDB::bind_method(D_METHOD("get_fitness"), &FleetSim::get_fitness);
	ClassDB::bind_method(D_METHOD("get_reasons"), &FleetSim::get_reasons);
	ClassDB::bind_method(D_METHOD("get_view_states"), &FleetSim::get_view_states);
	ClassDB::bind_method(D_METHOD("view_stride"), &FleetSim::view_stride);
	ClassDB::bind_method(D_METHOD("get_rays", "k"), &FleetSim::get_rays);
	ClassDB::bind_method(D_METHOD("get_inputs", "k"), &FleetSim::get_inputs);
	ClassDB::bind_method(D_METHOD("get_acts", "k"), &FleetSim::get_acts);
	ClassDB::bind_method(D_METHOD("get_car_state", "k"), &FleetSim::get_car_state);
	ClassDB::bind_method(D_METHOD("get_agent", "k"), &FleetSim::get_agent);
	ClassDB::bind_method(D_METHOD("version"), &FleetSim::version);
	ClassDB::bind_method(D_METHOD("debug_sharpest", "l", "r"), &FleetSim::debug_sharpest);
	ClassDB::bind_method(D_METHOD("debug_heading", "s"), &FleetSim::debug_heading);
}

} // namespace trackrush
