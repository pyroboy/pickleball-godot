extends RefCounted
class_name CardProfile
## Per-player body-language profile for the pixel cards, so the four players don't move in lockstep.
## Visual only. Fixed traits come from the actor id (same player = same habits every match); each
## switch also gets a little fresh jitter from the player's own RNG (the global RNG is untouched).
##
##   notice      s before this player reacts to a change (point over, serve coming)
##   rise_ease   s to stand up straight after a point
##   sink_ease   s to sink into the athletic stance for the serve
##   tempo       breathing / bounce / look-around speed (x)
##   phase       s offset into those loops

var notice: float
var rise_ease: float
var sink_ease: float
var tempo: float
var phase: float
var _rng: = RandomNumberGenerator.new()

func _init(actor_id: int) -> void:
	var r: = RandomNumberGenerator.new()
	r.seed = 104729 * (actor_id + 3)
	notice = r.randf_range(0.10, 0.45)
	rise_ease = r.randf_range(0.35, 0.75)
	sink_ease = r.randf_range(0.25, 0.50)
	tempo = r.randf_range(0.85, 1.15)
	phase = r.randf_range(0.0, 12.0)
	_rng.seed = 15485863 * (actor_id + 5)

## Small per-switch variation (s).
func jitter(amount: float = 0.15) -> float:
	return _rng.randf_range(-amount, amount)
