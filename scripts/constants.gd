extends Node


const COURT_LENGTH: float = 13.4
const COURT_WIDTH: float = 6.1
const NET_Z: float = 0.0
const NET_HEIGHT: float = 0.91
const FLOOR_Y: float = 0.075
const NON_VOLLEY_ZONE: float = 2.134
const LINE_WIDTH: float = 0.05


const BALL_MASS: float = 0.024
const BALL_RADIUS: float = 0.06
const GRAVITY_SCALE: float = 1.5
const MAX_SPEED: float = 20.0



const PLAYER_SPEED: float = 5.8
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





const SERVE_HEIGHT: float = 1.5
const MIN_SERVE_SPEED: float = 5.5
const MAX_SERVE_SPEED: float = 12.0
const MAX_SERVE_CHARGE_TIME: float = 0.45
const HIT_REACH_DISTANCE: float = 1.15


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
