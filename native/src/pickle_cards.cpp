#include "pickle_cards.h"

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/core/math.hpp>
#include <cmath>

using namespace godot;

namespace {

// pixel_card_rig.gd constants (same names).
const int SIG_HEAD = 4;
const int SIG_PER_CARD = 5;
const double SIG_TOL_SQ = 0.0014 * 0.0014;
const double CAM_TOL_SQ = 0.01 * 0.01;
const double CUP_OFF = 0.18;
const double CUP_AIM = 0.75;
const double LIMB_OVERLAP = 1.04;
const double LIMB_MIN_SHOWN = 0.34;
const double LIMB_DIR_HOLD = 0.10;
const double LIMB_DIR_FREE = 0.28;
const double AXIAL_HYST_DEG = 10.0;
const double LIMB_AXIAL_MIN = 0.7;
const double VIEW_LOW_ON = 16.0;
const double VIEW_LOW_OFF = 22.0;
const double VIEW_TOP_ON = 73.0;
const double VIEW_TOP_OFF = 67.0;
const double BIAS_BLEND = 0.04;
const int ATTR_STRIDE = 11;
const double SHADOW_WIDEN = 1.15; // the shadow's width over the art's: as full as the old camera-facing shadow read
const double VEL_FOLLOW = 0.55; // share of the way the blur's motion moves to this tick's each tick
const double VEL_ZERO_SQ = 0.0005 * 0.0005;
const double TICK_JUMP_SQ = 1.5 * 1.5;
const double TICK_TURN_MIN = 0.3;
const double TICK_FAST_SQ = 0.03 * 0.03; // a corner moved this far in the tick: the soft blur pass must be drawn (the solid pass leaves the blurred edges to it; under the shader's own threshold at any strength)
const int STATIC_STRIDE = 16;
const double DEG = 57.29577951308232;

inline double smooth(double from, double to, double x) {
	if (Math::is_equal_approx(from, to)) {
		return from;
	}
	const double s = CLAMP((x - from) / (to - from), 0.0, 1.0);
	return s * s * (3.0 - 2.0 * s);
}

} // namespace

void PickleCards::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "statics", "variants"), &PickleCards::setup);
	ClassDB::bind_method(D_METHOD("prepare", "sig", "force_all"), &PickleCards::prepare);
	ClassDB::bind_method(D_METHOD("build", "params", "hand_rows", "cup_mask", "tick_mode"), &PickleCards::build);
	ClassDB::bind_method(D_METHOD("setup_joints", "nodes", "reads"), &PickleCards::setup_joints);
	ClassDB::bind_method(D_METHOD("read_joints", "deltas", "extras", "flags", "interpolated"), &PickleCards::read_joints);
	ClassDB::bind_method(D_METHOD("prepare_read", "force_all"), &PickleCards::prepare_read);
	ClassDB::bind_method(D_METHOD("signature"), &PickleCards::signature);
	ClassDB::bind_method(D_METHOD("vertex_bytes"), &PickleCards::vertex_bytes);
	ClassDB::bind_method(D_METHOD("attr_bytes"), &PickleCards::attr_bytes);
	ClassDB::bind_method(D_METHOD("vertices"), &PickleCards::vertices);
	ClassDB::bind_method(D_METHOD("attributes"), &PickleCards::attributes);
}

void PickleCards::setup(const PackedFloat64Array &p_statics, const PackedFloat64Array &p_variants) {
	const int n = (int)(p_statics.size() / STATIC_STRIDE);
	cards.resize(n);
	const double *st = p_statics.ptr();
	for (int i = 0; i < n; i++) {
		const double *v = st + i * STATIC_STRIDE;
		Card c;
		c.limb = v[0] != 0.0;
		c.has_prev = v[1] != 0.0;
		c.hand = v[2] != 0.0;
		c.mirror = v[3] != 0.0;
		c.facing = (int)v[4];
		c.sided = v[5] != 0.0;
		c.anchor_x = v[6];
		c.anchor_y = v[7];
		c.end_y = v[8];
		c.detail = v[9];
		c.row = (int)v[10];
		c.low_row = (int)v[11];
		c.top_row = (int)v[12];
		c.bias = v[13];
		c.var_start = (int)v[14];
		c.var_count = (int)v[15];
		cards[i] = c;
	}
	variants = p_variants;
	verts.resize(n * 4);
	verts.fill(Vector3());
	old_verts.resize(n * 4);
	attr.resize(n * 4 * ATTR_STRIDE);
	attr.fill(0.0f);
	last_a.resize(0);
	vel_have = false;
	redrawn.resize(n);
	drawn_sig.resize(0);
	tick_moving = false;
	build_mask = 0;
}

void PickleCards::setup_joints(const Array &p_nodes, const PackedInt32Array &p_reads) {
	nodes = p_nodes;
	node_ids.resize(nodes.size());
	node_xf.resize(nodes.size());
	for (int i = 0; i < (int)nodes.size(); i++) {
		Object *o = nodes[i];
		node_ids[i] = o ? o->get_instance_id() : 0;
	}
	const int n = (int)(p_reads.size() / 7);
	reads.resize(n);
	for (int i = 0; i < n; i++) {
		Reads r;
		r.a = p_reads[i * 7];
		r.other = p_reads[i * 7 + 1];
		r.root = p_reads[i * 7 + 2];
		r.up_mode = p_reads[i * 7 + 3];
		r.elbow_a = p_reads[i * 7 + 4];
		r.elbow_other = p_reads[i * 7 + 5];
		r.hand_slot = p_reads[i * 7 + 6];
		reads[i] = r;
	}
}

bool PickleCards::read_joints(const Dictionary &p_deltas, const PackedVector3Array &p_extras, int p_flags, bool p_interpolated) {
	const int n = (int)cards.size();
	if ((int)reads.size() != n || p_extras.size() < 9) {
		return false;
	}
	const bool has_deltas = !p_deltas.is_empty();
	for (int i = 0; i < (int)node_ids.size(); i++) {
		Node3D *node = Object::cast_to<Node3D>(ObjectDB::get_instance(node_ids[i]));
		if (node == nullptr) {
			return false;
		}
		Transform3D xf = p_interpolated ? node->get_global_transform_interpolated() : node->get_global_transform();
		if (has_deltas) {
			const Variant d = p_deltas.get(nodes[i], Variant());
			if (d.get_type() == Variant::TRANSFORM3D) {
				xf = (Transform3D)d * xf;
			}
		}
		node_xf[i] = xf;
	}
	const int n_sig = SIG_HEAD + SIG_PER_CARD * n;
	if (sig.size() != n_sig) {
		sig.resize(n_sig);
	}
	const Vector3 *ex = p_extras.ptr();
	Vector3 *s = sig.ptrw();
	for (int k = 0; k < SIG_HEAD; k++) {
		s[k] = ex[k];
	}
	const Vector3 torso_pos = ex[4];
	const Vector3 ball_pos = ex[5];
	const bool ball_held = (p_flags & 4) != 0;
	for (int i = 0; i < n; i++) {
		const Reads &r = reads[i];
		Vector3 *c = s + SIG_HEAD + i * SIG_PER_CARD;
		c[0] = (r.elbow_a >= 0 && (p_flags & (1 << r.elbow_a))) ? ex[6 + r.elbow_a] : node_xf[r.a].origin;
		if (r.other >= 0) {
			c[1] = (r.elbow_other >= 0 && (p_flags & (1 << r.elbow_other))) ? ex[6 + r.elbow_other] : node_xf[r.other].origin;
		} else {
			c[1] = Vector3();
		}
		c[2] = r.root >= 0 ? node_xf[r.root].origin - torso_pos : Vector3();
		if (r.up_mode == 3) {
			c[3] = Vector3(r.hand_slot >= 0 ? ex[8][r.hand_slot] : (real_t)1.0, 0, 0);
		} else if (r.up_mode == 1) {
			c[3] = node_xf[r.a].basis.get_column(1);
		} else if (r.up_mode == 2) {
			c[3] = Vector3(0, 1, 0);
		} else {
			c[3] = Vector3();
		}
		c[4] = (ball_held && r.up_mode == 3) ? ball_pos : Vector3();
	}
	return true;
}

int64_t PickleCards::prepare_read(bool p_force_all) {
	return pick(p_force_all);
}

PackedVector3Array PickleCards::signature() const {
	return sig;
}

int64_t PickleCards::prepare(const PackedVector3Array &p_sig, bool p_force_all) {
	sig = p_sig;
	return pick(p_force_all);
}

int64_t PickleCards::pick(bool p_force_all) {
	const int n = (int)cards.size();
	const int n_sig = SIG_HEAD + SIG_PER_CARD * n;
	build_mask = 0;
	if (sig.size() != n_sig || n > 62) {
		return 0;
	}
	const Vector3 *s = sig.ptr();
	bool all_cards = p_force_all || drawn_sig.size() != n_sig;
	if (!all_cards) {
		const Vector3 *d = drawn_sig.ptr();
		if (s[0].distance_squared_to(d[0]) > CAM_TOL_SQ) {
			all_cards = true;
		} else {
			for (int k = 1; k < SIG_HEAD; k++) {
				if (s[k].distance_squared_to(d[k]) > SIG_TOL_SQ) {
					all_cards = true;
					break;
				}
			}
		}
	}
	if (drawn_sig.size() != n_sig) {
		drawn_sig = sig.duplicate();
	}
	Vector3 *d = drawn_sig.ptrw();
	if (all_cards) {
		for (int k = 0; k < SIG_HEAD; k++) {
			d[k] = s[k];
		}
	}
	for (int i = 0; i < n; i++) {
		const int si = SIG_HEAD + i * SIG_PER_CARD;
		bool moved = all_cards;
		if (!moved) {
			for (int k = 0; k < SIG_PER_CARD; k++) {
				if (s[si + k].distance_squared_to(d[si + k]) > SIG_TOL_SQ) {
					moved = true;
					break;
				}
			}
		}
		if (moved) {
			for (int k = 0; k < SIG_PER_CARD; k++) {
				d[si + k] = s[si + k];
			}
			build_mask |= (uint64_t)1 << i;
		}
	}
	return (int64_t)build_mask;
}

int PickleCards::build(const PackedFloat64Array &p_params, const PackedInt32Array &p_hand_rows, int64_t p_cup_mask, bool p_tick_mode) {
	const int n = (int)cards.size();
	if (p_params.size() < 23 || p_hand_rows.size() < n || sig.size() != SIG_HEAD + SIG_PER_CARD * n) {
		return 0;
	}
	const double *pr = p_params.ptr();
	const Vector3 cam_pos((real_t)pr[0], (real_t)pr[1], (real_t)pr[2]);
	const Vector3 torso_pos((real_t)pr[3], (real_t)pr[4], (real_t)pr[5]);
	const Vector3 ball_pos((real_t)pr[6], (real_t)pr[7], (real_t)pr[8]);
	const double s = pr[9];
	const double cell_x = pr[10], cell_y = pr[11];
	const int cols = (int)pr[12];
	const double tex_w = pr[13], tex_h = pr[14];
	const double squash = pr[15];
	const int body_cell = (int)pr[16], torso_cell = (int)pr[17], head_cell = (int)pr[18];
	const bool ball_ok = pr[19] != 0.0;
	const Vector3 light((real_t)pr[20], (real_t)pr[21], (real_t)pr[22]); // the sun's light direction, world
	const int32_t *hand_rows = p_hand_rows.ptr();
	const double *var = variants.ptr();
	const Vector3 *sg = sig.ptr();
	if (p_tick_mode) {
		old_verts = verts.duplicate();
		for (int i = 0; i < n; i++) {
			redrawn[i] = 0;
		}
	}
	Vector3 *vt = verts.ptrw();
	float *at = attr.ptrw();
	int built = 0;
	for (int i = 0; i < n; i++) {
		if (!(build_mask & ((uint64_t)1 << i))) {
			continue;
		}
		Card &c = cards[i];
		const int si = SIG_HEAD + i * SIG_PER_CARD;
		const Vector3 a = sg[si];
		const Vector3 b_src = sg[si + 1];
		const Vector3 root_pos = sg[si + 2] + torso_pos;
		const Vector3 up_read = sg[si + 3];
		built++;
		Vector3 b;
		if (c.limb) {
			b = b_src;
		} else if (c.has_prev) {
			Vector3 along = (a - b_src).normalized();
			// A hand cupping the ball points at the ball.
			if ((p_cup_mask & ((int64_t)1 << i)) && ball_ok) {
				const Vector3 to_ball = ball_pos - a;
				const double len = to_ball.length();
				if (len > 0.02 && len < CUP_OFF * 1.5) {
					along = along.lerp(to_ball.normalized(), (real_t)CUP_AIM).normalized();
				}
			}
			b = a + along * (real_t)0.06;
		} else {
			b = a;
		}
		const Vector3 mid = (a + b) * (real_t)0.5;
		const Vector3 z = (cam_pos - mid).normalized();
		Vector3 up_dir;
		double sy = s;
		Vector3 limb_shift;
		double true_scale = 1.0; // a limb's real length over the length its card shows
		int limb_row = -1;
		double tilt = 0.0;
		if (c.limb || c.has_prev) {
			const Vector3 d = b - a;
			Vector3 dp = d - z * d.dot(z);
			double texel_len = c.limb ? MAX(c.end_y - c.anchor_y, 1.0) : 1.2;
			if (dp.length() < 0.0001) {
				dp = -(Vector3(0, 1, 0) - z * z.y);
			}
			up_dir = -dp.normalized();
			// How end-on it is seen: + from its root end, - from its far end.
			tilt = std::asin(CLAMP((double)z.dot(-d.normalized()), -1.0, 1.0)) * DEG;
			const double side_share = (double)dp.length() / MAX((double)d.length(), 0.001);
			if (c.has_dir && side_share < LIMB_DIR_FREE) {
				const Vector3 kept = c.dir - z * c.dir.dot(z); // last direction, laid in today's plane
				if (kept.length_squared() > 1e-6) {
					const Vector3 kn = kept.normalized();
					up_dir = kn.dot(up_dir) > -0.999 ? kn.slerp(up_dir, (real_t)smooth(LIMB_DIR_HOLD, LIMB_DIR_FREE, side_share)).normalized() : kn;
				}
			}
			c.dir = up_dir;
			c.has_dir = true;
			if (c.limb) {
				// _pick_axial: the drawing nearest this tilt, the current one kept within the hysteresis.
				double pick_tilt = 0.0;
				int pick_row = c.row;
				double pick_len = MAX(c.end_y - c.anchor_y, 1.0);
				if (c.var_count > 0) {
					double best_off = INFINITY;
					int best = c.var_start, kept_v = -1;
					for (int v = c.var_start; v < c.var_start + c.var_count; v++) {
						const double off = std::abs(tilt - var[v * 3]);
						if (off < best_off) {
							best_off = off;
							best = v;
						}
						if (Math::is_equal_approx(var[v * 3], c.axial)) {
							kept_v = v;
						}
					}
					if (kept_v >= 0 && std::abs(tilt - c.axial) <= best_off + AXIAL_HYST_DEG) {
						best = kept_v;
					}
					pick_tilt = var[best * 3];
					pick_row = (int)var[best * 3 + 1];
					pick_len = var[best * 3 + 2];
					c.axial = pick_tilt;
				}
				limb_row = pick_row;
				texel_len = pick_len;
				// Never shorter than a share of the drawing's own length, centred on where it is.
				const double least = Math::is_zero_approx(pick_tilt) ? LIMB_MIN_SHOWN : std::cos(std::abs(pick_tilt) / DEG) * LIMB_AXIAL_MIN;
				const double shown = MAX((double)dp.length(), (double)d.length() * least);
				sy = shown / texel_len;
				true_scale = (double)d.length() / MAX(shown, 0.0001);
				limb_shift = up_dir * (real_t)((shown - (double)dp.length()) * 0.5);
			}
		} else {
			// Screen-up of the sprite: the part's own up while that is well seen; from steep above
			// or below the level direction away from the camera.
			Vector3 away = mid - cam_pos;
			away.y = 0.0;
			const double steep = smooth(0.55, 0.85, std::abs((double)z.y));
			const Vector3 plain = up_read - z * up_read.dot(z);
			Vector3 level;
			if (away.length_squared() > 1e-6) {
				level = away.normalized() * (real_t)((z.y > 0) - (z.y < 0));
				level = level - z * level.dot(z);
			}
			const Vector3 mixed = plain.normalized() * (real_t)(1.0 - steep) + (level.length_squared() > 1e-8 ? level.normalized() : plain.normalized()) * (real_t)steep;
			up_dir = (mixed.length_squared() > 1e-8 ? mixed : plain).normalized();
		}
		Vector3 x = up_dir.cross(z).normalized();
		int k = c.facing == 2 ? head_cell : (c.facing == 1 ? torso_cell : body_cell);
		if (c.mirror) {
			x = -x;
			k = (cols - k) % cols;
		}
		Vector3 origin_a = a + z * (mid - a).dot(z) + limb_shift;
		// Draw order by camera side: the limb chain nearer the camera than the torso draws in front.
		double bias = c.bias;
		if (c.sided) {
			bias *= CLAMP((double)(root_pos - torso_pos).dot(z) / BIAS_BLEND, -1.0, 1.0);
		}
		origin_a += z * (real_t)bias;
		double lsc = c.limb ? LIMB_OVERLAP : 1.0;
		double wsc = 1.0;
		if (!c.hand) {
			lsc *= 1.0 + squash;
			wsc = 1.0 - 0.7 * squash;
		}
		const double xs = s * wsc / c.detail;
		const double ys = sy * lsc / c.detail;
		// Which drawing: the limb's tilt row, the hand's state row, or low / normal / top by how
		// far above the part the camera is.
		int row = c.row;
		if (limb_row >= 0) {
			row = limb_row;
		}
		if (c.hand) {
			row = hand_rows[i];
			// _pick_hand_axial over this hand row's tilted drawings (base row, tilt, row).
			double best_off = INFINITY;
			int best = -1, kept_v = -1;
			for (int v = c.var_start; v < c.var_start + c.var_count; v++) {
				if ((int)var[v * 3] != row) {
					continue;
				}
				const double off = std::abs(tilt - var[v * 3 + 1]);
				if (off < best_off) {
					best_off = off;
					best = v;
				}
				if (Math::is_equal_approx(var[v * 3 + 1], c.axial)) {
					kept_v = v;
				}
			}
			if (best >= 0) {
				if (kept_v >= 0 && std::abs(tilt - c.axial) <= best_off + AXIAL_HYST_DEG) {
					best = kept_v;
				}
				c.axial = var[best * 3 + 1];
				row = (int)var[best * 3 + 2];
			}
		} else if (c.low_row >= 0 || c.top_row >= 0) {
			const double elev = std::asin(CLAMP((double)z.y, -1.0, 1.0)) * DEG;
			int view = c.view;
			if (view > 0) {
				view = elev > VIEW_TOP_OFF ? 1 : 0;
			} else if (view < 0) {
				view = elev < VIEW_LOW_OFF ? -1 : 0;
			}
			if (view == 0) {
				if (elev > VIEW_TOP_ON && c.top_row >= 0) {
					view = 1;
				} else if (elev < VIEW_LOW_ON && c.low_row >= 0) {
					view = -1;
				}
			}
			c.view = view;
			if (view > 0 && c.top_row >= 0) {
				row = c.top_row;
			} else if (view < 0 && c.low_row >= 0) {
				row = c.low_row;
			}
		}
		const real_t x0 = (real_t)(-c.anchor_x * xs);
		const real_t x1 = (real_t)((cell_x - c.anchor_x) * xs);
		const real_t y0 = (real_t)((0.0 - c.anchor_y) * ys);
		const real_t y1 = (real_t)((cell_y - c.anchor_y) * ys);
		const int v = i * 4;
		vt[v] = origin_a + x * x0 - up_dir * y0;
		vt[v + 1] = origin_a + x * x1 - up_dir * y0;
		vt[v + 2] = origin_a + x * x1 - up_dir * y1;
		vt[v + 3] = origin_a + x * x0 - up_dir * y1;
		const double u0 = (double)k * cell_x / tex_w;
		const double u1 = ((double)k + 1.0) * cell_x / tex_w;
		const double v0 = ((double)row * cell_y + 0.0) / tex_h;
		const double v1 = ((double)row + 1.0) * cell_y / tex_h;
		float *q = at + v * ATTR_STRIDE;
		// Another drawing has its own size and anchor: this tick shows it as it is.
		if (p_tick_mode && (!Math::is_equal_approx((double)q[0], u0) || !Math::is_equal_approx((double)q[1], v0) || !Math::is_equal_approx((double)q[2 * ATTR_STRIDE + 1], v1))) {
			redrawn[i] = 1;
		}
		q[0] = (float)u0;
		q[1] = (float)v0;
		q[ATTR_STRIDE] = (float)u1;
		q[ATTR_STRIDE + 1] = (float)v0;
		q[2 * ATTR_STRIDE] = (float)u1;
		q[2 * ATTR_STRIDE + 1] = (float)v1;
		q[3 * ATTR_STRIDE] = (float)u0;
		q[3 * ATTR_STRIDE + 1] = (float)v1;
		// The shadow's own shape. The card is a flat picture turned to the camera, pushed along
		// the view for draw order and shortened when the limb points at the camera: slid along
		// the sun, two cards that meet at a joint land apart, and from a camera that looks along
		// the light every card is edge-on to the sun and its shadow collapses to a line (photo
		// mode, low side views). The shadow is therefore cast by a shape that does not depend on
		// the camera at all: from the part's real joint, along its real line (its own up for the
		// head, chest and hips), turned to face the sun, SHADOW_WIDEN times as wide as the art so
		// it stays as full as the old shadow looked from the match camera. Flattened onto the
		// court by the shadow shader, it is the same from every angle. Stored per corner as the
		// offset from the card's corner.
		{
			Vector3 axis; // down the art: from the part's joint toward its far end
			if (c.limb || c.has_prev) {
				const Vector3 run = b - a;
				axis = run.length() > 1e-4 ? run.normalized() : -up_dir;
			} else {
				axis = up_read.length_squared() > 1e-6 ? -up_read.normalized() : Vector3(0, -1, 0);
			}
			Vector3 side = axis.cross(light);
			side = side.length_squared() > 1e-8 ? side.normalized() * (real_t)SHADOW_WIDEN : x;
			if (side.dot(x) < 0) {
				side = -side;
			}
			const real_t ya = (real_t)((double)y0 * true_scale), yb = (real_t)((double)y1 * true_scale);
			const Vector3 cast_corner[4] = { a + side * x0 + axis * ya, a + side * x1 + axis * ya, a + side * x1 + axis * yb, a + side * x0 + axis * yb };
			for (int corner = 0; corner < 4; corner++) {
				const Vector3 offset = cast_corner[corner] - vt[v + corner];
				float *o = q + corner * ATTR_STRIDE + 8;
				o[0] = offset.x;
				o[1] = offset.y;
				o[2] = offset.z;
			}
		}
	}
	// Motion blur: each corner's motion this tick, from the card's own joints (not from its
	// corners, which jump when a limb changes drawing or flips) and eased over a few ticks, so
	// the blur neither drops out for a tick nor changes length in steps.
	bool vel_changed = false, vel_fast = false;
	if (p_tick_mode) {
		if ((int)last_a.size() != n) {
			last_a.resize(n);
			last_b.resize(n);
			vel_a.resize(n);
			vel_b.resize(n);
			for (int i = 0; i < n; i++) {
				vel_a[i] = Vector3();
				vel_b[i] = Vector3();
			}
			vel_have = false;
		}
		for (int i = 0; i < n; i++) {
			const Card &c = cards[i];
			const int si = SIG_HEAD + i * SIG_PER_CARD;
			const Vector3 a = sg[si];
			const Vector3 b = c.limb ? sg[si + 1] : a;
			Vector3 raw_a, raw_b;
			if (vel_have) {
				raw_a = a - last_a[i];
				raw_b = b - last_b[i];
				if (raw_a.length_squared() > TICK_JUMP_SQ || raw_b.length_squared() > TICK_JUMP_SQ) {
					raw_a = Vector3();
					raw_b = Vector3();
				}
			}
			last_a[i] = a;
			last_b[i] = b;
			Vector3 va = vel_a[i].lerp(raw_a, (real_t)VEL_FOLLOW);
			Vector3 vb = vel_b[i].lerp(raw_b, (real_t)VEL_FOLLOW);
			if (va.length_squared() < VEL_ZERO_SQ) {
				va = Vector3();
			}
			if (vb.length_squared() < VEL_ZERO_SQ) {
				vb = Vector3();
			}
			vel_a[i] = va;
			vel_b[i] = vb;
			if (va.length_squared() > TICK_FAST_SQ || vb.length_squared() > TICK_FAST_SQ) {
				vel_fast = true;
			}
			// Along a limb the motion runs from its joint's to its far joint's.
			double t0 = 0.0, t1 = 0.0;
			if (c.limb) {
				const double len = MAX(c.end_y - c.anchor_y, 1.0);
				t0 = CLAMP(-c.anchor_y / len, -0.5, 1.5);
				t1 = CLAMP((cell_y - c.anchor_y) / len, -0.5, 1.5);
			}
			const Vector3 top = va + (vb - va) * (real_t)t0;
			const Vector3 bottom = va + (vb - va) * (real_t)t1;
			for (int corner = 0; corner < 4; corner++) {
				const Vector3 &v = corner < 2 ? top : bottom;
				float *q = at + (i * 4 + corner) * ATTR_STRIDE;
				if (q[5] != v.x || q[6] != v.y || q[7] != v.z) {
					vel_changed = true;
					q[5] = v.x;
					q[6] = v.y;
					q[7] = v.z;
				}
			}
		}
		vel_have = true;
	} else {
		vel_have = false;
	}
	bool upload = built > 0;
	if (p_tick_mode) {
		// Each corner's place one tick ago. A card that jumped, flipped, changed drawing or was
		// hidden a tick ago is shown where it is now.
		const bool moved = built > 0;
		upload = moved || tick_moving || vel_changed;
		bool fast = vel_fast;
		if (upload) {
			const Vector3 *ov = old_verts.ptr();
			for (int i = 0; i < n; i++) {
				const int first = i * 4;
				const Vector3 now0 = vt[first];
				const Vector3 was0 = ov[first];
				const Vector3 side_now = vt[first + 1] - now0;
				const Vector3 side_was = ov[first + 1] - was0;
				const Vector3 tall_now = vt[first + 3] - now0;
				const Vector3 tall_was = ov[first + 3] - was0;
				const bool blend_ok = redrawn[i] == 0 && was0.distance_squared_to(now0) <= TICK_JUMP_SQ &&
						(double)side_now.dot(side_was) > TICK_TURN_MIN * (double)side_now.length() * (double)side_was.length() &&
						(double)tall_now.dot(tall_was) > TICK_TURN_MIN * (double)tall_now.length() * (double)tall_was.length();
				if (blend_ok && (was0.distance_squared_to(now0) > TICK_FAST_SQ || ov[first + 1].distance_squared_to(vt[first + 1]) > TICK_FAST_SQ || ov[first + 2].distance_squared_to(vt[first + 2]) > TICK_FAST_SQ || ov[first + 3].distance_squared_to(vt[first + 3]) > TICK_FAST_SQ)) {
					fast = true;
				}
				for (int corner = first; corner < first + 4; corner++) {
					const Vector3 before = blend_ok ? ov[corner] : vt[corner];
					float *q = at + corner * ATTR_STRIDE;
					q[2] = before.x;
					q[3] = before.y;
					q[4] = before.z;
				}
			}
		}
		tick_moving = moved;
		return built + (upload ? 256 : 0) + (fast ? 512 : 0);
	}
	return built + (upload ? 256 : 0);
}

PackedByteArray PickleCards::vertex_bytes() const {
	return verts.to_byte_array();
}

PackedByteArray PickleCards::attr_bytes() const {
	return attr.to_byte_array();
}

PackedVector3Array PickleCards::vertices() const {
	return verts;
}

PackedFloat32Array PickleCards::attributes() const {
	return attr;
}
