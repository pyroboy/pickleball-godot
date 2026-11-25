#include "pickle_native.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/classes/skin.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <cmath>

using namespace godot;

namespace {

// ball.gd constants.
const double BALL_RADIUS = 0.0375;
const double BALL_MASS = 0.024;
const double MAX_SPEED = 20.0;
const double AIR_DENSITY = 1.225;
const double DRAG_COEFFICIENT = 0.47;
const double MAGNUS_COEFFICIENT = 0.0003;
const double SPIN_DAMPING_HALFLIFE = 150.0;
const double AERO_EFFECT_SCALE = 0.79;

struct Flight {
	Vector3 pos, vel, omega;
};

// One call of ball.gd predict_aero_steps. GDScript keeps scalars in 64 bits and vectors in 32:
// every vector * scalar below narrows the scalar first, as the script's operators do.
inline void steps(Flight &f, double gravity, double dt, int count, double linear_damp, double angular_damp) {
	const double spin_decay = AERO_EFFECT_SCALE > 0.0 ? std::exp(-dt * 0.693 / (SPIN_DAMPING_HALFLIFE * AERO_EFFECT_SCALE)) : 1.0;
	const double drag_factor = 0.5 * AIR_DENSITY * DRAG_COEFFICIENT * (3.14159265358979323846 * BALL_RADIUS * BALL_RADIUS);
	const real_t rdt = (real_t)dt;
	const real_t raero = (real_t)AERO_EFFECT_SCALE;
	const real_t vel_damp = (real_t)Math::max(1.0 - linear_damp * dt, 0.0);
	const real_t omega_damp = (real_t)Math::max(1.0 - angular_damp * dt, 0.0);
	for (int step = 0; step < count; step++) {
		const double speed = f.vel.length();
		if (speed > 0.1 && AERO_EFFECT_SCALE > 0.0) {
			const double drag_force_mag = drag_factor * speed * speed;
			const Vector3 drag_accel = -f.vel.normalized() * (real_t)(drag_force_mag / BALL_MASS);
			f.vel += drag_accel * rdt * raero;
		}
		if (f.omega.length_squared() > 0.01 && speed > 0.5 && AERO_EFFECT_SCALE > 0.0) {
			const Vector3 magnus_force = (real_t)MAGNUS_COEFFICIENT * f.omega.cross(f.vel);
			f.vel += (magnus_force / (real_t)BALL_MASS) * rdt * raero;
		}
		if (f.omega.length_squared() > 0.001 && AERO_EFFECT_SCALE > 0.0) {
			f.omega *= (real_t)spin_decay;
		}
		if (f.vel.length() > MAX_SPEED) {
			f.vel = f.vel.normalized() * (real_t)MAX_SPEED;
		}
		f.vel *= vel_damp;
		f.omega *= omega_damp;
		f.vel.y = (real_t)((double)f.vel.y - gravity * dt);
		f.pos += f.vel * rdt;
	}
}

// shot_profile.gd angular_velocity with no contact spin.
inline Vector3 spin_for(double topspin_rads, const Vector3 &velocity) {
	const Vector3 travel(velocity.x, 0.0, velocity.z);
	if (travel.length_squared() < 0.01) {
		return Vector3();
	}
	const Vector3 axis = Vector3(0, 1, 0).cross(travel.normalized());
	return axis * (real_t)topspin_rads;
}

} // namespace

Array PickleNative::aero_steps(const Vector3 &p_pos, const Vector3 &p_vel, const Vector3 &p_omega, double p_gravity, double p_dt, int p_count, double p_linear_damp, double p_angular_damp) {
	Flight f{ p_pos, p_vel, p_omega };
	steps(f, p_gravity, p_dt, p_count, p_linear_damp, p_angular_damp);
	Array out;
	out.push_back(f.pos);
	out.push_back(f.vel);
	out.push_back(f.omega);
	return out;
}

int64_t PickleNative::floor_scan(const PackedInt64Array &p_nodes, const PackedInt64Array &p_skeletons, const PackedInt64Array &p_meshes, const PackedInt32Array &p_surface_counts, const PackedVector3Array &p_boxes, const PackedFloat32Array &p_reach, double p_floor_y) {
	const int n = (int)p_nodes.size();
	if (n > 62 || p_skeletons.size() != n || p_meshes.size() != n || p_surface_counts.size() != n || p_boxes.size() != n * 2 || p_reach.size() != n) {
		return -1;
	}
	int64_t scan = 0;
	for (int i = 0; i < n; i++) {
		MeshInstance3D *instance = Object::cast_to<MeshInstance3D>(ObjectDB::get_instance((uint64_t)p_nodes[i]));
		if (instance == nullptr) {
			return -1;
		}
		const Ref<Mesh> mesh = instance->get_mesh();
		if (mesh.is_null() || instance->get_layer_mask() == 0) {
			continue;
		}
		if ((int64_t)mesh->get_instance_id() != p_meshes[i] || mesh->get_surface_count() != p_surface_counts[i]) {
			return -1;
		}
		const double reach = p_reach[i];
		const bool skinned = instance->get_skin().is_valid();
		if (skinned != (reach != -2.0)) {
			return -1;
		}
		bool clear;
		if (skinned) {
			if (reach < 0.0) {
				clear = false; // no cheap bound: the full check decides
			} else {
				Node3D *skeleton = Object::cast_to<Node3D>(ObjectDB::get_instance((uint64_t)p_skeletons[i]));
				if (skeleton == nullptr) {
					return -1;
				}
				const Transform3D root = skeleton->get_global_transform();
				const double scale = Math::sqrt(MAX((double)root.basis.get_column(0).length_squared(), MAX((double)root.basis.get_column(1).length_squared(), (double)root.basis.get_column(2).length_squared())));
				clear = (double)root.origin.y - reach * scale > p_floor_y;
			}
		} else {
			const Transform3D frame = instance->get_global_transform();
			const Vector3 row = frame.basis.rows[1];
			const Vector3 half = p_boxes[i * 2 + 1] * (real_t)0.5;
			const double lowest = (double)frame.origin.y + (double)row.dot(p_boxes[i * 2] + half) - ((double)Math::abs(row.x) * (double)half.x + (double)Math::abs(row.y) * (double)half.y + (double)Math::abs(row.z) * (double)half.z);
			clear = lowest - 0.00002 > p_floor_y;
		}
		if (clear) {
			continue;
		}
		// world_bounds: the box through the mesh's frame, or through every bone frame of its
		// skin; clear when its lowest corner is above the floor.
		const Vector3 box_from = p_boxes[i * 2];
		const Vector3 box_size = p_boxes[i * 2 + 1];
		real_t lowest_y = INFINITY;
		const Ref<Skin> skin = instance->get_skin();
		Skeleton3D *bones = skinned ? Object::cast_to<Skeleton3D>(ObjectDB::get_instance((uint64_t)p_skeletons[i])) : nullptr;
		const int binds = bones != nullptr ? (int)skin->get_bind_count() : 0;
		for (int frame_index = 0; frame_index < MAX(binds, 1); frame_index++) {
			Transform3D frame = instance->get_global_transform();
			if (binds > 0) {
				int bone = skin->get_bind_bone(frame_index);
				if (bone < 0) {
					bone = bones->find_bone(skin->get_bind_name(frame_index));
				}
				if (bone >= 0) {
					frame = bones->get_global_transform() * bones->get_bone_global_pose(bone) * skin->get_bind_pose(frame_index);
				}
			}
			for (int corner = 0; corner < 8; corner++) {
				// AABB.get_endpoint order does not matter for a minimum.
				const Vector3 point = frame.xform(Vector3(box_from.x + ((corner & 4) ? box_size.x : 0), box_from.y + ((corner & 2) ? box_size.y : 0), box_from.z + ((corner & 1) ? box_size.z : 0)));
				lowest_y = MIN(lowest_y, point.y);
			}
		}
		if ((double)lowest_y > p_floor_y) {
			continue;
		}
		scan |= (int64_t)1 << i;
	}
	return scan;
}

Vector3 PickleNative::fit_launch(const Vector3 &p_start, const Vector3 &p_target, const Vector3 &p_launch, double p_duration, double p_topspin_rads, double p_speed_cap, int p_max_passes, bool p_early_exit, double p_gravity, double p_dt, double p_linear_damp, double p_angular_damp) {
	Vector3 launch = p_launch;
	const int count = (int)Math::round(p_duration / p_dt);
	const Vector3 aim = p_target - Vector3(0, 0.0005, 0);
	for (int pass = 0; pass < p_max_passes; pass++) {
		Flight f{ p_start, launch, spin_for(p_topspin_rads, launch) };
		steps(f, p_gravity, p_dt, count, p_linear_damp, p_angular_damp);
		const Vector3 residual = aim - f.pos;
		if (p_early_exit && residual.length_squared() < 4e-08) {
			break;
		}
		launch += residual / (real_t)p_duration * (real_t)0.86;
		launch = launch.limit_length((real_t)p_speed_cap);
	}
	return launch;
}

void PickleNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("aero_steps", "pos", "vel", "omega", "gravity", "dt", "count", "linear_damp", "angular_damp"), &PickleNative::aero_steps);
	ClassDB::bind_method(D_METHOD("floor_scan", "nodes", "skeletons", "meshes", "surface_counts", "boxes", "reach", "floor_y"), &PickleNative::floor_scan);
	ClassDB::bind_method(D_METHOD("fit_launch", "start", "target", "launch", "duration", "topspin_rads", "speed_cap", "max_passes", "early_exit", "gravity", "dt", "linear_damp", "angular_damp"), &PickleNative::fit_launch);
}
