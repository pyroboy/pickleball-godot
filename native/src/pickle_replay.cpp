#include "pickle_replay.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <cstring>

using namespace godot;

namespace {
const int REPLAY_VERSION = 1; // scripts/fx/photo_history.gd RALLY_VERSION
const int BALL_NUMBERS = 15;
} // namespace

void PickleReplay::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "nodes", "counts", "max_ticks"), &PickleReplay::setup);
	ClassDB::bind_method(D_METHOD("begin"), &PickleReplay::begin);
	ClassDB::bind_method(D_METHOD("record", "ball", "motion", "turn"), &PickleReplay::record);
	ClassDB::bind_method(D_METHOD("recorded"), &PickleReplay::recorded);
	ClassDB::bind_method(D_METHOD("finish"), &PickleReplay::finish);
	ClassDB::bind_method(D_METHOD("finished_ticks"), &PickleReplay::finished_ticks);
	ClassDB::bind_method(D_METHOD("drop_finished"), &PickleReplay::drop_finished);
	ClassDB::bind_method(D_METHOD("save_finished", "path", "tick_rate"), &PickleReplay::save_finished);
	ClassDB::bind_method(D_METHOD("load", "path"), &PickleReplay::load);
	ClassDB::bind_method(D_METHOD("viewing_ticks"), &PickleReplay::viewing_ticks);
	ClassDB::bind_method(D_METHOD("close_view"), &PickleReplay::close_view);
	ClassDB::bind_method(D_METHOD("apply", "tick"), &PickleReplay::apply);
	ClassDB::bind_method(D_METHOD("ball", "tick"), &PickleReplay::ball);
}

void PickleReplay::setup(const Array &p_nodes, const PackedInt32Array &p_counts, int p_max_ticks) {
	ids.resize(p_nodes.size());
	for (int i = 0; i < (int)p_nodes.size(); i++) {
		Object *o = p_nodes[i];
		ids[i] = o ? o->get_instance_id() : 0;
	}
	counts = p_counts;
	per_tick = (int)ids.size() * 12 + BALL_NUMBERS;
	max_ticks = MAX(p_max_ticks, 1);
	begin();
}

void PickleReplay::begin() {
	rec.clear();
	rec_first = 0;
	rec_ticks = 0;
}

bool PickleReplay::record(const Vector3 &p_ball, const Vector3 &p_motion, const Basis &p_turn) {
	if (per_tick <= 0) {
		return false;
	}
	const size_t at = rec.size();
	rec.resize(at + per_tick);
	float *out = rec.data() + at;
	for (uint32_t i = 0; i < ids.size(); i++) {
		Node3D *node = Object::cast_to<Node3D>(ObjectDB::get_instance(ids[i]));
		if (node == nullptr) {
			rec.resize(at);
			return false;
		}
		const Transform3D xf = node->get_global_transform();
		for (int column = 0; column < 3; column++) {
			const Vector3 axis = xf.basis.get_column(column);
			*out++ = axis.x;
			*out++ = axis.y;
			*out++ = axis.z;
		}
		*out++ = xf.origin.x;
		*out++ = xf.origin.y;
		*out++ = xf.origin.z;
	}
	*out++ = p_ball.x;
	*out++ = p_ball.y;
	*out++ = p_ball.z;
	*out++ = p_motion.x;
	*out++ = p_motion.y;
	*out++ = p_motion.z;
	for (int column = 0; column < 3; column++) {
		const Vector3 axis = p_turn.get_column(column);
		*out++ = axis.x;
		*out++ = axis.y;
		*out++ = axis.z;
	}
	rec_ticks++;
	// The cap: the oldest ticks are passed over, and cleared out in one go now and then.
	if (rec_ticks - rec_first > max_ticks) {
		rec_first++;
		if (rec_first >= 512) {
			const size_t keep = (size_t)(rec_ticks - rec_first) * per_tick;
			memmove(rec.data(), rec.data() + (size_t)rec_first * per_tick, keep * sizeof(float));
			rec.resize(keep);
			rec_ticks -= rec_first;
			rec_first = 0;
		}
	}
	return true;
}

int PickleReplay::recorded() const {
	return rec_ticks - rec_first;
}

void PickleReplay::finish() {
	const int ticks = rec_ticks - rec_first;
	// Drop the passed-over start (only when the cap was reached), then hand the block over
	// by swapping: no copy of the rally at the end of a point.
	if (rec_first > 0 && ticks > 0) {
		memmove(rec.data(), rec.data() + (size_t)rec_first * per_tick, (size_t)ticks * per_tick * sizeof(float));
	}
	rec.resize((size_t)MAX(ticks, 0) * per_tick);
	{
		std::lock_guard<std::mutex> guard(done_lock);
		done.swap(rec);
		done_ticks = ticks;
	}
	begin();
}

int PickleReplay::finished_ticks() {
	std::lock_guard<std::mutex> guard(done_lock);
	return done_ticks;
}

void PickleReplay::drop_finished() {
	std::lock_guard<std::mutex> guard(done_lock);
	done.clear();
	done_ticks = 0;
}

bool PickleReplay::save_finished(const String &p_path, int p_tick_rate) {
	// The finished rally is taken out under the lock, then written without it: the match can
	// end the next rally while this one is still being compressed.
	std::vector<float> block;
	int ticks = 0;
	PackedInt32Array joints;
	{
		std::lock_guard<std::mutex> guard(done_lock);
		if (done_ticks <= 0) {
			return false;
		}
		block.swap(done);
		ticks = done_ticks;
		joints = counts;
		done_ticks = 0;
	}
	Ref<FileAccess> file = FileAccess::open_compressed(p_path, FileAccess::WRITE, FileAccess::COMPRESSION_ZSTD);
	if (file.is_null()) {
		return false;
	}
	file->store_32(REPLAY_VERSION);
	file->store_32(p_tick_rate);
	file->store_32(ticks);
	file->store_32(joints.size());
	for (int i = 0; i < (int)joints.size(); i++) {
		file->store_32(joints[i]);
	}
	PackedByteArray bytes;
	bytes.resize(block.size() * sizeof(float));
	memcpy(bytes.ptrw(), block.data(), block.size() * sizeof(float));
	file->store_buffer(bytes);
	file->close();
	return true;
}

int PickleReplay::load(const String &p_path) {
	close_view();
	Ref<FileAccess> file = FileAccess::open_compressed(p_path, FileAccess::READ, FileAccess::COMPRESSION_ZSTD);
	if (file.is_null() || file->get_32() != (uint32_t)REPLAY_VERSION) {
		return 0;
	}
	file->get_32();
	const int ticks = (int)file->get_32();
	const int players = (int)file->get_32();
	if (players != (int)counts.size() || ticks <= 0) {
		return 0;
	}
	for (int i = 0; i < players; i++) {
		if ((int)file->get_32() != counts[i]) {
			return 0;
		}
	}
	const int64_t want = (int64_t)ticks * per_tick * (int64_t)sizeof(float);
	const PackedByteArray bytes = file->get_buffer(want);
	const int got = (int)(bytes.size() / ((int64_t)per_tick * (int64_t)sizeof(float)));
	if (got <= 0) {
		return 0;
	}
	view.resize((uint32_t)got * per_tick);
	memcpy(view.data(), bytes.ptr(), (size_t)got * per_tick * sizeof(float));
	view_ticks = got;
	return got;
}

int PickleReplay::viewing_ticks() const {
	return view_ticks;
}

void PickleReplay::close_view() {
	view.clear();
	view_ticks = 0;
}

bool PickleReplay::apply(int p_tick) {
	if (view_ticks <= 0) {
		return false;
	}
	const float *in = view.data() + (uint32_t)CLAMP(p_tick, 0, view_ticks - 1) * per_tick;
	for (uint32_t i = 0; i < ids.size(); i++) {
		Node3D *node = Object::cast_to<Node3D>(ObjectDB::get_instance(ids[i]));
		if (node == nullptr) {
			return false;
		}
		Transform3D xf;
		xf.basis.set_column(0, Vector3(in[0], in[1], in[2]));
		xf.basis.set_column(1, Vector3(in[3], in[4], in[5]));
		xf.basis.set_column(2, Vector3(in[6], in[7], in[8]));
		xf.origin = Vector3(in[9], in[10], in[11]);
		node->set_global_transform(xf);
		in += 12;
	}
	return true;
}

PackedFloat32Array PickleReplay::ball(int p_tick) const {
	PackedFloat32Array out;
	if (view_ticks <= 0) {
		return out;
	}
	out.resize(BALL_NUMBERS);
	const float *in = view.data() + (uint32_t)CLAMP(p_tick, 0, view_ticks - 1) * per_tick + ids.size() * 12;
	memcpy(out.ptrw(), in, BALL_NUMBERS * sizeof(float));
	return out;
}
