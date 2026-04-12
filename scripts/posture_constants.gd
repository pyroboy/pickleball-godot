class_name PostureConstants
extends RefCounted

## Extracted constants from player_paddle_posture.gd.
## Phase 1b: all these values were inline const declarations.
## Wiring in Phase 1c replaces the inline constants with imports from this file.

# ── Paddle posture position / height ─────────────────────────────────────────
const PADDLE_SIDE_OFFSET                := 0.5
const PADDLE_FORWARD_OFFSET             := 0.4
const PADDLE_CENTER_OFFSET              := 0.42
const PADDLE_BACKHAND_OFFSET            := 0.42
const PADDLE_MEDIUM_OVERHEAD_HEIGHT     := 0.6
const PADDLE_MEDIUM_OVERHEAD_FORWARD    := 0.7
const PADDLE_HIGH_OVERHEAD_HEIGHT       := 1.1
const PADDLE_HIGH_OVERHEAD_FORWARD      := 0.8
const PADDLE_OVERHEAD_SIDE_OFFSET       := 0.5
const PADDLE_LOW_HEIGHT                 := -0.62
const PADDLE_LOW_FORWARD_OFFSET        := 0.55
const PADDLE_BACKSWING_DEGREES          := 65.0
const PADDLE_FOLLOW_THROUGH_DEGREES    := 18.0
const PADDLE_CHARGE_PULLBACK           := 0.24
const PADDLE_CHARGE_LIFT                := 0.1
const PADDLE_CHARGE_BEHIND_OFFSET       := 0.42
const PADDLE_CHARGE_FOREHAND_BEHIND     := 0.65
const PADDLE_CHARGE_FOREHAND_HEIGHT     := 0.35
const PADDLE_CHARGE_BACKHAND_BEHIND     := 0.65
const PADDLE_CHARGE_BACKHAND_HEIGHT     := 0.35
const PADDLE_POSTURE_SWITCH_DEADZONE    := 0.22
const PADDLE_WIDE_LATERAL_THRESHOLD     := 0.65

# ── Ghost stretch / intercept clamp limits ───────────────────────────────────
const GHOST_STRETCH_LATERAL_MAX        := 1.4
const GHOST_STRETCH_HEIGHT_MIN          := -0.62
const GHOST_STRETCH_HEIGHT_MAX         := 1.3
const GHOST_FORWARD_PLANE              := 0.5
const GHOST_CONTACT_MAX_DIST           := 3.0
const ZONE_EXIT_MARGIN                 := 0.3

# ── Overhead trigger thresholds (forwarded from PickleballConstants) ──────────
## These aliases keep posture logic self-contained; values live in PickleballConstants.
const MEDIUM_OVERHEAD_TRIGGER_HEIGHT   := PickleballConstants.MEDIUM_OVERHEAD_TRIGGER_HEIGHT
const HIGH_OVERHEAD_TRIGGER_HEIGHT     := PickleballConstants.HIGH_OVERHEAD_TRIGGER_HEIGHT
const OVERHEAD_TRIGGER_RADIUS          := PickleballConstants.OVERHEAD_TRIGGER_RADIUS
const OVERHEAD_RELEASE_HEIGHT          := PickleballConstants.OVERHEAD_RELEASE_HEIGHT
const OVERHEAD_RELEASE_RADIUS          := PickleballConstants.OVERHEAD_RELEASE_RADIUS

# ── Ghost visual constants ───────────────────────────────────────────────────
const POSTURE_GHOST_ALPHA              := 0.12
const POSTURE_GHOST_ACTIVE_ALPHA       := 0.3
const POSTURE_GHOST_NEAR_ALPHA         := 0.55
const POSTURE_GHOST_NEAR_EMISSION      := 1.8
const POSTURE_GHOST_NEAR_RADIUS        := 0.3
const POSTURE_GHOST_SCALE              := Vector3(0.92, 0.92, 0.92)

# ── Commit stage timing ───────────────────────────────────────────────────────
const BLUE_HOLD_DURATION               := 0.35   # hold blue for at least this long once triggered
const TTC_BLUE                         := 0.2    # seconds-to-contact threshold for BLUE latch
const TTC_PURPLE                       := 0.8    # seconds-to-contact threshold for PURPLE
const BLUE_DIST_FALLBACK               := 0.35   # physical ball-to-ghost fallback for BLUE latch
const POSTURE_HOLD_MIN                 := 0.3    # minimum seconds before allowing posture switch
const INCOMING_GLOW_DURATION           := 1.5
const INCOMING_FADE_DURATION           := 0.6    # gradual fade back to yellow after glow expires
const GHOST_MIN_DISTANCE               := 0.18   # anti-overlap: minimum center-to-center
const GHOST_LERP_SPEED                 := 8.0
const GHOST_TIGHTEN_RATIO              := 0.20   # pull 20% toward committed posture

# ── Debug ────────────────────────────────────────────────────────────────────
## Debug posture name lookup — indexed by PaddlePosture enum value (0-20)
const DEBUG_POSTURE_NAMES: Array[String] = [
	"FH","FW","BH","MO","HO","LF","LC","LB","CF","CB","WF","WB","VR",
	"MLF","MLB","MLC","MWF","MWB","LWF","LWB",
]
