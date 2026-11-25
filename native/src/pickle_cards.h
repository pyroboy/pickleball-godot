// Native build of one player's pixel cards (docs/PERFORMANCE_PLAN.md step 5 / 8). A port of
// the quad loop of scripts/graphics/pixel_card_rig.gd _draw_cards, which stays in the project
// as the reference and the fallback (PerfToggles.native_math off, first person, debug lines,
// recorded frames). One object per rig: it keeps what the script keeps between builds (the
// inputs each card was last built from, the drawing each card shows, the corners).
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class PickleCards : public RefCounted {
	GDCLASS(PickleCards, RefCounted)

	struct Card {
		bool limb = false, has_prev = false, hand = false, mirror = false, sided = false;
		int facing = 0; // 0 body, 1 torso, 2 head
		double anchor_x = 0.0, anchor_y = 0.0, end_y = 0.0, detail = 1.0, bias = 0.0;
		int row = 0, low_row = -1, top_row = -1;
		int var_start = 0, var_count = 0;
		// Kept between builds (the script keeps these in the card's dictionary).
		int view = 0;
		double axial = 0.0;
		bool has_dir = false;
		Vector3 dir;
	};

	// Joint reads (setup_joints / read_joints): the rig's distinct joint nodes and, per card,
	// which of them it reads.
	struct Reads {
		int a = -1, other = -1, root = -1; // node indices: the card's joint, its far joint or the joint before it, its chain's root
		int up_mode = 0; // 0 none, 1 the joint's own up, 2 world up, 3 hand (free weight)
		int elbow_a = -1, elbow_other = -1; // arm slot whose drawn elbow replaces that read
		int hand_slot = -1;
	};
	Array nodes; // keeps the Variants for the delta lookup
	LocalVector<uint64_t> node_ids;
	LocalVector<Transform3D> node_xf;
	LocalVector<Reads> reads;

	LocalVector<Card> cards;
	PackedFloat64Array variants; // limbs: tilt, row, texels joint to joint; hands: base row, tilt, row
	PackedVector3Array sig; // this build's inputs
	PackedVector3Array drawn_sig; // the inputs each card was last built from
	PackedVector3Array verts;
	PackedVector3Array old_verts;
	PackedFloat32Array attr; // per corner: u, v, the corner one tick ago (x, y, z), its eased motion per tick (x, y, z), the shadow's corner as an offset (x, y, z)
	LocalVector<uint8_t> redrawn;
	// Motion blur: each card's joints one tick ago and their eased motion per tick.
	LocalVector<Vector3> last_a, last_b, vel_a, vel_b;
	bool vel_have = false;
	uint64_t build_mask = 0;
	bool tick_moving = false;

protected:
	static void _bind_methods();

public:
	// Per card, 16 numbers: limb, has prev, hand, mirror, facing, sided, anchor x, anchor y,
	// end y, detail, row, low row, top row, draw-order bias, first variant, variant count.
	void setup(const PackedFloat64Array &p_statics, const PackedFloat64Array &p_variants);
	// Per card, 7 numbers (see Reads). `nodes` are the distinct Node3D joints they index.
	void setup_joints(const Array &p_nodes, const PackedInt32Array &p_reads);
	// Fills this build's inputs from the joints: pixel_card_rig.gd's signature loop. deltas:
	// the motion layer's node -> Transform3D. extras: the 4 head entries, torso, ball, drawn
	// elbow of arm slot 0 and 1, free weights (x, y, z by hand slot). flags: 1 / 2 the drawn
	// elbow of slot 0 / 1 is given, 4 the ball is held. False when a joint is gone.
	bool read_joints(const Dictionary &p_deltas, const PackedVector3Array &p_extras, int p_flags, bool p_interpolated);
	int64_t prepare_read(bool p_force_all);
	PackedVector3Array signature() const;
	// Which cards' inputs moved since they were built (bit per card); remembers the new inputs.
	int64_t prepare(const PackedVector3Array &p_sig, bool p_force_all);

private:
	int64_t pick(bool p_force_all);

public:
	// Builds the cards prepare() picked. params: camera (3), torso (3), ball (3), metres per
	// texel, cell w, cell h, columns, atlas w, atlas h, squash, body / torso / head cell, ball
	// valid, the sun's light direction (3). Returns the number built, plus 256 when the mesh buffers changed, plus 512 when a
	// card moved fast enough this tick for motion blur to show.
	int build(const PackedFloat64Array &p_params, const PackedInt32Array &p_hand_rows, int64_t p_cup_mask, bool p_tick_mode);
	PackedByteArray vertex_bytes() const;
	PackedByteArray attr_bytes() const;
	PackedVector3Array vertices() const;
	PackedFloat32Array attributes() const;
};

} // namespace godot
