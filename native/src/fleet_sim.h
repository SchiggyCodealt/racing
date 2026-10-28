// fleet_sim.h
// ------------------------------------------------------------------
// FleetSim: the native fast path of AI training (a GDExtension class).
// One call steps a whole population of AI cars for one track run:
// sensors (ai/sensors.gd) + network forward with the mirrored pass
// (ai/network.gd, Sensors.drive_network) + car physics (sim/car.gd) +
// race gates (sim/race.gd) + fitness and elimination rules (ai/trainer.gd
// Trainer.step), optionally on several native threads.
//
// The GDScript Trainer (ai/trainer.gd) drives it: it hands over the car spec,
// the track (with every table GDScript computed: wall grid, gates, physics and
// heading tables) and the networks, then calls step() and reads the results.
// The genetic algorithm stays in GDScript.
//
// Results are the same as the GDScript path's, bit for bit on the same machine
// (tests/test_ai.gd checks it): same expressions in the same order, doubles
// everywhere, 32-bit floats exactly where the GDScript stores them.
#pragma once

#include "sim_types.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cmath>
#include <cstdint>
#include <vector>

namespace trackrush {

// The training rules (Trainer.RULES + settings), see ai/trainer.gd.
struct Rules {
	double stall_time = 3.0, backwards = 20.0, min_pace = 8.0, gate_slack = 10.0, time_slack = 20.0;
	double finish_cutoff = 1.25, finish_slack = 5.0, ref_speed = 50.0;
	bool walls_crash = false;
	int laps = 1;
	double speed_scale = 77.0; // Sensors.SPEED_SCALE
};

// One car of the run (Trainer.Agent with its RaceState).
struct Agent {
	CarState car;
	Controls ctrl;
	// RaceState (sim/race.gd), only what training uses
	int next_gate = 0;
	double race_time = 0.0, lap_start = 0.0, finish_time = INFINITY;
	bool race_finished = false;
	// Trainer.Agent
	bool alive = true, finished = false, touched_wall = false;
	int reason = 0; // Trainer.REASONS index (0 = still driving)
	double fitness = 0.0, start_prog = 0.0, max_prog = 0.0, last_improve = 0.0, gate_deadline = 0.0;
	double prev_x = 0.0, prev_y = 0.0, prev_z = 0.0, prev_yaw = 0.0;
	float inputs[18] = {};
	float mirrored[18] = {};
	float rays[9] = {};
	std::vector<float> acts; // every layer's activations after the last forward
};

// What one thread found while stepping its cars (merged after each chunk).
struct ThreadStats {
	int steps = 0;
	int deaths[8] = {};
	int wall_cars = 0;
	double best_lap = INFINITY, best_finish = INFINITY, first_finish = INFINITY;
	int64_t car_steps = 0;
};

class FleetSim : public godot::RefCounted {
	GDCLASS(FleetSim, godot::RefCounted)

	Spec spec;
	Track track;
	Rules rules;
	std::vector<int> sizes;
	std::vector<float> params;
	int per_net = 0;
	int act_count = 0;
	int net_count = 0;
	std::vector<Agent> agents;
	int threads = 1;
	bool have_spec = false, have_track = false;
	// run state (Trainer: sim_time, first_finish, deaths, wall_cars, race_len, ...)
	double sim_time = 0.0;
	double first_finish = INFINITY;
	double race_len = 0.0, ref_time = 0.0, time_limit = 0.0;
	int deaths[8] = {};
	int wall_cars = 0;
	double best_lap = INFINITY, best_finish = INFINITY;
	bool run_over = true;
	int64_t car_steps = 0;
	double ray_cos[9] = {}, ray_sin[9] = {};

	void sense(Agent &a) const;
	void forward(const float *p, float *acts, const float *inputs) const;
	void drive(int k, Agent &a) const;
	double gate_deadline_for(const Agent &a, double from_prog, double now) const;
	double score(const Agent &a, double now) const;
	void step_agent(Agent &a, int k, double dt, double now, double cutoff, ThreadStats &st) const;
	void run_cars(int first, int stride, int n_steps, double dt, double start_time, ThreadStats &st);
	int alive_in(int first, int stride) const;

protected:
	static void _bind_methods();

public:
	FleetSim();

	void set_spec(const godot::Dictionary &d);
	void set_track(const godot::Dictionary &d);
	void set_rules(const godot::Dictionary &d);
	void set_networks(const godot::PackedInt32Array &p_sizes, const godot::PackedFloat32Array &p_params, int count);
	void set_threads(int n);
	int get_threads() const;

	void begin_run();
	int step(int max_steps, double dt);
	bool is_run_over() const;
	int alive_count() const;
	int agent_count() const;

	double get_sim_time() const;
	double get_first_finish() const;
	int get_wall_cars() const;
	godot::Dictionary get_deaths() const;
	double get_best_lap() const;
	double get_best_finish() const;
	int64_t get_car_steps() const;
	godot::PackedFloat64Array get_fitness() const;
	godot::PackedInt32Array get_reasons() const;
	godot::PackedFloat64Array get_view_states() const;
	int view_stride() const;
	godot::PackedFloat32Array get_rays(int k) const;
	godot::PackedFloat32Array get_inputs(int k) const;
	godot::PackedFloat32Array get_acts(int k) const;
	godot::Dictionary get_car_state(int k) const;
	godot::Dictionary get_agent(int k) const;
	godot::String version() const;
	// the sensors' track queries, for tests
	double debug_sharpest(int l, int r) const;
	double debug_heading(double s) const;
};

} // namespace trackrush
