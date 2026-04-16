extends Node

# Court
const COURT_LENGTH: float = 13.4
const COURT_WIDTH: float = 6.1
const NET_Z: float = 0.0
const NET_HEIGHT: float = 0.91
const FLOOR_Y: float = 0.075
const NON_VOLLEY_ZONE: float = 2.134  # 7 feet per USA Pickleball rules (was 1.8, ~13% undersized)
const LINE_WIDTH: float = 0.05

# Ball physics
const BALL_MASS: float = 0.024
const BALL_RADIUS: float = 0.06
const GRAVITY_SCALE: float = 1.5
const MAX_SPEED: float = 20.0
# BOUNCE_COR lives on Ball (calibrated via drop test). Reference Ball.BOUNCE_COR.

# Player
const PLAYER_SPEED: float = 5.8
const AI_SPEED: float = 6.5
const PADDLE_FORCE: float = 3.5
const AI_PADDLE_FORCE: float = 1.8

# Player physics
const JUMP_VELOCITY: float = 4.1
const JUMP_GRAVITY: float = 11.5

# Human overhead triggers (AI uses different, higher thresholds in player_ai_brain.gd)
const MEDIUM_OVERHEAD_TRIGGER_HEIGHT: float = 0.72
const HIGH_OVERHEAD_TRIGGER_HEIGHT: float = 1.08
const OVERHEAD_TRIGGER_RADIUS: float = 1.7
const OVERHEAD_RELEASE_HEIGHT: float = 0.62
const OVERHEAD_RELEASE_RADIUS: float = 2.0

# Serve
# NOTE: removed legacy fixed `SERVE_SPEED = 8.0` — live serves use the charge
# lerp between MIN_SERVE_SPEED and MAX_SERVE_SPEED. ball.gd keeps its own local
# copy for the direct serve_from() path (currently unused but public API).
const SERVE_HEIGHT: float = 1.5
const MIN_SERVE_SPEED: float = 5.5
const MAX_SERVE_SPEED: float = 12.0
const MAX_SERVE_CHARGE_TIME: float = 0.45
const HIT_REACH_DISTANCE: float = 1.15  # Updated for WIDE_FOREHAND/BACKHAND arm extension

# Gameplay bounds
const SIDE_BOUND_MARGIN: float = 2.4
const BASELINE_BOUND_MARGIN: float = 2.6
const NET_BOUND_MARGIN: float = 0.18

# Rule enforcement
# Baseline Z = half court length. Servers must be behind this line on strike.
const BASELINE_Z: float = COURT_LENGTH / 2.0  # 6.7m
# Small grace zone for foot fault (physics jitter, foot width). Real rule is
# strict about the line; this is a video game.
const FOOT_FAULT_TOLERANCE: float = 0.15  # meters
# Window after a legal volley during which a player's forward momentum into
# the kitchen counts as a fault. Real rule is "until established"; fixed 800ms
# is forgiving enough for recreational physics play.
const MOMENTUM_FAULT_WINDOW_MS: int = 800

# Positions
# NOTE: removed unused BLUE/RED_RESET_POSITION constants — they had the wrong
# y (0.5 vs 1.0) and z (±6.15 vs ±6.8). game.gd defines its own local copies
# with the correct values.

# Trajectory
const TRAJECTORY_STEP_TIME: float = 0.08
const TRAJECTORY_STEPS: int = 14  # Mobile: reduced from 28
const SERVE_AIM_STEP: float = 0.35
const SERVE_AIM_MAX: float = 2.2
const ARC_INTENT_STEP: float = 0.06
const ARC_INTENT_MIN: float = -0.12
const ARC_INTENT_MAX: float = 0.24
