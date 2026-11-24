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
##   restless    how fidgety the player is while idle (quick looks, shuffles, faster fidgets)

var notice: float
var rise_ease: float
var sink_ease: float
var tempo: float
var phase: float
var restless: float   # 0 calm .. 1 cannot stand still
var stance_deg: float   # how far this player stands turned from square to the net at rest (deg, signed)
var stance_rate: float  # how often they change between turned and square (rad/s)
var look_deg: float     # how far the head turns when they look around (deg)
var fidgets: Array      # which idle fidgets they do: [toe bounce, paddle check, practice swing, loosen up] (0..1)
var _rng: = RandomNumberGenerator.new()

func _init(actor_id: int) -> void:
	var r: = RandomNumberGenerator.new()
	r.seed = 104729 * (actor_id + 3)
	notice = r.randf_range(0.10, 0.45)
	rise_ease = r.randf_range(0.35, 0.75)
	sink_ease = r.randf_range(0.25, 0.50)
	tempo = r.randf_range(0.85, 1.15)
	phase = r.randf_range(0.0, 12.0)
	# Set by seat, so each match has two restless players and two calm ones: your partner
	# (actor 2) and the first opponent (actor 1) cannot stand still.
	restless = float([0.1, 0.9, 0.75, 0.05][posmod(actor_id, 4)])
	# Idle habits by seat too, so the four never stand or fidget alike. Stance angles are small
	# (a foot moves about one card pixel); every player is square to the net part of the time.
	var seat: int = posmod(actor_id, 4)
	stance_deg = float([10.0, -12.0, 8.0, -9.0][seat])
	stance_rate = float([0.23, 0.31, 0.27, 0.19][seat])
	look_deg = float([30.0, 40.0, 36.0, 28.0][seat])
	fidgets = [[0.0, 0.0, 0.6, 0.6], [0.7, 0.7, 0.0, 0.0], [0.6, 0.0, 0.7, 0.0], [0.0, 0.6, 0.0, 0.6]][seat]
	_rng.seed = 15485863 * (actor_id + 5)

## Small per-switch variation (s).
func jitter(amount: float = 0.15) -> float:
	return _rng.randf_range(-amount, amount)
