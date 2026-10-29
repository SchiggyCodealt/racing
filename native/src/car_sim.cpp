// car_sim.cpp
// ------------------------------------------------------------------
// C++ port of sim/collision.gd (the queries the car and the sensors use) and
// sim/car.gd (car physics v3 with nitro), for the native training simulation.
// Read the GDScript files for the model; this file keeps their structure,
// their comments (shortened) and, line by line, their order of operations.
//
// Bit parity with GDScript: GDScript computes in doubles and calls the C
// library for sin, cos, tan, atan, atan2, asin, exp, sqrt, fmod, floor, so the
// same expressions here give the same results on the same machine. Build with
// -ffp-contract=off (native/SConstruct): no fused multiply-adds, which would
// round differently. GDScript's minf/maxf are `a < b ? a : b` / `a > b ? a : b`.
#include "car_sim.h"

#include <cmath>

namespace trackrush {

namespace {

constexpr double PI = 3.14159265358979323846;
constexpr double G = 9.81; // car.gd G
constexpr double SKIN = 0.03; // car.gd SKIN: m, contact skin around the capsule
constexpr double WALL_Y = 0.45; // car.gd WALL_Y: m above the car's base where wall_y puts a contact
constexpr double U_MIN = 1.5; // car.gd U_MIN
constexpr int SEARCH_WINDOW = 8; // collision.gd SEARCH_WINDOW
constexpr double KINK_DOT = 0.5; // collision.gd KINK_DOT

// GDScript utility functions with their exact semantics.
inline double minf(double a, double b) { return a < b ? a : b; }
inline double maxf(double a, double b) { return a > b ? a : b; }
inline int mini(int a, int b) { return a < b ? a : b; }
inline int maxi(int a, int b) { return a > b ? a : b; }
inline int posmod(int a, int b) {
	int v = a % b;
	if ((v < 0 && b > 0) || (v > 0 && b < 0)) {
		v += b;
	}
	return v;
}
inline double signf(double x) { return x > 0.0 ? 1.0 : (x < 0.0 ? -1.0 : 0.0); }
// car.gd _clamp
inline double clampd(double v, double a, double b) { return v < a ? a : (v > b ? b : v); }

} // namespace

// ===========================================================================
// js_math.gd
// ===========================================================================

double js_hypot2(double a, double b) {
	double aa = std::fabs(a);
	double ab = std::fabs(b);
	if (std::isnan(a) || std::isnan(b)) {
		return (std::isinf(a) || std::isinf(b)) ? INFINITY : NAN;
	}
	double mx = aa > ab ? aa : ab;
	if (mx == INFINITY) {
		return INFINITY;
	}
	if (mx == 0.0) {
		return 0.0;
	}
	// Kahan summation of the squares, normalised by the largest value
	double sum = 0.0;
	double comp = 0.0;
	double n = aa / mx;
	double summand = n * n - comp;
	double pre = sum + summand;
	comp = (pre - sum) - summand;
	sum = pre;
	n = ab / mx;
	summand = n * n - comp;
	pre = sum + summand;
	sum = pre;
	return std::sqrt(sum) * mx;
}

double Spec::pacejka(double x) const {
	double b = pac_b * x;
	return std::sin(pac_c * std::atan(b - pac_e * (b - std::atan(b))));
}

double Spec::engine_torque(double rpm) const {
	const int n = (int)torque_rpm.size();
	if (rpm <= torque_rpm[0]) {
		return torque_nm[0];
	}
	for (int k = 1; k < n; k++) {
		if (rpm <= torque_rpm[k]) {
			double a0 = torque_rpm[k - 1];
			double a1 = torque_nm[k - 1];
			return a1 + ((torque_nm[k] - a1) * (rpm - a0)) / (torque_rpm[k] - a0);
		}
	}
	return torque_nm[n - 1];
}

// ===========================================================================
// collision.gd
// ===========================================================================

// Collision.locate: nearest straight segment in a window around the hint, then the
// smooth projection (locate_near).
Loc &locate(const Track &track, double x, double z, int hint, Loc &out) {
	const int N = track.N;
	const bool closed = track.closed;
	const double *px = track.px.data();
	const double *pz = track.pz.data();
	const int seg_count = track.seg_count;
	double best = INFINITY;
	int bi = 0;
	for (int k = -SEARCH_WINDOW; k <= SEARCH_WINDOW; k++) {
		int i = hint + k;
		if (closed) {
			i = posmod(i, N);
		} else if (i < 0 || i >= seg_count) {
			continue;
		}
		int j = closed ? (i + 1) % N : i + 1;
		double ax = px[i];
		double az = pz[i];
		double ex = px[j] - ax;
		double ez = pz[j] - az;
		double t = ((x - ax) * ex + (z - az) * ez) / (ex * ex + ez * ez);
		t = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
		double qx = ax + ex * t - x;
		double qz = az + ez * t - z;
		double d2 = qx * qx + qz * qz;
		if (d2 < best) {
			best = d2;
			bi = i;
		}
	}
	return locate_near(track, x, z, bi, out);
}

// Collision.locate_near: smooth projection starting at segment i, walking to the
// neighbour segment (at most a few) until the point projects inside a segment.
Loc &locate_near(const Track &track, double x, double z, int i, Loc &out) {
	const int N = track.N;
	const bool closed = track.closed;
	const double *px = track.px.data();
	const double *pz = track.pz.data();
	const double *nx = track.nx.data();
	const double *nz = track.nz.data();
	const int seg_count = track.seg_count;
	if (closed) {
		i = posmod(i, N);
	} else {
		i = i < 0 ? 0 : (i >= seg_count ? seg_count - 1 : i);
	}

	double t = 0.0;
	int dir = 0;
	for (int iter = 0; iter < 8; iter++) {
		// t = _smooth_t(track, x, z, i), inlined
		int j0 = closed ? (i + 1) % N : i + 1;
		double wx = x - px[i];
		double wz = z - pz[i];
		double ex0 = px[j0] - px[i];
		double ez0 = pz[j0] - pz[i];
		if (nx[i] * nx[j0] + nz[i] * nz[j0] < KINK_DOT) {
			double ee = ex0 * ex0 + ez0 * ez0;
			t = (wx * ex0 + wz * ez0) / (ee != 0.0 ? ee : 1e-9);
		} else {
			double tix = -nz[i];
			double tiz = nx[i];
			double dtx = -nz[j0] - tix;
			double dtz = nx[j0] - tiz;
			double a2 = -(ex0 * dtx + ez0 * dtz);
			double a1 = wx * dtx + wz * dtz - (ex0 * tix + ez0 * tiz);
			double a0 = wx * tix + wz * tiz;
			if (std::fabs(a2) < 1e-9 * std::fabs(a1)) {
				t = -a0 / a1;
			} else {
				double disc = a1 * a1 - 4.0 * a2 * a0;
				if (disc < 0.0) {
					t = -a0 / a1;
				} else {
					t = a0 / (-0.5 * (a1 + (a1 < 0.0 ? -1.0 : 1.0) * std::sqrt(disc)));
				}
			}
		}
		if (t < 0.0) {
			if (!closed && i == 0) {
				break;
			}
			if (dir == 1) {
				t = 0.0; // ping-pong between two segments: on the boundary
				break;
			}
			dir = -1;
			i = closed ? (i - 1 + N) % N : i - 1;
		} else if (t > 1.0) {
			if (!closed && i == seg_count - 1) {
				break;
			}
			if (dir == -1) {
				t = 1.0;
				break;
			}
			dir = 1;
			i = closed ? (i + 1) % N : i + 1;
		} else {
			break;
		}
	}

	int j = closed ? (i + 1) % N : i + 1;
	double t_raw = t;
	double tc = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
	// For points beyond the ends of an open track, extrapolate along the end segment.
	double te = closed ? tc : t_raw;
	double cx = px[i] + (px[j] - px[i]) * te;
	double cz = pz[i] + (pz[j] - pz[i]) * te;
	double mx = nx[i] + (nx[j] - nx[i]) * tc;
	double mz = nz[i] + (nz[j] - nz[i]) * tc;
	if (nx[i] * nx[j] + nz[i] * nz[j] < KINK_DOT) {
		// kink: use the segment's own left normal
		double ex = px[j] - px[i];
		double ez = pz[j] - pz[i];
		double el = std::sqrt(ex * ex + ez * ez);
		if (el == 0.0) {
			el = 1.0;
		}
		mx = ez / el;
		mz = -ex / el;
	}
	double m2 = mx * mx + mz * mz;
	double lat = ((x - cx) * mx + (z - cz) * mz) / m2;
	double inv = 1.0 / std::sqrt(m2);
	const double *bk = track.bank.data();
	double bank_i = bk[i];
	double bank = bank_i + (bk[j] - bank_i) * tc;
	const double *py = track.py.data();
	double py_i = py[i];
	double cy = py_i + (py[j] - py_i) * tc;
	const double *hw = track.hw.data();
	double hw_i = hw[i];

	out.idx = i;
	out.t = tc;
	out.t_raw = t_raw;
	out.prog = i + tc;
	out.lat = lat;
	out.nx = mx * inv;
	out.nz = mz * inv;
	out.bank = bank;
	out.hw = hw_i + (hw[j] - hw_i) * tc;
	// Positive bank (left-hand turn) raises the right edge (negative lat).
	out.ground_y = cy - lat * std::tan(bank);
	return out;
}

// Collision.raycast: grid DDA traversal; distance to the first wall, or max_dist.
double raycast(const Track &track, double ox, double oz, double dx, double dz, double max_dist) {
	const double cell = track.cell;
	const double min_x = track.min_x;
	const double min_z = track.min_z;
	const int cols = track.cols;
	const int rows = track.rows;
	const double *seg_d = track.seg_d.data();
	const int32_t *cell_start = track.cell_start.data();
	const int32_t *cell_segs = track.cell_segs.data();
	int cx = (int)std::floor((ox - min_x) / cell);
	int cz = (int)std::floor((oz - min_z) / cell);
	int step_x = dx > 0.0 ? 1 : -1;
	int step_z = dz > 0.0 ? 1 : -1;
	double t_delta_x = dx != 0.0 ? cell / std::fabs(dx) : INFINITY;
	double t_delta_z = dz != 0.0 ? cell / std::fabs(dz) : INFINITY;
	double t_max_x = dx != 0.0 ? ((cx + (dx > 0.0 ? 1 : 0)) * cell + min_x - ox) / dx : INFINITY;
	double t_max_z = dz != 0.0 ? ((cz + (dz > 0.0 ? 1 : 0)) * cell + min_z - oz) / dz : INFINITY;
	double best = max_dist;

	while (cx >= 0 && cz >= 0 && cx < cols && cz < rows) {
		int ci = cz * cols + cx;
		int end = cell_start[ci + 1];
		for (int k = cell_start[ci]; k < end; k++) {
			int o = cell_segs[k] << 2;
			double ex = seg_d[o + 2];
			double ez = seg_d[o + 3];
			double denom = dx * ez - dz * ex;
			if (denom > -1e-9 && denom < 1e-9) {
				continue;
			}
			double wx = seg_d[o] - ox;
			double wz = seg_d[o + 1] - oz;
			double t = (wx * ez - wz * ex) / denom;
			if (t < 0.0 || t >= best) {
				continue;
			}
			double s = (wx * dz - wz * dx) / denom;
			if (s >= 0.0 && s <= 1.0) {
				best = t;
			}
		}
		double t_next = t_max_x < t_max_z ? t_max_x : t_max_z;
		if (best <= t_next || t_next > max_dist) {
			break;
		}
		if (t_max_x < t_max_z) {
			cx += step_x;
			t_max_x += t_delta_x;
		} else {
			cz += step_z;
			t_max_z += t_delta_z;
		}
	}
	return best;
}

// Collision.collide_capsule: deepest contact between a capsule (core P0-P1, radius R)
// and the one-sided walls in the grid cells it overlaps.
bool collide_capsule(const Track &track, double p0x, double p0z, double p1x, double p1z, double R, Contact &out,
		double max_behind) {
	const double cell = track.cell;
	const double min_x = track.min_x;
	const double min_z = track.min_z;
	const int cols = track.cols;
	const int rows = track.rows;
	const double *seg_d = track.seg_d.data();
	const int32_t *cell_start = track.cell_start.data();
	const int32_t *cell_segs = track.cell_segs.data();
	const int32_t *seg_cell = track.seg_cell.data();
	const double *inward = track.inward.data();
	double x0 = minf(p0x, p1x) - R;
	double x1 = maxf(p0x, p1x) + R;
	double z0 = minf(p0z, p1z) - R;
	double z1 = maxf(p0z, p1z) + R;
	int c0 = maxi(0, (int)std::floor((x0 - min_x) / cell));
	int c1 = mini(cols - 1, (int)std::floor((x1 - min_x) / cell));
	int r0 = maxi(0, (int)std::floor((z0 - min_z) / cell));
	int r1 = mini(rows - 1, (int)std::floor((z1 - min_z) / cell));
	double best_depth = 0.0;
	bool found = false;
	double ux = p1x - p0x;
	double uz = p1z - p0z;
	double uu = ux * ux + uz * uz;
	if (uu == 0.0) {
		uu = 1e-9;
	}

	for (int r = r0; r <= r1; r++) {
		for (int c = c0; c <= c1; c++) {
			int ci = r * cols + c;
			int end = cell_start[ci + 1];
			for (int k = cell_start[ci]; k < end; k++) {
				int s = cell_segs[k];
				// each segment once: in the first cell of the query that lists it
				if (c != maxi(c0, seg_cell[s * 2]) || r != maxi(r0, seg_cell[s * 2 + 1])) {
					continue;
				}
				int o = s * 4;
				double ax = seg_d[o];
				double az = seg_d[o + 1];
				double ex = seg_d[o + 2];
				double ez = seg_d[o + 3];
				double bx = ax + ex;
				double bz = az + ez;
				// quick reject: segment bounding box vs capsule bounding box
				if ((ax < x0 && bx < x0) || (ax > x1 && bx > x1) || (az < z0 && bz < z0) || (az > z1 && bz > z1)) {
					continue;
				}
				double mx = inward[s * 2];
				double mz = inward[s * 2 + 1];
				double ee = ex * ex + ez * ez;
				if (ee == 0.0) {
					ee = 1e-9;
				}
				// signed distances of the core ends to the wall line (+ = road side)
				double s0 = (p0x - ax) * mx + (p0z - az) * mz;
				double s1 = (p1x - ax) * mx + (p1z - az) * mz;
				double depth;
				double n_x;
				double n_z;
				double min_s = s0 < s1 ? s0 : s1;
				if (min_s < 0.0) {
					// Some of the core is behind the wall line: inside the wall's span?
					if (min_s < -max_behind) {
						continue;
					}
					double qx = s0 < s1 ? p0x : p1x;
					double qz = s0 < s1 ? p0z : p1z;
					double tc;
					if (s0 * s1 < 0.0) {
						double f = s0 / (s0 - s1);
						tc = ((p0x + ux * f - ax) * ex + (p0z + uz * f - az) * ez) / ee;
					} else {
						tc = ((qx - ax) * ex + (qz - az) * ez) / ee;
					}
					if (!(tc < 0.0 || tc > 1.0)) {
						depth = R - min_s;
						if (depth > best_depth) {
							best_depth = depth;
							found = true;
							out.depth = depth;
							out.nx = mx;
							out.nz = mz;
							out.px = qx - mx * R;
							out.pz = qz - mz * R;
							out.seg = s;
						}
						continue;
					}
					// beyond the wall's ends: treat as an ordinary distance test below
				}
				// Closest points between the two segments: at an endpoint of one of them.
				double bd = INFINITY;
				double bcx = 0.0, bcz = 0.0, bwx = 0.0, bwz = 0.0;
				// core ends against the wall segment
				double t = ((p0x - ax) * ex + (p0z - az) * ez) / ee;
				t = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
				double wx = ax + ex * t;
				double wz = az + ez * t;
				double d = (p0x - wx) * (p0x - wx) + (p0z - wz) * (p0z - wz);
				if (d < bd) {
					bd = d; bcx = p0x; bcz = p0z; bwx = wx; bwz = wz;
				}
				t = ((p1x - ax) * ex + (p1z - az) * ez) / ee;
				t = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
				wx = ax + ex * t;
				wz = az + ez * t;
				d = (p1x - wx) * (p1x - wx) + (p1z - wz) * (p1z - wz);
				if (d < bd) {
					bd = d; bcx = p1x; bcz = p1z; bwx = wx; bwz = wz;
				}
				// wall ends against the core
				t = ((ax - p0x) * ux + (az - p0z) * uz) / uu;
				t = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
				double cx = p0x + ux * t;
				double cz = p0z + uz * t;
				d = (cx - ax) * (cx - ax) + (cz - az) * (cz - az);
				if (d < bd) {
					bd = d; bcx = cx; bcz = cz; bwx = ax; bwz = az;
				}
				t = ((bx - p0x) * ux + (bz - p0z) * uz) / uu;
				t = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
				cx = p0x + ux * t;
				cz = p0z + uz * t;
				d = (cx - bx) * (cx - bx) + (cz - bz) * (cz - bz);
				if (d < bd) {
					bd = d; bcx = cx; bcz = cz; bwx = bx; bwz = bz;
				}
				if (bd >= R * R) {
					continue;
				}
				double dist = std::sqrt(bd);
				if (dist > 1e-6) {
					n_x = (bcx - bwx) / dist;
					n_z = (bcz - bwz) / dist;
					// never push towards the back of the wall
					if (n_x * mx + n_z * mz < 0.0) {
						n_x = mx;
						n_z = mz;
					}
				} else {
					n_x = mx;
					n_z = mz;
				}
				depth = R - dist;
				if (depth > best_depth) {
					best_depth = depth;
					found = true;
					out.depth = depth;
					out.nx = n_x;
					out.nz = n_z;
					out.px = bcx - n_x * R;
					out.pz = bcz - n_z * R;
					out.seg = s;
				}
			}
		}
	}
	if (!found) {
		out.depth = 0.0;
	}
	return found;
}

// ===========================================================================
// car.gd
// ===========================================================================

namespace {

// Car._road_attitude: pitch/roll of the road surface under the car (into att_pitch / att_roll).
void road_attitude(CarState &c, const Track &track, const Loc &loc) {
	int i = loc.idx;
	int j = track.closed ? (i + 1) % track.N : mini(i + 1, track.count - 1);
	const double *ps = track.phys_slope.data();
	double slope_t = ps[i] + (ps[j] - ps[i]) * loc.t;
	double tb = std::tan(loc.bank);
	double nx = loc.nx;
	double nz = loc.nz;
	double tx = -nz;
	double tz = nx;
	double gx = slope_t * tx - tb * nx; // height gradient
	double gz = slope_t * tz - tb * nz;
	double fx = std::sin(c.yaw);
	double fz = std::cos(c.yaw);
	c.att_pitch = std::atan(gx * fx + gz * fz); // uphill ahead -> nose up
	c.att_roll = std::atan(gx * fz - gz * fx); // ground rising to the left -> left side up
}

// Car._axle_mix: blend of the surfaces at fractional sample p (into c.mx_*).
void axle_mix(CarState &c, const Spec &P, const Track &track, double p) {
	int n = track.count;
	int k;
	double f;
	if (track.closed) {
		double kf = std::floor(p);
		f = p - kf;
		k = posmod((int)kf, track.N);
	} else if (p <= 0.0) {
		k = 0;
		f = 0.0;
	} else if (p >= n - 1) {
		k = n - 2;
		f = 1.0;
	} else {
		double kf2 = std::floor(p);
		k = (int)kf2;
		f = p - kf2;
	}
	int j = track.closed ? (k + 1) % track.N : k + 1;
	int S = track.surf_n;
	const double *W = track.surf_w.data();
	double g = 0.0;
	double st = 0.0;
	double r = 0.0;
	double e = 0.0;
	double a0 = 0.0;
	for (int s = 0; s < S; s++) {
		double wa = W[k * S + s];
		double w = wa + (W[j * S + s] - wa) * f;
		if (s == 0) {
			a0 = w;
		}
		g += w * P.surf_grip[s];
		st += w * track.surf_stiff[s];
		r += w * track.surf_roll[s];
		e += w * track.surf_esc[s];
	}
	c.mx_pure = a0 == 1.0;
	c.mx_g = g;
	c.mx_k = st;
	c.mx_r = r;
	c.mx_e = e;
}

// Car._surface_mix: the surface blend under both axles (front cg_to_front ahead, rear cg_to_rear behind).
void surface_mix(CarState &c, const Spec &P, const Track &track) {
	c.env_loose = false;
	if (track.surf_w.empty()) {
		return;
	}
	double cos_t = std::sin(c.yaw) * -c.nz + std::cos(c.yaw) * c.nx; // heading against the road's tangent
	double p0 = c.idx + c.t;
	axle_mix(c, P, track, p0 + (P.cg_to_front * cos_t) / track.seg_len);
	bool pure_f = c.mx_pure;
	c.env_gf = c.mx_g;
	c.env_kf = c.mx_k;
	c.env_rf = c.mx_r;
	double esc_f = c.mx_e;
	axle_mix(c, P, track, p0 - (P.cg_to_rear * cos_t) / track.seg_len);
	if (pure_f && c.mx_pure) {
		return;
	}
	c.env_loose = true;
	c.env_gr = c.mx_g;
	c.env_kr = c.mx_k;
	c.env_rr = c.mx_r;
	c.env_sesc = (esc_f + c.mx_e) * 0.5;
	c.env_pk = std::atan((P.peak_slip / c.env_kf) * P.steer_slip_gain);
}

// Car._surface_env: gravity along the road and the normal load (once per step).
void surface_env(CarState &c, const Spec &P, const Track &track) {
	surface_mix(c, P, track);
	int i = c.idx;
	int j = track.closed ? (i + 1) % track.N : mini(i + 1, track.count - 1);
	double t = c.t;
	const double *ps = track.phys_slope.data();
	double slope_t = ps[i] + (ps[j] - ps[i]) * t;
	double tb = std::tan(c.bank);
	// gradient of the road height on the x/z plane: along the tangent + across (bank)
	double nx = c.nx; // left normal
	double nz = c.nz;
	double tx = -nz; // tangent
	double tz = nx;
	double gx = slope_t * tx - tb * nx;
	double gz = slope_t * tz - tb * nz;
	double g2 = gx * gx + gz * gz;
	double inv_s = 1.0 / std::sqrt(1.0 + g2); // cos of the surface tilt
	c.env_gx = -G * gx * inv_s;
	c.env_gz = -G * gz * inv_s;
	if (!c.grounded) {
		c.env_gn = 0.0;
		return;
	}
	// normal acceleration: g cos + (lateral acceleration into the slope) sin + vertical curvature
	double fx = std::sin(c.yaw);
	double fz = std::cos(c.yaw);
	double u = c.vx * fx + c.vz * fz;
	double a_lat = u * c.yaw_rate; // centripetal, towards the car's left
	double lx = fz;
	double lz = -fx;
	double gl = std::sqrt(g2);
	double into = 0.0;
	if (gl > 1e-4) {
		into = -a_lat * (lx * gx + lz * gz) / gl; // acceleration towards down-slope
	}
	double sin_s = gl * inv_s;
	const double *pk = track.phys_kv.data();
	double kv_t = pk[i] + (pk[j] - pk[i]) * t;
	double vt = c.vx * tx + c.vz * tz;
	double gn = G * inv_s + into * sin_s + kv_t * vt * vt;
	c.env_gn = gn < 0.0 ? 0.0 : (gn > 2.2 * G ? 2.2 * G : gn);
}

// Car._drivetrain: gearbox, engine, brakes, handbrake lever, ESC gating (once per step).
void drivetrain(CarState &c, const Spec &P, double thr, bool hb, double dt) {
	double fx = std::sin(c.yaw);
	double fz = std::cos(c.yaw);
	double u = c.vx * fx + c.vz * fz;
	double wheel_rpm = (std::fabs(u) / P.wheel_radius) * (30.0 / PI);

	// Direction logic: brake to a stop first, then reverse (and the other way round).
	double drive = 0.0;
	double brake = 0.0;
	if (c.gear_ == -1) {
		if (thr > 0.02 && u > -1.0) {
			c.gear_ = 1;
		}
	} else if (thr < -0.02 && u < 1.0) {
		c.gear_ = -1;
	}
	if (c.gear_ >= 1 && thr < -0.02) {
		brake = -thr;
	} else if (c.gear_ == -1 && thr > 0.02) {
		brake = thr;
	}

	if (c.gear_ >= 1) {
		// automatic gearbox
		if (c.shift > 0.0) {
			c.shift -= dt;
		}
		double fd = P.final_drive;
		const std::vector<double> &gears = P.gears;
		double rpm_w = wheel_rpm * gears[c.gear_ - 1] * fd;
		if (c.shift <= 0.0 && c.grounded) {
			if (rpm_w > P.upshift_rpm && c.gear_ < (int)gears.size() && thr > 0.02) {
				c.gear_ += 1;
				c.shift = P.shift_time;
			} else if (c.gear_ > 1 && rpm_w < P.downshift_rpm && wheel_rpm * gears[c.gear_ - 2] * fd < P.upshift_rpm - 700.0) {
				c.gear_ -= 1;
				c.shift = P.shift_time * 0.5;
			}
			rpm_w = wheel_rpm * gears[c.gear_ - 1] * fd;
		}
		double ratio = gears[c.gear_ - 1] * fd;
		// clutch slip when pulling away in first gear
		double rpm_eng = rpm_w;
		if (c.gear_ == 1 && thr > 0.02) {
			rpm_eng = maxf(rpm_w, P.idle_rpm + (P.launch_rpm - P.idle_rpm) * thr);
		}
		rpm_eng = maxf(P.idle_rpm, rpm_eng);
		if (thr > 0.02) {
			if (c.shift <= 0.0 && rpm_w < P.redline) {
				drive = (P.engine_torque(rpm_eng) * thr * ratio * P.efficiency) / P.wheel_radius;
			}
		} else if (c.grounded && rpm_w > P.idle_rpm * 1.2) {
			// engine braking (friction + pumping torque grows with rpm)
			drive = -((25.0 + 0.009 * rpm_w) * ratio) / P.wheel_radius * signf(u);
		}
		c.gear = (c.speed < 0.3 && thr <= 0.02) ? 0 : c.gear_;
		double rpm_target = c.grounded ? rpm_eng : maxf(rpm_eng, P.idle_rpm + (P.redline - P.idle_rpm) * maxf(0.0, thr));
		c.rpm += (minf(P.redline, rpm_target) - c.rpm) * minf(1.0, dt * 18.0);
	} else {
		// reverse gear
		double ratio = P.reverse_ratio * P.final_drive;
		double rpm_w = wheel_rpm * ratio;
		double rpm_eng = maxf(rpm_w, P.idle_rpm + 2500.0 * maxf(0.0, -thr));
		if (thr < -0.02 && u > -P.max_reverse) {
			drive = -(P.engine_torque(rpm_eng) * -thr * ratio * P.efficiency * 0.6) / P.wheel_radius;
		}
		c.gear = -1;
		c.rpm += (minf(P.redline, rpm_eng) - c.rpm) * minf(1.0, dt * 18.0);
	}
	c.env_drive = drive;
	c.env_brake = brake * P.brake_force;
	// handbrake lever: ramps in (a keyboard tap gives a short, partial pull)
	if (hb) {
		c.hb = minf(1.0, c.hb + P.handbrake_rate * dt);
	} else {
		c.hb = maxf(0.0, c.hb - 2.0 * P.handbrake_rate * dt);
	}
	c.env_hb = c.hb;
	// stability control: off while the handbrake is used and for a moment after, then fades back in
	if (c.hb > 0.02) {
		c.esc_off = P.esc_handbrake_hold;
	} else if (c.esc_off > 0.0) {
		c.esc_off = maxf(0.0, c.esc_off - dt);
	}
	c.env_esc = P.esc * (c.esc_off <= 0.0 ? 1.0 : (c.esc_off >= 0.5 ? 0.0 : 1.0 - c.esc_off / 0.5));
	// ... and while scraping a wall (the wall, not the tyres, sets the rotation then)
	int wt = c.wall_t;
	if (wt < 45) {
		c.env_esc *= wt < 15 ? 0.0 : (wt - 15) / 30.0;
	}
	c.braking = brake > 0.02 || (c.hb > 0.1 && c.speed > 1.0);
}

// Car._mu_at
inline double mu_at(const Spec &P, double load, double load0) {
	double r = load / load0;
	double k = 1.0 - P.load_sensitivity * (r - 1.0);
	return P.mu * (k < 0.6 ? 0.6 : (k > 1.2 ? 1.2 : k));
}

// Car._secant: magic formula force ratio divided by slip (secant stiffness), finite at 0.
inline double secant(const Spec &P, double xs) {
	double ax = xs < 0.0 ? -xs : xs;
	if (ax < 1e-4) {
		return P.pac_slope0;
	}
	return P.pacejka(ax) / ax;
}

// Car._planar_step: bicycle model, one sub-step.
void planar_step(CarState &c, const Spec &P, double h) {
	double L = P.wheelbase;
	double m = P.mass;
	double iz = P.inertia;
	double a = P.cg_to_front;
	double b = P.cg_to_rear;
	double yaw0 = c.yaw;
	double fx = std::sin(yaw0);
	double fz = std::cos(yaw0);
	double lx = fz;
	double lz = -fx;
	double u = c.vx * fx + c.vz * fz;
	double v = c.vx * lx + c.vz * lz;
	double r = c.yaw_rate;
	double spd = std::sqrt(u * u + v * v);

	// External forces in the car frame: aero drag, gravity along the road.
	double drag_k = P.drag * spd;
	double fx_e = -drag_k * u + m * (c.env_gx * fx + c.env_gz * fz);
	double fy_e = -drag_k * v + m * (c.env_gx * lx + c.env_gz * lz);

	if (!c.grounded) {
		// In the air: no tyre forces; the take-off yaw rate slowly damped, steering adds a little.
		double r0 = (r - c.air_rs) * std::exp(-P.air_yaw_damp * h);
		c.air_rs += (c.sc * P.air_steer - c.air_rs) * (1.0 - std::exp(-h / P.air_steer_tau));
		c.yaw_rate = r0 + c.air_rs;
		c.vx += ((fx_e * fx + fy_e * lx) / m) * h;
		c.vz += ((fx_e * fz + fy_e * lz) / m) * h;
		c.yaw = yaw0 + c.yaw_rate * h;
		c.x += c.vx * h;
		c.z += c.vz * h;
		c.steer_angle = c.sc * P.steer_lock * 0.5;
		c.slip_f = 0.0;
		c.slip_r = 0.0;
		c.tc_cut = 0.0;
		c.ax += (0.0 - c.ax) * minf(1.0, h * 10.0);
		c.ay = 0.0;
		return;
	}

	// --- normal loads ---
	double down = P.downforce * spd * spd;
	double w = m * c.env_gn;
	double tr = (m * c.ax * P.cg_height) / L; // longitudinal weight transfer
	double load_f = (w * b) / L + down * P.aero_front - tr;
	double load_r = (w * a) / L + down * (1.0 - P.aero_front) + tr;
	double min_load = 0.03 * w;
	if (load_f < min_load) {
		load_f = min_load;
	}
	if (load_r < min_load) {
		load_r = min_load;
	}
	double load_f0 = (m * G * b) / L;
	double load_r0 = (m * G * a) / L;
	double cap_f = mu_at(P, load_f, load_f0) * load_f;
	double cap_r = mu_at(P, load_r, load_r0) * load_r;
	bool loose = c.env_loose; // dirt / snow under an axle
	if (loose) {
		cap_f *= c.env_gf;
		cap_r *= c.env_gr;
	}

	// rolling resistance (opposes u, never reverses it)
	double sgn_u = u > 0.0 ? 1.0 : (u < 0.0 ? -1.0 : 0.0);
	double stop_f = (m * std::fabs(u)) / h; // force that would stop the car this sub-step
	double roll_f = P.roll_resist * (load_f + load_r);
	if (loose) {
		roll_f = P.roll_resist * (load_f * c.env_rf + load_r * c.env_rr);
	}
	if (roll_f > stop_f * 0.5) {
		roll_f = stop_f * 0.5;
	}
	fx_e -= roll_f * sgn_u;

	// --- longitudinal tyre forces ---
	double brake = c.env_brake;
	if (brake > stop_f * 0.9) {
		brake = stop_f * 0.9;
	}
	double hb = c.env_hb; // handbrake lever 0..1
	double drive_f = c.env_drive * P.drive_front;
	double drive_r = c.env_drive - drive_f;
	// Rear: cornering has priority (EBD / traction control), unless the handbrake is on.
	double fx_r = 0.0;
	double fy_cap_r = cap_r;
	double tc_cut = 0.0;
	if (hb > 0.0) {
		// Handbrake: a strong rear brake that bypasses the electronics; the drive the rear can't take goes to the front.
		drive_f += drive_r * hb;
		drive_r *= 1.0 - hb;
		double hbk = u < 25.0 ? P.handbrake : (u > 55.0 ? P.handbrake_fast : P.handbrake + ((P.handbrake_fast - P.handbrake) * (u - 25.0)) / 30.0);
		double fb = hb * hbk * cap_r;
		if (fb > stop_f * 0.5) {
			fb = stop_f * 0.5;
		}
		fx_r = drive_r - fb * sgn_u - brake * (1.0 - P.brake_front) * sgn_u;
		if (fx_r > 0.97 * cap_r) {
			fx_r = 0.97 * cap_r;
		} else if (fx_r < -0.97 * cap_r) {
			fx_r = -0.97 * cap_r;
		}
		fy_cap_r = std::sqrt(maxf(0.0, cap_r * cap_r - fx_r * fx_r));
	} else {
		double fy_prev = std::fabs(c.fyr) < cap_r ? std::fabs(c.fyr) : cap_r;
		double long_cap = 0.97 * std::sqrt(cap_r * cap_r - fy_prev * fy_prev);
		double want = drive_r - brake * (1.0 - P.brake_front) * sgn_u;
		bool sliding = std::fabs(c.slip_r) > P.peak_slip * P.slide_drive;
		if (sliding && want > 0.0) {
			// rear already sliding: the driven wheels spin up and keep it loose (power slide)
			if (want > 0.97 * cap_r) {
				want = 0.97 * cap_r;
			}
			fy_cap_r = std::sqrt(maxf(0.0, cap_r * cap_r - want * want));
		} else if (want > long_cap) {
			// traction control: cut what the rear can't use without losing cornering grip
			if (drive_r > 0.0) {
				tc_cut = maxf(tc_cut, (want - long_cap) / (std::fabs(c.env_drive) + 1.0));
			}
			want = long_cap;
		} else if (want < -long_cap) {
			want = -long_cap;
		}
		fx_r = want;
	}
	// Front: driving/braking has priority, cornering gets what is left.
	double fx_f = drive_f - brake * P.brake_front * sgn_u;
	double fx_cap_f = 0.97 * cap_f;
	if (fx_f > fx_cap_f) {
		tc_cut = maxf(tc_cut, (fx_f - fx_cap_f) / (std::fabs(c.env_drive) + 1.0));
		fx_f = fx_cap_f;
	} else if (fx_f < -fx_cap_f) {
		fx_f = -fx_cap_f;
	}
	double fy_cap_f = std::sqrt(maxf(0.0, cap_f * cap_f - fx_f * fx_f));
	c.tc_cut = tc_cut;

	// --- steering angle: speed-sensitive lock + countersteer assist when the rear slides ---
	double sc = c.sc;
	double delta = 0.0;
	double delta_cmd = 0.0;
	if (u > 0.5) {
		double wf = (u - P.steer_slow_speed) / (P.steer_fast_speed - P.steer_slow_speed);
		wf = wf <= 0.0 ? 0.0 : (wf >= 1.0 ? 1.0 : wf * wf * (3.0 - 2.0 * wf));
		double lock;
		if (loose) {
			// the same lock for the grip and the tyre this surface leaves
			lock = std::atan((L * P.steer_ref_accel * c.env_gf) / (u * u)) + c.env_pk + (P.steer_extra_fast / c.env_kf - c.env_pk) * wf;
		} else {
			lock = std::atan((L * P.steer_ref_accel) / (u * u)) + P.peak_steer + (P.steer_extra_fast - P.peak_steer) * wf;
		}
		delta = sc * (lock < P.steer_lock ? lock : P.steer_lock);
		delta_cmd = delta;
		if (u > 3.0) {
			double slide_r = std::atan((v - b * r) / u); // rear slip angle
			double ab = slide_r < 0.0 ? -slide_r : slide_r;
			if (ab > P.assist_from) {
				double aw = (ab - P.assist_from) / (P.assist_full - P.assist_from);
				aw = aw > 1.0 ? 1.0 : aw * aw * (3.0 - 2.0 * aw);
				double fade = u < 8.0 ? (u - 3.0) / 5.0 : 1.0;
				delta += slide_r * aw * fade * P.steer_assist;
			}
		}
	} else {
		double rev = u < -0.5 ? minf(1.0, 6.0 / -u) : 1.0;
		delta = sc * P.steer_lock * rev;
	}
	if (delta > P.steer_lock) {
		delta = P.steer_lock;
	} else if (delta < -P.steer_lock) {
		delta = -P.steer_lock;
	}
	c.steer_angle = delta;
	double cs = std::cos(delta);
	double s = std::sin(delta);

	// --- lateral tyre stiffness (secant of the magic formula) ---
	double vfa = v + a * r;
	double uw = u * cs + vfa * s;
	double vw = -u * s + vfa * cs;
	double uf = std::fabs(uw) > U_MIN ? std::fabs(uw) : U_MIN;
	double x_f = vw / uf;
	double k_f = (fy_cap_f * secant(P, x_f)) / uf; // N per (m/s) of lateral wheel velocity
	double vr = v - b * r;
	double ur = std::fabs(u) > U_MIN ? std::fabs(u) : U_MIN;
	double x_r = vr / ur;
	double k_r = (fy_cap_r * secant(P, x_r)) / ur;
	if (loose) {
		// a softer tyre: the force at slip x is the asphalt force at x * stiffness
		k_f = (fy_cap_f * (c.env_kf * secant(P, x_f * c.env_kf))) / uf;
		k_r = (fy_cap_r * (c.env_kr * secant(P, x_r * c.env_kr))) / ur;
	}
	c.slip_f = x_f;
	c.slip_r = x_r;

	// --- semi-implicit solve for the new sideways speed v' and yaw rate r' ---
	double kfc2 = k_f * cs * cs;
	double hm = h / m;
	double hi = h / iz;
	double a11 = 1.0 + hm * (kfc2 + k_r);
	double a12 = hm * (kfc2 * a - k_r * b) + h * u;
	double b1 = v + hm * (fx_f * s + k_f * cs * u * s + fy_e);
	double a21 = hi * (a * kfc2 - b * k_r);
	double a22 = 1.0 + hi * (a * a * kfc2 + b * b * k_r);
	double b2 = r + hi * (a * (fx_f * s + k_f * cs * u * s));
	double det = a11 * a22 - a12 * a21;
	double v1 = (b1 * a22 - a12 * b2) / det;
	double r1 = (a11 * b2 - a21 * b1) / det;

	// tyre forces at the solved state, clamped to their grip
	double fy_f = k_f * (u * s - cs * (v1 + a * r1));
	if (fy_f > fy_cap_f) {
		fy_f = fy_cap_f;
	} else if (fy_f < -fy_cap_f) {
		fy_f = -fy_cap_f;
	}
	double fy_r = -k_r * (v1 - b * r1);
	if (fy_r > fy_cap_r) {
		fy_r = fy_cap_r;
	} else if (fy_r < -fy_cap_r) {
		fy_r = -fy_cap_r;
	}
	c.fyr = fy_r;

	// body-frame totals
	double f_x = fx_f * cs - fy_f * s + fx_r + fx_e;
	double f_y = fx_f * s + fy_f * cs + fy_r + fy_e;
	double mz = a * (fx_f * s + fy_f * cs) - b * fy_r;

	// integrate (world frame for velocity, so turning never creates speed)
	double r_n = r + (mz / iz) * h;
	double vx_n = c.vx + ((f_x * fx + f_y * lx) / m) * h;
	double vz_n = c.vz + ((f_x * fz + f_y * lz) / m) * h;

	// --- stability control (ESC) ---
	if (c.env_esc > 0.0 && u > P.esc_from) {
		double r_lim = (fy_cap_f + fy_cap_r) / (m * u); // yaw rate of a grip-limited steady turn
		double r_ref = (u * std::tan(delta_cmd)) / L;
		if (r_ref > r_lim) {
			r_ref = r_lim;
		} else if (r_ref < -r_lim) {
			r_ref = -r_lim;
		}
		double e = r_n - r_ref;
		double ae = (e < 0.0 ? -e : e) - P.esc_deadband;
		if (ae > 0.0) {
			bool under = e * r_ref < 0.0 && r_n * r_ref > 0.0;
			double fade_in = u < P.esc_from + 4.0 ? (u - P.esc_from) / 4.0 : 1.0;
			double mom = iz * P.esc_gain * ae;
			double m_max = P.esc_moment * (under ? P.esc_under : 1.0);
			if (loose) {
				m_max *= c.env_sesc;
			}
			if (mom > m_max) {
				mom = m_max;
			}
			mom *= c.env_esc * fade_in;
			r_n -= (e > 0.0 ? mom : -mom) * (h / iz);
			// the single-wheel braking that makes the moment also slows the car a little
			double sp = std::sqrt(vx_n * vx_n + vz_n * vz_n);
			if (sp > 1.0) {
				double dv = ((mom / 0.8) * P.esc_slow * h) / m;
				if (dv > sp * 0.5) {
					dv = sp * 0.5;
				}
				vx_n -= (vx_n / sp) * dv;
				vz_n -= (vz_n / sp) * dv;
			}
		}
	}
	c.yaw_rate = r_n;
	c.vx = vx_n;
	c.vz = vz_n;
	c.yaw = yaw0 + c.yaw_rate * h;
	c.x += c.vx * h;
	c.z += c.vz * h;
	// filtered accelerations for weight transfer and body attitude (suspension lag)
	double kf = minf(1.0, h * 12.0);
	c.ax += ((f_x - fx_e + (-drag_k * u)) / m - c.ax) * kf;
	c.ay += (f_y / m + 0.0 - c.ay) * kf;
}

// Car._wall_contact: remember the latest wall contact for effects.
inline void wall_contact(CarState &c, double px, double pz, double nx, double nz) {
	c.wall_x = px;
	c.wall_z = pz;
	c.wall_nx = nx;
	c.wall_nz = nz;
	c.wall_now = true;
}

// Car._rub: the sliding speed along a wall fades by wall_rub per second, building up over wall_rub_build s.
void rub(CarState &c, const Spec &P, double h) {
	double nx = c.wall_nx;
	double nz = c.wall_nz;
	double vn = c.vx * nx + c.vz * nz;
	double tvx = c.vx - vn * nx;
	double tvz = c.vz - vn * nz;
	c.rub_t = minf(P.wall_rub_build, c.rub_t + h);
	double k = P.wall_rub * h * (P.wall_rub_build > 0.0 ? c.rub_t / P.wall_rub_build : 1.0);
	c.vx -= tvx * k;
	c.vz -= tvz * k;
}

// Car._stop_rotation: remove part of the rotation that swings the contact point into the wall.
inline void stop_rotation(CarState &c, const Spec &P, double dx, double dz, double nx, double nz) {
	double kn = dz * nx - dx * nz; // normal velocity of the contact point per unit yaw rate
	double wn = c.yaw_rate * kn;
	if (wn < 0.0 && std::fabs(kn) > 0.05) {
		c.yaw_rate -= (P.wall_yaw_stop * wn) / kn;
	}
}

// Car._impulse: velocity response at a wall contact.
void impulse(CarState &c, const Spec &P, double dx, double dz, double nx, double nz, double h) {
	double vn = c.vx * nx + c.vz * nz;
	if (vn < 0.0) {
		c.wall_impact -= vn;
		// almost no bounce, and never more than max_rebound m/s
		double reb = -vn * P.wall_restitution;
		double jn = -vn + (reb < P.max_rebound ? reb : P.max_rebound);
		c.vx += nx * jn;
		c.vz += nz * jn;
		double vn2 = c.vx * nx + c.vz * nz;
		double tvx = c.vx - vn2 * nx;
		double tvz = c.vz - vn2 * nz;
		double vt = std::sqrt(tvx * tvx + tvz * tvz);
		if (vt > 1e-6) {
			double dv = (P.wall_friction + P.wall_crush * jn) * jn;
			// slow sliding: the friction fades out, so a car pressed nose-in slides off
			if (vt < P.wall_slide) {
				dv *= vt / P.wall_slide;
			}
			if (dv > vt) {
				dv = vt;
			}
			c.vx -= (tvx / vt) * dv;
			c.vz -= (tvz / vt) * dv;
		}
	}
	// rotation pushing the contact point into the wall: take it away (over a few sub-steps)
	stop_rotation(c, P, dx, dz, nx, nz);
	// gentle alignment with the wall, in the direction the car is sliding
	double fx = std::sin(c.yaw);
	double fz = std::cos(c.yaw);
	double u = c.vx * fx + c.vz * fz;
	if (std::fabs(u) > 2.0) {
		double dir = u > 0.0 ? 1.0 : -1.0; // the end of the car that leads
		double fn = (fx * nx + fz * nz) * dir; // < 0: leading end points into the wall
		if (fn < 0.0) {
			double ln = (fz * nx - fx * nz) * dir; // turning left lifts the nose off the wall if > 0
			double ang = std::asin(minf(1.0, -fn)); // angle between heading and wall
			double target = (ln >= 0.0 ? 1.0 : -1.0) * dir * minf(P.wall_align, ang * P.wall_align_gain);
			if (c.yaw_rate * target < target * target) {
				double mm = P.wall_align_accel * h;
				double d = target - c.yaw_rate;
				c.yaw_rate += d > mm ? mm : (d < -mm ? -mm : d);
			}
		}
	}
}

// Car._walls: wall collisions for one sub-step. Returns true with the located position in
// c.loc, or false when the safety net moved the car (the GDScript returns null then).
bool walls(CarState &c, const Spec &P, const Track &track, double h) {
	double R = P.radius;
	double core = P.core;
	// Broad phase: far from both walls and from the ends of a sprint track -> nothing to do.
	int hint = c.idx;
	Loc &loc = locate_near(track, c.x, c.z, hint, c.loc);
	c.idx = loc.idx;
	c.t = loc.t;
	c.nx = loc.nx;
	c.nz = loc.nz;
	c.hw = loc.hw;
	bool near_end = !track.closed && (loc.idx < 4 || loc.idx > track.seg_count - 5);
	double reach = P.half_length + 1.5;
	if (!near_end && std::fabs(loc.lat) < loc.hw - reach) {
		return true;
	}

	// Flying higher than the barriers: only kept inside the barrier line.
	if (!c.grounded && c.y - loc.ground_y > P.wall_height && !near_end) {
		double ax = std::sin(c.yaw) * loc.nx + std::cos(c.yaw) * loc.nz; // how far the capsule's axis points across the road
		double lim = loc.hw - R - core * (ax < 0.0 ? -ax : ax);
		if (std::fabs(loc.lat) <= lim) {
			return true;
		}
		double sgn = loc.lat > 0.0 ? 1.0 : -1.0;
		double push = std::fabs(loc.lat) - lim;
		c.x -= loc.nx * push * sgn;
		c.z -= loc.nz * push * sgn;
		double vn = (c.vx * loc.nx + c.vz * loc.nz) * sgn;
		if (vn > 0.0) {
			c.vx -= loc.nx * vn * sgn;
			c.vz -= loc.nz * vn * sgn;
		}
		locate_near(track, c.x, c.z, c.idx, c.loc);
		return true;
	}

	Contact &ct = c.contact;
	bool touched = false;
	for (int iter = 0; iter < 4; iter++) {
		double fx = std::sin(c.yaw);
		double fz = std::cos(c.yaw);
		double p0x = c.x - fx * core;
		double p0z = c.z - fz * core;
		double p1x = c.x + fx * core;
		double p1z = c.z + fz * core;
		// a thin skin keeps the contact (and hit_wall) steady while scraping along a wall
		if (!collide_capsule(track, p0x, p0z, p1x, p1z, R + SKIN, ct)) {
			// contact hysteresis: a car that touched in the last few steps still counts as scraping
			if (iter == 0 && c.wall_t < P.wall_latch_steps && collide_capsule(track, p0x, p0z, p1x, p1z, R + P.wall_latch, ct)) {
				c.hit_wall = true;
				touched = true;
				wall_contact(c, ct.px, ct.pz, ct.nx, ct.nz);
				stop_rotation(c, P, ct.px - c.x, ct.pz - c.z, ct.nx, ct.nz);
			}
			break;
		}
		touched = true;
		c.hit_wall = true;
		c.wall_t = -1;
		double nx = ct.nx;
		double nz = ct.nz;
		double depth = ct.depth - SKIN;
		ct.px += nx * SKIN;
		ct.pz += nz * SKIN;
		if (depth <= 1e-5) {
			// touching: only stop motion into the wall
			wall_contact(c, ct.px, ct.pz, nx, nz);
			if (c.vx * nx + c.vz * nz < 0.0) {
				impulse(c, P, ct.px - c.x, ct.pz - c.z, nx, nz, h);
			}
			break;
		}
		// push out (no velocity change from the push)
		c.x += nx * depth;
		c.z += nz * depth;
		// contact point relative to the centre (after the push)
		double dx = ct.px + nx * depth - c.x;
		double dz = ct.pz + nz * depth - c.z;
		wall_contact(c, c.x + dx, c.z + dz, nx, nz);
		impulse(c, P, dx, dz, nx, nz, h);
	}
	if (touched) {
		rub(c, P, h);
	}

	// Safety net: the centre must stay on the road whatever happens (a small bounded nudge).
	// (Untouched and on the same segment, the query above is still in c.loc.)
	Loc &l2 = (!touched && c.idx == hint) ? loc : locate_near(track, c.x, c.z, c.idx, c.loc);
	double lim2 = l2.hw - 0.3;
	if (std::fabs(l2.lat) > lim2) {
		double sgn = l2.lat > 0.0 ? 1.0 : -1.0;
		double push = std::fabs(l2.lat) - lim2;
		if (!(push < 0.5)) {
			push = 0.5;
		}
		c.x -= l2.nx * push * sgn;
		c.z -= l2.nz * push * sgn;
		double vn = (c.vx * l2.nx + c.vz * l2.nz) * sgn;
		if (vn > 0.0) {
			c.vx -= l2.nx * vn * sgn;
			c.vz -= l2.nz * vn * sgn;
			c.wall_impact += vn;
		}
		double gap = l2.hw - std::fabs(l2.lat) + push; // from the centre (after the nudge) out to the wall line
		wall_contact(c, c.x + l2.nx * gap * sgn, c.z + l2.nz * gap * sgn, -l2.nx * sgn, -l2.nz * sgn);
		c.hit_wall = true;
		c.wall_t = -1;
		return false;
	}
	return true;
}

// Car._road_height_at
double road_height_at(const Track &track, double p, double lat_at) {
	double kf = std::floor(p);
	double t = p - kf;
	int k = (int)kf;
	int n = track.count;
	if (track.closed) {
		k = ((k % track.N) + track.N) % track.N;
	} else if (k >= n - 1) {
		k = n - 2;
		t = 1.0;
	} else if (k < 0) {
		k = 0;
		t = 0.0;
	}
	int j = track.closed ? (k + 1) % track.N : k + 1;
	double py = track.py[k] + (track.py[j] - track.py[k]) * t;
	double bk = track.bank[k] + (track.bank[j] - track.bank[k]) * t;
	return py - lat_at * std::tan(bk);
}

// Car._vertical: glued to the road, real jumps only, damped landings.
void vertical(CarState &c, const Spec &P, const Track &track, const Loc &loc, double dt) {
	double g_y = loc.ground_y;
	double spd2 = c.vx * c.vx + c.vz * c.vz;
	double g_eff = P.gravity + (P.downforce * spd2) / P.mass;
	if (c.grounded) {
		double v_ground = (g_y - c.y) / dt; // vertical speed of the road under the car
		c.ground += dt;
		// Could the road be dropping away faster than the car can follow?
		int i = loc.idx;
		int j = track.closed ? (i + 1) % track.N : mini(i + 1, track.count - 1);
		const double *pk = track.phys_kv.data();
		double kv = pk[i] + (pk[j] - pk[i]) * loc.t;
		double tx = -loc.nz;
		double tz = loc.nx;
		double vt = c.vx * tx + c.vz * tz;
		bool take_off = false;
		if (kv * vt * vt < -g_eff && c.ground > 0.05 && std::fabs(vt) > 5.0) {
			// Confirm by flying the ballistic path forward against the actual road ahead.
			double v0 = v_ground;
			double max_sep = 0.0;
			double flight = 0.0;
			for (int k = 1; k < 37; k++) {
				double T = k * dt;
				double road = road_height_at(track, loc.prog + (vt * T) / track.seg_len, loc.lat);
				double sep = g_y + v0 * T - 0.5 * g_eff * T * T - road;
				if (sep < 0.0) {
					break;
				}
				flight = T;
				if (sep > max_sep) {
					max_sep = sep;
				}
			}
			take_off = max_sep > P.lift_separation && flight >= P.min_flight;
		}
		if (take_off) {
			c.grounded = false;
			c.air_time = 0.0;
			c.air_rs = 0.0;
			c.vy = v_ground;
			c.y = g_y;
		} else {
			c.y = g_y;
			c.vy = v_ground;
			c.air_time = 0.0;
		}
	} else {
		c.air_time += dt;
		c.y += c.vy * dt - 0.5 * g_eff * dt * dt; // exact ballistic step
		c.vy -= g_eff * dt;
		// Just after take-off the path skims the road: don't let rounding end the jump.
		if (c.air_time < 0.1 && c.y < g_y && c.y > g_y - 0.02) {
			c.y = g_y;
		} else if (c.y < g_y) {
			// Landing: the vertical speed relative to the road under the car.
			double slope_along = (road_height_at(track, loc.prog + 0.5, loc.lat) - road_height_at(track, loc.prog - 0.5, loc.lat)) / track.seg_len;
			double tx = -loc.nz;
			double tz = loc.nx;
			double vt = c.vx * tx + c.vz * tz;
			double v_road = slope_along * vt;
			double impact = v_road - c.vy; // > 0 when hitting the road
			if (impact > P.hard_landing) {
				double loss = minf(0.15, P.landing_loss * (impact - P.hard_landing));
				c.vx *= 1.0 - loss;
				c.vz *= 1.0 - loss;
			}
			c.pitch_v -= minf(0.6, 0.03 * impact); // nose dips as the suspension compresses
			c.y = g_y;
			c.vy = v_road;
			c.grounded = true;
			c.ground = 0.0;
		}
	}
	c.ground_y = g_y;
}

// Car._attitude: smoothed visual pitch / roll (a damped spring).
void attitude(CarState &c, const Track &track, const Loc &loc, double dt) {
	double tp;
	double tr;
	double w;
	if (c.grounded) {
		road_attitude(c, track, loc);
		// squat under acceleration (nose up), dive under braking; roll out of corners
		double ax = clampd(c.ax, -20.0, 20.0);
		double ay = clampd(c.forward_speed * c.yaw_rate, -25.0, 25.0);
		tp = c.att_pitch + 0.0032 * ax;
		tr = c.att_roll + 0.0035 * ay;
		w = 11.0;
	} else {
		double vh = maxf(4.0, c.speed);
		tp = clampd(std::atan2(c.vy, vh) * 0.6, -0.4, 0.4);
		tr = c.roll * 0.98;
		w = 3.0;
	}
	// critically-damped-ish spring (semi-implicit, stable at 60 Hz)
	double zeta = 0.8;
	c.pitch_v += (w * w * (tp - c.pitch) - 2.0 * zeta * w * c.pitch_v) * dt;
	c.roll_v += (w * w * (tr - c.roll) - 2.0 * zeta * w * c.roll_v) * dt;
	c.pitch += c.pitch_v * dt;
	c.roll += c.roll_v * dt;
}

} // namespace

// Car._init + Car.place(track, sample_idx) without a snapshot: a car standing on the
// sample, facing along the track, with a full nitro tank.
void car_init(CarState &car, const Spec &P, const Track &track, int sample_idx) {
	car = CarState();
	CarState &c = car;
	c.rpm = P.idle_rpm;
	c.env_gn = G;
	int i = maxi(0, mini(track.count - 1, sample_idx));
	c.x = track.px[i];
	c.z = track.pz[i];
	c.yaw = std::atan2(track.tx[i], track.tz[i]);
	c.vx = 0.0;
	c.vz = 0.0;
	c.vy = 0.0;
	c.idx = mini(i, track.seg_count - 1);
	c.laps = 0;
	Loc &loc = locate(track, c.x, c.z, c.idx, c.loc);
	c.idx = loc.idx;
	c.y = loc.ground_y;
	c.ground_y = loc.ground_y;
	c.prog = c.laps * track.N + loc.prog;
	c.lat = loc.lat;
	c.bank = loc.bank;
	c.t = loc.t;
	c.nx = loc.nx;
	c.nz = loc.nz;
	c.hw = loc.hw;
	c.grounded = true;
	c.air_time = 0.0;
	c.ground = 1.0;
	c.wall_t = 1000000;
	double fx = std::sin(c.yaw);
	double fz = std::cos(c.yaw);
	c.speed = js_hypot2(c.vx, c.vz);
	c.forward_speed = c.vx * fx + c.vz * fz;
	c.side_speed = c.vx * fz - c.vz * fx;
	// pick the gear that suits the speed
	c.gear_ = 1;
	const std::vector<double> &gears = P.gears;
	double wheel_rpm = (std::fabs(c.forward_speed) / P.wheel_radius) * (30.0 / PI);
	while (c.gear_ < (int)gears.size() && wheel_rpm * gears[c.gear_ - 1] * P.final_drive > P.upshift_rpm - 600.0) {
		c.gear_ += 1;
	}
	c.gear = c.speed < 0.3 ? 0 : c.gear_;
	c.rpm = maxf(P.idle_rpm, wheel_rpm * gears[c.gear_ - 1] * P.final_drive);
	// body attitude straight from the road, no spring transient
	road_attitude(c, track, loc);
	c.pitch = c.att_pitch;
	c.roll = c.att_roll;
	c.pitch_v = 0.0;
	c.roll_v = 0.0;
}

// Car.step: advance one fixed physics step.
void car_step(CarState &c, const Spec &P, const Track &track, const Controls &ctrl, double dt) {
	double steer_in = clampd(std::isnan(ctrl.steer) ? 0.0 : ctrl.steer, -1.0, 1.0);
	double thr = clampd(std::isnan(ctrl.throttle) ? 0.0 : ctrl.throttle, -1.0, 1.0);
	bool hb = ctrl.handbrake;
	// nitro: on the ground, in a forward gear, not braking, no handbrake, with something in the tank
	double boost_now = 0.0;
	double n_in = ctrl.nitro;
	if (n_in != 0.0 && !std::isnan(n_in) && !hb && c.nitro > 0.0 && c.grounded && c.gear_ >= 1 && thr > -0.02) {
		boost_now = clampd(n_in, 0.0, 1.0);
		if (thr < boost_now) {
			thr = boost_now;
		}
	}
	c.steer = steer_in;
	c.throttle = thr;
	c.hit_wall = false;
	c.wall_impact = 0.0;
	c.wall_now = false;
	int prev_idx = c.idx;

	// --- 1. steering command (rate limited) ---
	double d = steer_in - c.sc;
	double m = P.steer_rate * dt;
	c.sc += d > m ? m : (d < -m ? -m : d);

	// --- 2. surface under the car, drivetrain, nitro ---
	surface_env(c, P, track);
	drivetrain(c, P, thr, hb, dt);
	if (boost_now > 0.0) {
		double u = c.vx * std::sin(c.yaw) + c.vz * std::cos(c.yaw);
		double fade = clampd((P.nitro_top - u) / P.nitro_fade, 0.0, 1.0);
		c.env_drive += boost_now * fade * minf(P.nitro_force, P.nitro_power / (u > 1.0 ? u : 1.0));
		double left = c.nitro - (boost_now * dt) / P.nitro_time;
		c.nitro = left > 1e-9 ? left : 0.0;
	}
	c.boost = boost_now;
	c.boosting = boost_now > 0.0;

	// --- 3 + 4. planar dynamics and walls, in sub-steps ---
	int n = P.substeps;
	double h = dt / n;
	bool have_loc = false;
	for (int s = 0; s < n; s++) {
		planar_step(c, P, h);
		have_loc = walls(c, P, track, h);
	}

	// --- 5. locate, vertical ---
	if (!have_loc) {
		locate_near(track, c.x, c.z, c.idx, c.loc);
	}
	const Loc &loc = c.loc;
	vertical(c, P, track, loc, dt);

	// --- bookkeeping ---
	if (track.closed) {
		if (loc.idx - prev_idx < -track.N / 2.0) {
			c.laps += 1;
		} else if (loc.idx - prev_idx > track.N / 2.0) {
			c.laps -= 1;
		}
	}
	if (c.hit_wall) {
		c.wall_hits += 1;
	}
	if (c.wall_t < 1000000) {
		c.wall_t += 1;
	}
	// wall contact for effects; the rub memory fades while off the wall
	if (c.wall_now) {
		c.wall_y = c.y + WALL_Y;
	}
	if (c.hit_wall) {
		double vn = c.vx * c.wall_nx + c.vz * c.wall_nz;
		c.wall_scrape = std::sqrt(maxf(0.0, c.vx * c.vx + c.vz * c.vz - vn * vn));
	} else {
		c.wall_scrape = 0.0;
		if (c.rub_t > 0.0) {
			c.rub_t = maxf(0.0, c.rub_t - dt);
		}
	}
	c.idx = loc.idx;
	c.prog = c.laps * track.N + loc.prog;
	c.lat = loc.lat;
	c.bank = loc.bank;
	c.t = loc.t;
	c.nx = loc.nx;
	c.nz = loc.nz;
	c.hw = loc.hw;
	double fx = std::sin(c.yaw);
	double fz = std::cos(c.yaw);
	c.forward_speed = c.vx * fx + c.vz * fz;
	c.side_speed = c.vx * fz - c.vz * fx;
	c.speed = std::sqrt(c.vx * c.vx + c.vz * c.vz);
	c.wheel_rot = std::fmod(c.wheel_rot + (c.forward_speed / P.wheel_radius) * dt, 2.0 * PI);
	if (c.wheel_rot < 0.0) {
		c.wheel_rot += 2.0 * PI;
	}

	// derived "drifting" flag and slip amount (for effects)
	double a_r = std::fabs(c.slip_r);
	double a_f = std::fabs(c.slip_f);
	bool fast = c.speed > 8.0;
	bool hb_on = c.hb > 0.5 && c.speed > 12.0;
	if (c.drifting) {
		c.drifting = c.grounded && fast && (a_r > 0.1 || hb_on);
	} else {
		c.drifting = c.grounded && fast && (a_r > 0.16 || hb_on);
	}
	double sl = 0.0;
	if (c.grounded && c.speed > 3.0) {
		double lateral = (maxf(a_r, a_f) - 0.8 * P.peak_slip) / (2.2 * P.peak_slip);
		sl = maxf(maxf(lateral, c.tc_cut), c.hb * 0.9);
		sl *= minf(1.0, (c.speed - 3.0) / 6.0);
	}
	c.slip = clampd(sl, 0.0, 1.0);

	attitude(c, track, loc, dt);
}

} // namespace trackrush
