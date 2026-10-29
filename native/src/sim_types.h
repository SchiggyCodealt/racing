// sim_types.h
// ------------------------------------------------------------------
// Plain data for the native training simulation (FleetSim): the car spec,
// the built track, a located point, a wall contact and one car's state.
// Every field mirrors a GDScript one (sim/car_spec.gd, sim/built_track.gd,
// sim/collision.gd, sim/car.gd); the names are the GDScript names.
//
// Numbers: everything is a 64-bit double, as in GDScript. Track arrays that
// GDScript keeps as 32-bit floats (PackedFloat32Array) are converted to doubles
// once when the track is handed over (exact), so no arithmetic here ever runs
// in single precision by accident.
#pragma once

#include <cstdint>
#include <vector>

namespace trackrush {

// sim/car_spec.gd (CarSpec): every tuning constant plus the derived ones.
struct Spec {
	// chassis
	double mass = 1250.0, inertia = 1850.0, cg_to_front = 1.2, cg_to_rear = 1.4, cg_height = 0.42, wheel_radius = 0.34;
	// tyres
	double mu = 1.6, handbrake = 0.8, handbrake_fast = 0.55, handbrake_rate = 6.0, load_sensitivity = 0.08;
	double pac_b = 13.0, pac_c = 1.9, pac_e = 0.97;
	// aero
	double drag = 0.62, downforce = 0.65, aero_front = 0.42, roll_resist = 0.013;
	// engine and gearbox
	double idle_rpm = 1000.0, redline = 8200.0, upshift_rpm = 7700.0, downshift_rpm = 4200.0, launch_rpm = 5500.0;
	std::vector<double> gears;
	double final_drive = 3.4, reverse_ratio = 3.2, efficiency = 0.88, shift_time = 0.12, drive_front = 0.35;
	double slide_drive = 1.2, max_reverse = 15.0;
	// brakes
	double brake_force = 13800.0, brake_front = 0.68;
	// steering
	double steer_lock = 0.7, steer_rate = 7.0, steer_ref_accel = 18.0, steer_slip_gain = 1.15, steer_extra_fast = 0.04;
	double steer_slow_speed = 12.0, steer_fast_speed = 35.0, steer_assist = 0.65, assist_from = 0.12, assist_full = 0.25;
	// stability control
	double esc = 1.0, esc_gain = 8.0, esc_moment = 5000.0, esc_under = 0.3, esc_deadband = 0.04, esc_slow = 0.25;
	double esc_from = 8.0, esc_handbrake_hold = 1.5;
	// body / collision
	double radius = 1.0, half_length = 2.2, wall_restitution = 0.05, max_rebound = 1.0, wall_friction = 0.5;
	double wall_crush = 0.06, wall_slide = 5.0, wall_rub = 0.15, wall_rub_build = 1.0, wall_align = 1.5;
	double wall_align_gain = 12.0, wall_align_accel = 15.0, wall_yaw_stop = 0.4, wall_latch = 0.12;
	double wall_latch_steps = 10.0, wall_height = 1.1;
	// vertical
	double gravity = 9.81, lift_separation = 0.15, min_flight = 0.25, hard_landing = 4.0, landing_loss = 0.012;
	double air_steer = 0.2, air_steer_tau = 0.2, air_yaw_damp = 0.6;
	// nitro
	double nitro_time = 5.0, nitro_force = 4500.0, nitro_power = 130000.0, nitro_top = 82.3, nitro_fade = 3.0;
	// simulation
	int substeps = 2;
	double max_speed = 77.0;
	// derived (CarSpec.derive())
	double wheelbase = 2.6, core = 1.2, peak_slip = 0.0, pac_slope0 = 0.0, peak_steer = 0.0;
	std::vector<double> torque_rpm, torque_nm;
	// the car's grip share on every road surface (CarSpec.surface_grip, sim/surfaces.gd order)
	std::vector<double> surf_grip;

	// CarSpec.pacejka(): magic formula force ratio at slip x.
	double pacejka(double x) const;
	// CarSpec.engine_torque(): engine torque (N m) at rpm from the torque curve.
	double engine_torque(double rpm) const;
};

// sim/built_track.gd (BuiltTrack) + its wall grid (Collision.WallGrid), gates and the
// sensors' heading tables (ai/sensors.gd Headings), as FleetSim needs them.
struct Track {
	bool closed = true;
	int N = 0, count = 0, seg_count = 0, start_idx = 0, finish_idx = 0;
	double seg_len = 2.0, length = 0.0;
	std::vector<double> px, py, pz, tx, tz, nx, nz, hw, bank;
	std::vector<double> phys_slope, phys_kv; // Car.track_phys()
	// road surfaces (BuiltTrack.surf_w: surf_n blend weights a sample; empty = all asphalt) and the
	// surface table's physics columns (sim/surfaces.gd: roll, stiffness, esc)
	std::vector<double> surf_w, surf_roll, surf_stiff, surf_esc;
	int surf_n = 0;
	// wall grid (collision.gd WallGrid)
	double cell = 12.0, min_x = 0.0, min_z = 0.0;
	int cols = 0, rows = 0;
	std::vector<double> seg_d, inward;
	std::vector<int32_t> cell_start, cell_segs, seg_cell;
	// gates for the training laps (TrackBuilder.get_gates): progress and kind (0 cp, 1 lap, 2 finish)
	std::vector<double> gate_prog;
	std::vector<int32_t> gate_kind;
	double race_len = 0.0;
	// sensors.gd Headings
	std::vector<double> head_theta;
	double head_total = 0.0;
	int head_n = 0, head_len = 0;
	std::vector<std::vector<double>> head_sparse;
};

// collision.gd Collision.Loc: a point located on the track.
struct Loc {
	int idx = 0;
	double t = 0.0, t_raw = 0.0, prog = 0.0, lat = 0.0, nx = 0.0, nz = 0.0, ground_y = 0.0, bank = 0.0, hw = 0.0;
};

// collision.gd Collision.Contact: the deepest wall contact.
struct Contact {
	double depth = 0.0, nx = 0.0, nz = 0.0, px = 0.0, pz = 0.0;
	int seg = 0;
};

// car.gd Car.Controls
struct Controls {
	double steer = 0.0, throttle = 0.0;
	bool handbrake = false;
	double nitro = 0.0;
};

// car.gd Car: the whole state of one car (public fields, then the "_" internals).
struct CarState {
	double x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0, yaw = 0, speed = 0, forward_speed = 0, side_speed = 0;
	bool grounded = true;
	double air_time = 0;
	bool drifting = false;
	int idx = 0;
	double lat = 0, bank = 0, ground_y = 0, prog = 0;
	int laps = 0;
	bool hit_wall = false;
	int wall_hits = 0;
	double steer = 0, throttle = 0;
	double yaw_rate = 0, steer_angle = 0, pitch = 0, roll = 0, rpm = 1000.0;
	int gear = 0;
	bool braking = false;
	double slip = 0, wheel_rot = 0;
	double wall_impact = 0, wall_scrape = 0, wall_x = 0, wall_y = 0, wall_z = 0, wall_nx = 0, wall_nz = 0;
	double nitro = 1.0, boost = 0;
	bool boosting = false;
	// internals
	double sc = 0, ax = 0, ay = 0, fyr = 0, shift = 0;
	int gear_ = 1; // car.gd _gear
	double pitch_v = 0, roll_v = 0, t = 0, nx = 1.0, nz = 0.0, hw = 7.0, ground = 0;
	double slip_f = 0, slip_r = 0, tc_cut = 0, hb = 0, esc_off = 0, air_rs = 0;
	int wall_t = 1000000;
	bool wall_now = false;
	double rub_t = 0;
	// per-step environment shared by the sub-steps (car.gd _env_*)
	double env_gx = 0, env_gz = 0, env_gn = 9.81, env_drive = 0, env_brake = 0, env_hb = 0, env_esc = 1.0;
	// the road surface under the axles (car.gd _env_loose ... _env_pk, _mx_*)
	bool env_loose = false;
	double env_gf = 1.0, env_gr = 1.0, env_kf = 1.0, env_kr = 1.0, env_rf = 1.0, env_rr = 1.0, env_sesc = 1.0, env_pk = 0.0;
	double mx_g = 1.0, mx_k = 1.0, mx_r = 1.0, mx_e = 1.0;
	bool mx_pure = true;
	// scratch (car.gd _loc, _contact, _att_pitch, _att_roll)
	Loc loc;
	Contact contact;
	double att_pitch = 0, att_roll = 0;
};

} // namespace trackrush
