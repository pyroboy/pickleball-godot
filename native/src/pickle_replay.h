// Native rally recorder (scripts/fx/photo_history.gd is the reference and the fallback). One
// object per match. Per physics tick of a rally it reads the players' joints and appends
// them to one flat block of numbers, which is already the file's layout: a save is one write,
// done on a worker thread, and playback places the joints straight from the block.
// File layout (same as the script's): version, tick rate, ticks, players, joints per player,
// then per tick 12 numbers per joint (basis columns x, y, z, origin) and 15 for the ball
// (position, blur motion, hole turn as basis columns).
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <mutex>
#include <vector>

namespace godot {

class PickleReplay : public RefCounted {
	GDCLASS(PickleReplay, RefCounted)

	LocalVector<uint64_t> ids; // the joints, every player's in turn, parents before children
	PackedInt32Array counts; // joints per player
	int per_tick = 0;
	int max_ticks = 1800;
	std::vector<float> rec; // the rally being recorded
	int rec_first = 0; // ticks dropped from its start (the cap)
	int rec_ticks = 0;
	std::mutex done_lock;
	std::vector<float> done; // the rally that just ended, until it is saved
	int done_ticks = 0;
	std::vector<float> view; // a loaded rally
	int view_ticks = 0;

protected:
	static void _bind_methods();

public:
	void setup(const Array &p_nodes, const PackedInt32Array &p_counts, int p_max_ticks);
	void begin();
	// One tick; false when a joint is gone (the caller sets the list up again).
	bool record(const Vector3 &p_ball, const Vector3 &p_motion, const Basis &p_turn);
	int recorded() const;
	void finish(); // the recorded rally becomes the finished one
	int finished_ticks();
	void drop_finished();
	// Writes the finished rally (compressed). Safe on a worker thread.
	bool save_finished(const String &p_path, int p_tick_rate);
	// Loads a saved rally for viewing; returns its ticks, 0 when it does not fit these joints.
	int load(const String &p_path);
	int viewing_ticks() const;
	void close_view();
	bool apply(int p_tick); // places every joint as in that tick of the loaded rally
	PackedFloat32Array ball(int p_tick) const; // its 15 ball numbers
};

} // namespace godot
