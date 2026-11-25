// Native hot paths (docs/PERFORMANCE_PLAN.md step 8). Each function is a port of a GDScript
// function that stays in the project as the reference and the fallback; the script names are
// given at each function. Same equations, same order of operations, same float widths.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class PickleNative : public RefCounted {
	GDCLASS(PickleNative, RefCounted)

protected:
	static void _bind_methods();

public:
	// ball.gd predict_aero_steps: `count` flight steps of `dt`; returns [pos, vel, omega].
	Array aero_steps(const Vector3 &p_pos, const Vector3 &p_vel, const Vector3 &p_omega, double p_gravity, double p_dt, int p_count, double p_linear_damp, double p_angular_damp);
	// shot_physics.gd: the launch-fitting loop of _solve_aim_candidate / _solve_drop_candidate.
	// Returns the launch velocity that lands on `target` after `duration` (or the last try).
	// player_surface_contacts.gd ground_contacts: which body meshes may reach the floor (the
	// _clear_of_floor test per mesh). Per mesh: its node id, its skeleton's node id (skinned),
	// its mesh id and surface count as cached, its box (position, size) and reach (-2 rigid,
	// below 0 otherwise: no cheap bound, at least 0: skinned reach). Returns a bit per mesh to
	// scan, or -1 when what was cached no longer matches the scene (the script path decides).
	int64_t floor_scan(const PackedInt64Array &p_nodes, const PackedInt64Array &p_skeletons, const PackedInt64Array &p_meshes, const PackedInt32Array &p_surface_counts, const PackedVector3Array &p_boxes, const PackedFloat32Array &p_reach, double p_floor_y);
	Vector3 fit_launch(const Vector3 &p_start, const Vector3 &p_target, const Vector3 &p_launch, double p_duration, double p_topspin_rads, double p_speed_cap, int p_max_passes, bool p_early_exit, double p_gravity, double p_dt, double p_linear_damp, double p_angular_damp);
};

} // namespace godot
