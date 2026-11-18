extends SceneTree
const Synth = preload("res://scripts/ball_audio_synth.gd")
var checks: = 0
var failures: = 0
func check(ok: bool, label: String):
 checks += 1
 if not ok:
  failures += 1
  push_error(label)
func _initialize():
 call_deferred("_run")
func _run():
 var synth = Synth.new()
 root.add_child(synth)
 await process_frame
 check(AudioServer.get_bus_index("SFX") >= 0, "SFX bus exists")
 check(synth.paddle_hit_player.bus == "SFX", "paddle routed SFX")
 check(synth.bounce_player.bus == "SFX", "bounce routed SFX")
 check(synth.net_hit_player.bus == "SFX", "net routed SFX")
 check(synth._thock_pool.size() == 8, "pool generated once")
 synth._create_procedural_sounds()
 check(synth._thock_pool.size() == 8 and synth._smash_pool.size() == 8, "rebuild idempotent")
 check(synth._rim_pool.size() == 4 and synth._frame_pool.size() == 4, "edge pool bounded")
 for pool in [synth._volley_pool, synth._thock_pool, synth._smash_pool]:
  for wav in pool:
   var peak: = 0
   for i in range(0, wav.data.size(), 2):
    peak = maxi(peak, absi(wav.data.decode_s16(i)))
   check(peak > 1000 and peak < 28000, "wave audible and not clipped")
   check(wav.data.decode_s16(wav.data.size() - 2) == 0, "wave tail fades zero")
 check(Synth.impact_volume_db(3) < Synth.impact_volume_db(9), "dink quieter than drive")
 check(Synth.impact_volume_db(9) < Synth.impact_volume_db(18), "drive quieter than smash")
 seed(96371)
 var expected_random: = randf()
 seed(96371)
 synth.on_paddle_hit(8.0)
 synth._create_volley_sound_at(0.5)
 check(is_equal_approx(randf(), expected_random), "audio leaves gameplay RNG unchanged")
 var last = null
 for n in range(60):
  synth.on_paddle_hit(8.0)
  check(synth.paddle_hit_player.stream != last, "no immediate repeated sample")
  check(synth.paddle_hit_player.volume_db <= -7.0, "overlap headroom")
  check(synth._thock_pool.has(synth.paddle_hit_player.stream), "clean contact not random rim")
  last = synth.paddle_hit_player.stream
 synth.on_paddle_hit(NAN)
 check(synth.paddle_hit_player.stream == last, "NaN ignored")
 synth.on_paddle_hit(0)
 check(synth.paddle_hit_player.stream == last, "zero impact ignored")
 synth.play_serve_sound(9.0)
 check(synth._thock_pool.has(synth.paddle_hit_player.stream), "serve uses cached pool")
 check(synth._court_pool.size() == 6, "six bounded bounce strength buckets")
 check(synth._net_tape_pool.size() == 3 and synth._net_mesh_pool.size() == 3, "six bounded net variants")
 var bank_bytes: = 0
 for pool in [synth._court_pool, synth._net_tape_pool, synth._net_mesh_pool]:
  for wav in pool:
   bank_bytes += wav.data.size()
   check(wav.data.decode_s16(wav.data.size() - 2) == 0, "bounce/net release fades to zero")
 check(bank_bytes < 64000, "new impact banks under 64 KB PCM")
 var original_bounce = synth._court_pool[4]
 var original_data: PackedByteArray = original_bounce.data
 for n in range(100):
  synth.on_floor_bounce(10.0)
  check(synth.bounce_player.stream == original_bounce, "bounce reuses exact cached resource")
 synth.on_floor_bounce(1.0)
 var soft_volume: float = synth.bounce_player.volume_db
 synth.on_floor_bounce(14.0)
 check(synth.bounce_player.volume_db > soft_volume, "bounce strength still controls gain")
 var bounce_before = synth.bounce_player.stream
 synth.on_floor_bounce(NAN)
 check(synth.bounce_player.stream == bounce_before, "invalid bounce ignored")
 var net: = Node3D.new()
 net.name = "Net"
 root.add_child(net)
 for n in range(50):
  synth.net_audio_cooldown = 0.0
  synth.on_body_entered(net, 0.9, Vector3(0, 0, 7))
  check(synth.net_hit_player.stream == synth._net_tape_pool[1], "net tape uses cached bank")
 synth.net_audio_cooldown = 0.0
 synth.on_body_entered(net, 0.4, Vector3(0, 0, 14))
 check(synth.net_hit_player.stream == synth._net_mesh_pool[2], "net mesh uses cached bank")
 synth.on_body_entered(net, 0.9, Vector3(0, 0, 7))
 check(synth.net_hit_player.stream == synth._net_mesh_pool[2], "net debounce preserved")
 net.queue_free()
 synth._create_procedural_sounds()
 check(synth._court_pool.size() == 6 and synth._net_mesh_pool.size() == 3, "tuning rebuild does not grow banks")
 check(synth._court_pool[4].data == original_data, "court bank deterministically rebuilds")
 check(synth.bounce_player.unit_size == 8.0 and synth.bounce_player.max_db == -8.0, "court-scale mix retains headroom")
 synth.on_paddle_hit(8.0)
 synth.on_floor_bounce(7.0)
 paused = true
 check( not synth.paddle_hit_player.playing, "scene pause discards paddle transient")
 check( not synth.bounce_player.playing, "scene pause discards bounce transient")
 check( not synth.net_hit_player.playing, "scene pause discards net transient")
 paused = false
 var buses = AudioServer.bus_count
 var other = Synth.new()
 root.add_child(other)
 await process_frame
 check(AudioServer.bus_count == buses, "second game no duplicate bus")
 other.queue_free()
 synth.queue_free()
 await process_frame
 await create_timer(0.05).timeout
 print("IMPACT AUDIO: %d checks, %d failures" % [checks, failures])
 quit(0 if failures == 0 else 1)
