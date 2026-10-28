// car_sim.h
// ------------------------------------------------------------------
// The car physics and track queries of the native training simulation:
// C++ ports of sim/collision.gd (locate, raycast, collide_capsule) and
// sim/car.gd (Car.place, Car.step). See those files for how they work; the
// .cpp keeps their structure, order of operations and comments, so the
// same inputs give the same doubles (both call the same C library for
// sin, cos, atan2, tan, exp, asin, sqrt).
#pragma once

#include "sim_types.h"

namespace trackrush {

// JsMath.hypot2: V8's Math.hypot(a, b), bit for bit.
double js_hypot2(double a, double b);

// Collision.locate / locate_near (sim/collision.gd)
Loc &locate(const Track &track, double x, double z, int hint, Loc &out);
Loc &locate_near(const Track &track, double x, double z, int i, Loc &out);
// Collision.raycast: distance to the first wall along a ray, or max_dist.
double raycast(const Track &track, double ox, double oz, double dx, double dz, double max_dist);
// Collision.collide_capsule: deepest contact of a capsule with the walls.
bool collide_capsule(const Track &track, double p0x, double p0z, double p1x, double p1z, double R, Contact &out,
		double max_behind = 1.6);

// Car.new(track, sample_idx, spec) / Car.place(track, sample_idx) without a snapshot.
void car_init(CarState &car, const Spec &P, const Track &track, int sample_idx);
// Car.step(track, ctrl, dt)
void car_step(CarState &car, const Spec &P, const Track &track, const Controls &ctrl, double dt);

} // namespace trackrush
