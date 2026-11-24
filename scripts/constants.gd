extends Node


const COURT_LENGTH: float = 13.4
const COURT_WIDTH: float = 6.1
const NET_Z: float = 0.0
# Nominal height for HUD markers only. The real net (0.8636 m centre, 0.9144 m at the
# sidelines) is scripts/net_profile.gd. Ball size, mass and speed cap live in scripts/ball.gd.
const NET_HEIGHT: float = 0.91
const FLOOR_Y: float = 0.075
const NON_VOLLEY_ZONE: float = 2.134
const LINE_WIDTH: float = 0.05





const PLAYER_SPEED: float = 5.8
# Match special actions whose whole-body pose is built in code, not from the pose editor:
# the emergency lunge (grounded reach) and the Erne jump. Off: players only play editor poses
# and must move to the ball. The code stays for a later editable version.
const MATCH_SPECIAL_ACTIONS: bool = false
const AI_SPEED: float = PLAYER_SPEED
const PADDLE_FORCE: float = 3.5
const AI_PADDLE_FORCE: float = 1.8


const JUMP_VELOCITY: float = 4.1
const JUMP_GRAVITY: float = 11.5


const MEDIUM_OVERHEAD_TRIGGER_HEIGHT: float = 0.72
const HIGH_OVERHEAD_TRIGGER_HEIGHT: float = 1.08
const OVERHEAD_TRIGGER_RADIUS: float = 1.7
const OVERHEAD_RELEASE_HEIGHT: float = 0.62
const OVERHEAD_RELEASE_RADIUS: float = 2.0





const MIN_SERVE_SPEED: float = 5.5
const MAX_SERVE_SPEED: float = 12.0
const MAX_SERVE_CHARGE_TIME: float = 0.45
## Rally shots: power grows with the hold up to this many seconds (a tap under
## human_shot_choice.TAP_SECONDS is still a touch shot). Serves keep MAX_SERVE_CHARGE_TIME.
const RALLY_FULL_HOLD: float = 1.0


const SIDE_BOUND_MARGIN: float = 2.4
const BASELINE_BOUND_MARGIN: float = 2.6
const NET_BOUND_MARGIN: float = 0.18



const BASELINE_Z: float = COURT_LENGTH / 2.0


const FOOT_FAULT_TOLERANCE: float = 0.15



const MOMENTUM_FAULT_WINDOW_MS: int = 800







const TRAJECTORY_STEP_TIME: float = 0.08
const TRAJECTORY_STEPS: int = 14
const SERVE_AIM_STEP: float = 0.35
const SERVE_AIM_MAX: float = 2.2
const ARC_INTENT_STEP: float = 0.06
const ARC_INTENT_MIN: float = -0.12
const ARC_INTENT_MAX: float = 0.24
