extends RefCounted
## AutoPose prototype (docs/POSE_STUDIO_SPEC.md Stage 6b): drag one handle (hand, paddle tip,
## elbow, knee, foot, hips, chest, head) to a world point and let the body adapt, solving ANIMATION
## fields only (never GAMEPLAY / paddle fields at Contact) by damped least squares (Levenberg-
## Marquardt) with finite differences on the game's own solved player.
##
## Evaluation = the engine's displayed key pose (preview.pose, a resolved PostureDefinition) with
## candidate values, put through player.posture.force_posture_update (the same call
## preview.show_pose makes: body, legs, paddle placement, arm IK) and the joints read back. No
## preview refresh (ghosts, arc, gizmo, UI) per evaluation. Arm-only columns (elbow guides,
## shoulder rotation, support-hand offset, wind-up / finish paddle) use a cheaper path: paddle
## placement (Path.world_transform) + arm IK only; probe() checks both paths agree.
## Field values map display <-> engine by a per-field offset taken at the drag start
## (display = engine value + offset; wind-up / finish deltas are additive); commit() writes the
## engine values through studio.set_field (stage routing, clamps, foot-plant check) as one undo
## step and reports how far the committed pose is from the solver's prediction.
##
## Pins: both feet (except the dragged foot; opts.unpin frees one), at Contact the paddle grip +
## tip (opts.unpin "paddle" frees it only while the studio's Gameplay edit is on), plus user pins
## (opts.pins: any handle holds its world position at grab). Look-at (opts.look_at, a world point):
## after each move the head turns to it (head yaw / pitch, closed form, no evaluation). Relax
## (relax()): the checker rules (tools/pose_check.py level B) as one-sided goals at this key. Balance (opts.balance, default on): centre of gravity (pose_shots.gd _body_metrics
## weights) pulled toward 5 cm of the line between the ankles, and never left further off than
## max(5 cm, at grab) (_feasible; one-sided rows in _step near the limit). Per-region stiffness = Tikhonov weight toward the drag-start pose, so
## the arm moves first, then chest, then hips / legs. Jacobian: computed once at grab, then
## Broyden rank-1 updates per evaluation ("broyden", for live drags) or recomputed every
## iteration ("fd"). At Contact, fields that measurably move the paddle are frozen (reported).

const Path = preload("res://scripts/stroke_swing_path.gd")
const Fields = preload("res://scripts/ui/mobile_pose_fields.gd")
const Keyframe = preload("res://scripts/stroke_body_keyframe.gd")
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const TIP_LOCAL := Vector3(0, PaddleSize.LENGTH, 0)

# Points read per evaluation (indices).
enum { R_HAND, L_HAND, R_ELBOW, L_ELBOW, R_KNEE, L_KNEE, R_FOOT, L_FOOT, HIPS, TORSO, HEAD, PADDLE,
	TIP, R_ANKLE, L_ANKLE, R_THIGH, L_THIGH, GRIP, R_SHOULDER, L_SHOULDER, R_WRIST, L_WRIST, EDGE_A, EDGE_B, NPTS }
const HANDLES := {"right_hand": R_HAND, "left_hand": L_HAND, "right_elbow": R_ELBOW, "left_elbow": L_ELBOW,
	"right_knee": R_KNEE, "left_knee": L_KNEE, "right_foot": R_FOOT, "left_foot": L_FOOT, "hips": HIPS,
	"torso": TORSO, "chest": TORSO, "head": HEAD, "paddle": PADDLE, "paddle_tip": TIP,
	"right_shoulder": R_SHOULDER, "left_shoulder": L_SHOULDER, "right_hip": R_THIGH, "left_hip": L_THIGH,
	"paddle_edge_a": EDGE_A, "paddle_edge_b": EDGE_B}
## Rotate handles (6c step 4): shoulders turn the upper body only (torso yaw / pitch / roll; hips and
## feet hold), hips turn the pelvis (hip yaw, body pitch / roll; knees follow, feet planted), paddle
## edges (rim, both sides of the head) turn the paddle in the hand along the handle
## (paddle_in_hand_rotation_deg; hand and arm stay; at Contact gameplay, so only with Gameplay edit).
const EDGE_HANDLES := ["paddle_edge_a", "paddle_edge_b"]
const EDGE_A_LOCAL := Vector3(PaddleSize.HEAD_RADIUS, PaddleSize.HEAD_CENTER_Y, 0)
const EDGE_B_LOCAL := Vector3(-PaddleSize.HEAD_RADIUS, PaddleSize.HEAD_CENTER_Y, 0)
## Base stiffness per region (the studio's 1.0x). Tuned 2026-11-20 with W_FOLLOW: a 15 cm hand
## drag moves the chest ~4 cm (median), the hips ~1 cm, the feet 0 (pinned).
const STIFFNESS := {"arm": 1.0, "paddle": 1.0, "head": 1.0, "chest": 3.0, "hips": 16.0, "legs": 8.0, "foot": 2.0}
## Studio stiffness groups (sliders Arms / Torso / Legs) -> solver regions.
const GROUPS := {"arms": ["arm", "paddle"], "torso": ["chest", "head"], "legs": ["hips", "legs", "foot"]}
const RELAX := "relax"         # begin() pseudo handle: Relax (no drag goal, rules instead)
const RELAX_ITERS := 12
const RELAX_BAL := 0.09        # m: Relax pulls the centre of gravity this close to the ankle line (checker flags > 0.15)
const RELAX_PRIOR := 0.25     # Relax: stiffness x this (the drag stiffness would keep a rule broken behind a dead zone)
const RELAX_PROBE := 2.0      # scale units: secant probe for a field with no effect at the FD step (dead zone)
const W_DEG := 0.004           # m per degree: rule rows in degrees weigh like 4 mm per degree (x checker severity)
const LOOK_YAW := 85.0         # deg: head turn limit (player_head_gaze.gd)
const LOOK_UP := 70.0
const LOOK_DOWN := 55.0
const MU := 3e-5             # prior weight (m^2 per unit^2): one scale unit of arm ~ 5 mm of target error
const W_TARGET := 1.0
const W_PIN := 30.0          # 1 mm of pin drift weighs like 3 cm of target error
const W_FOLLOW := 0.15       # hand drags: the shoulder is pulled along with the hand at this weight (x Arms stiffness), so the chest turns / leans a little
const W_BAL := 3.0           # soft pull back toward the free zone (plus a hard rule: never past where the step started)
const BAL_TOL := 5e-4        # m: with balance on, the centre of gravity may not pass the free zone by more than this
const BAND := 0.003          # m: a limit (balance, arm reach) this close is a one-sided constraint in the step (_step)
const REACH_MARGIN := 0.0005 # m: keep a slack arm this far inside its limit (commit safety); a stretched arm has none
const BAL_FREE := 0.05       # m: centre of gravity this far off the ankle line is free (or as far as at grab)
const TOL := 0.01            # m: target reached
const MAX_ITERS := 8
const STEP_UNITS := 1.5      # largest step per iteration (scale units, whole vector)
const CONTACT_COUPLED := 5e-5   # m per unit (0.5 mm per 10 deg / 5 cm): above this a field moves the paddle -> frozen at Contact (FD noise ~5e-6)
const FD_H := 0.02           # finite-difference step (scale units)

var studio
var active := false
var handle := ""
var mode := "broyden"
var scope := "full"
var key := ""
var stage := 1
var info := {}                 # begin report (params, excluded, grab cost)
var _engine
var _player
var _pose0: Resource           # displayed pose at grab
var _cand: Resource            # working candidate (one duplicate per drag)
var _params: Array = []        # [{field, comp, region, lo, hi, scale, off, vec}]
var _x0 := PackedFloat64Array()
var _x_orig := PackedFloat64Array()   # values at grab before automatic guides were seeded (what the engine holds)
var _x := PackedFloat64Array()
var _k := PackedFloat64Array() # per-parameter stiffness
var _frozen := PackedByteArray()
var _J: Array = []             # columns (PackedFloat64Array, m rows)
var _J_ok := false
var _pts0 := PackedVector3Array()
var _pts := PackedVector3Array()   # points at _x
var _goals: Array = []         # [[point index, target, weight]]
var _pins: Array = []          # [[point index, world, weight]]
var _lambda := 0.01
var _evals := 0
var _eval_usec := PackedInt64Array()
var _arm_eval_usec := PackedInt64Array()
var _carry := false
var _guard_cache: Dictionary = {}   # "key|stage|working-copy sig|field[comp]" -> "", "both", "up", "down" (validator probe)
var _carry_axes: Dictionary = {}   # carry mode: POS param index -> world axis (the paddle translates with the elbow)
var _rel: Array = []               # carry mode: [[point a, point b, (a - b) at grab, weight]]: hand / tip keep their offset from the elbow
var _follow: Array = []            # hand drags: [[hand, shoulder, (hand - shoulder) at grab, weight]]: soft, the body follows the hand a little
var _sig := ""
var _bal_free := BAL_FREE
var _reach: Array = []         # [[shoulder idx, wrist idx, limit m, margin m]]: the engine's torso-turn check (no arm over-reach)
var _balance_on := true        # balance soft goal + never-worse rule (opts.balance)
var _pred_gain := 0.0          # cost decrease the linear model predicts for the last _step
var _ineq: Array = []
var _arm_path := true          # arm / paddle columns by the arm-only path (false: the body follows the arm here)          # [[d(value)/d(unit) per param, weight]]: limits within BAND, not yet passed (_rjac -> _step)
var budget_usec := 0           # > 0: stop iterating a move after this long (live drags); 0 = converge
var pinned: Array = []         # handle ids pinned for this drag (user pins; feet / Contact paddle reported separately)
var _paddle_free := false      # Contact paddle unpinned (Gameplay edit on and opts.unpin has "paddle")
var _look_at := Vector3.INF    # head look-at point (world); INF = off
var _look_idx := PackedInt32Array()   # [yaw param, pitch param] (frozen in the solve, set by _apply_look)
var _rules: Array = []         # Relax: [[name, metric, "min"|"max"|"absmax", limit, weight]]
var _pop := {}                 # Relax: hip heights of the other keys ({windup, contact, finish} -> y) for the pop-up rule

func _init(owner_studio) -> void:
	studio = owner_studio

# ---------------------------------------------------------------- evaluation

func _read() -> PackedVector3Array:
	var p = _player
	var out := PackedVector3Array(); out.resize(NPTS)
	out[R_HAND] = p.right_arm_node.hand_pivot.global_position
	out[L_HAND] = p.left_arm_node.hand_pivot.global_position
	out[R_ELBOW] = preload("res://scripts/elbow_swivel.gd").visual_elbow_now(p.right_arm_node)   # drawn elbow (authored swivel)
	out[L_ELBOW] = preload("res://scripts/elbow_swivel.gd").visual_elbow_now(p.left_arm_node)
	out[R_KNEE] = p.right_leg_node.shin_pivot.global_position
	out[L_KNEE] = p.left_leg_node.shin_pivot.global_position
	out[R_FOOT] = p.right_leg_node.foot_mesh.global_position
	out[L_FOOT] = p.left_leg_node.foot_mesh.global_position
	out[HIPS] = p.body_pivot.get_node("HipsMesh").global_position
	out[TORSO] = p.body_pivot.get_node("TorsoMesh").global_position
	out[HEAD] = p.body_pivot.get_node("TorsoMesh/HeadMesh").global_position
	var pt: Transform3D = p.paddle_node.global_transform
	out[PADDLE] = p.paddle_node.get_node("Head").global_position
	out[TIP] = pt * TIP_LOCAL
	out[R_ANKLE] = p.right_leg_node.foot_pivot.global_position
	out[L_ANKLE] = p.left_leg_node.foot_pivot.global_position
	out[R_THIGH] = p.right_leg_node.thigh_pivot.global_position
	out[L_THIGH] = p.left_leg_node.thigh_pivot.global_position
	out[GRIP] = pt.origin
	out[R_SHOULDER] = p.right_arm_node.upper_pivot.global_position
	out[L_SHOULDER] = p.left_arm_node.upper_pivot.global_position
	out[R_WRIST] = p.right_arm_node.anatomical_wrist_world
	out[L_WRIST] = p.left_arm_node.anatomical_wrist_world
	out[EDGE_A] = pt * EDGE_A_LOCAL
	out[EDGE_B] = pt * EDGE_B_LOCAL
	return out

## World points of every handle on `player` as it stands now (no evaluation): the AutoPose
## drag UI draws its handles here, so a handle sits exactly on the point the solver moves.
func handle_points(player) -> Dictionary:
	if player == null or not is_instance_valid(player): return {}
	var keep = _player
	_player = player
	var pts := _read()
	_player = keep
	var out := {}
	for h in HANDLES: out[h] = pts[HANDLES[h]]
	return out

## How far the dragged handle can move per scale unit of any free field (m), from the grab
## Jacobian: ~0 = no animation field moves it at this pose (e.g. a body stance's paddle hand,
## which rides the paddle). Elbow carry also moves it (the paddle travels with the elbow).
func handle_mobility() -> float:
	if not active: return 0.0
	var o: int = _pt_row(HANDLES[handle])
	var m := 0.0
	for i in _params.size():
		if _frozen[i]: continue
		var col: PackedFloat64Array = _J[i]
		m = maxf(m, Vector3(col[o], col[o + 1], col[o + 2]).length())
	return m

func _apply(x: PackedFloat64Array) -> void:
	for i in _params.size():
		var pr: Dictionary = _params[i]
		if pr.comp < 0: _cand.set(pr.field, x[i])
		else:
			var v: Vector3 = _cand.get(pr.field); v[pr.comp] = x[i]; _cand.set(pr.field, v)

## The rig keeps float32 noise between solves: the arm IK's look_at / rotation setters keep the
## pivots' previous scale (~1e-7) and the sole-above-floor fix (global_position setter) leaves
## roundoff in the foot mesh basis (1 ulp). So the same candidate could give slightly different
## joints depending on what was solved before, and the solver (ill-conditioned directions,
## accept / reject decisions) turns that into cm. Reset those bases first, so an evaluation
## depends on the candidate only (the same drag replays the same way). Engine nodes are only
## reset to their nominal frames (the solvers rebuild them anyway); no node is added.
var _foot_basis: Array = []
func _canon_arms() -> void:
	for arm in [_player.right_arm_node, _player.left_arm_node]:
		arm.upper_pivot.basis = Basis.IDENTITY
		arm.forearm_pivot.basis = Basis.IDENTITY
		arm.hand_pivot.basis = Basis.IDENTITY
	var legs := [_player.right_leg_node, _player.left_leg_node]
	if _foot_basis.size() != 2:
		_foot_basis = []
		for lg in legs:   # the scene's nominal frame (noise snapped away)
			var b: Basis = lg.foot_mesh.basis
			_foot_basis.append(Basis(b.x.snapped(Vector3.ONE * 1e-5), b.y.snapped(Vector3.ONE * 1e-5), b.z.snapped(Vector3.ONE * 1e-5)))
	for side in 2: legs[side].foot_mesh.basis = _foot_basis[side]

## Full evaluation: the game's own body + legs + paddle + arm solve for the candidate.
func _eval(x: PackedFloat64Array) -> PackedVector3Array:
	var t0 := Time.get_ticks_usec()
	_apply(x)
	_canon_arms()
	_player.posture.force_posture_update(_cand)
	var pts := _read()
	_eval_usec.append(Time.get_ticks_usec() - t0)
	_evals += 1
	return pts

## Arm-only evaluation (body and legs unchanged since the last full one): paddle placement + arm IK.
func _eval_arm(x: PackedFloat64Array) -> PackedVector3Array:
	var t0 := Time.get_ticks_usec()
	_apply(x)
	_canon_arms()
	_player.paddle_node.global_transform = Path.world_transform(_player, _cand)
	_player.arm_ik.update_arm_ik(0.0, _cand)
	var pts := _read()
	_arm_eval_usec.append(Time.get_ticks_usec() - t0)
	_evals += 1
	return pts

# ---------------------------------------------------------------- parameters

func _p(list: Array, field: String, region: String, scale: float, comps := -1) -> void:
	var ed = _engine
	if ed._edit.get(field) == null or _pose0.get(field) == null: return
	if ed._serve and not ed.ServeStore.is_field_editable(stage, field): return   # serve keys keep only their own fields
	if stage != 1 and not (field in Keyframe.FIELDS or field in ed.POS or field in ed.ROT): return   # would write the shared base
	if stage == 1 and (field in ed.POS or field in studio.FACE_FIELDS) and not _paddle_free: return   # Contact paddle: gameplay (free with Gameplay edit)
	if field in studio.GAMEPLAY_FIELDS and not (field in ed.POS and (stage != 1 or _paddle_free)): return   # wind-up / finish POS = deltas; Contact POS only when freed
	var d: Dictionary = studio._descriptor(field)
	if d.is_empty(): return
	for c in (range(3) if comps == 3 else [-1]):
		var disp = _pose0.get(field)
		var edv = ed._edit.get(field)
		var dv: float = float(disp) if c < 0 else float(disp[c])
		var ev: float = float(edv) if c < 0 else float(edv[c])
		var off: float = dv - ev
		var lo: float = float(d.min) + off
		var hi: float = float(d.max) + off
		if stage != 1 and (field in ed.ROT or field == "paddle_in_hand_rotation_deg"):   # wrapping angles at wind-up / finish: half a turn either way
			lo = dv - 180.0; hi = dv + 180.0
		list.append({"field": field, "comp": c, "region": region, "scale": scale, "off": off, "lo": lo, "hi": hi})

func _build_params(main: String) -> Array:
	var sup := "left" if main == "right" else "right"
	var arm := func(list: Array, side: String) -> void:
		_p(list, side + "_elbow_pole", "arm", 0.25, 3)
		_p(list, side + "_shoulder_rotation_deg", "arm", 10.0, 3)
		_p(list, side + "_elbow_swivel_deg", "arm", 15.0)   # the drawn elbow (scripts/elbow_swivel.gd)
	var paddle := func(list: Array) -> void:
		if stage == 1 and not _paddle_free: return   # Contact paddle moves only with Gameplay edit
		for f in _engine.POS: _p(list, f, "paddle", 0.05)
		_p(list, "paddle_pitch_base_deg", "paddle", 10.0); _p(list, "paddle_yaw_base_deg", "paddle", 10.0)
	var chest := func(list: Array) -> void:
		for f in ["torso_yaw_deg", "torso_pitch_deg", "torso_roll_deg", "spine_curve_deg"]: _p(list, f, "chest", 10.0)
		_p(list, "shoulder_protraction_m", "chest", 0.01)
	var hips := func(list: Array) -> void:
		for f in ["hip_yaw_deg", "body_pitch_deg", "body_roll_deg"]: _p(list, f, "hips", 10.0)
		_p(list, "weight_shift", "hips", 0.25); _p(list, "crouch_amount", "hips", 0.05)
		_p(list, "body_position_offset", "hips", 0.05, 3)
	var legs := func(list: Array) -> void:
		_p(list, "right_knee_pole", "legs", 0.25, 3); _p(list, "left_knee_pole", "legs", 0.25, 3)
	var out: Array = []
	var h := handle
	var full := scope == "full"
	if h == RELAX:   # Relax: the body and both arms (paddle and feet stay; the head only by look-at)
		arm.call(out, main); arm.call(out, sup); chest.call(out); hips.call(out); legs.call(out)
	elif h == main + "_hand" or h == "paddle_tip" or h == "paddle":
		paddle.call(out); arm.call(out, main)
		if full: chest.call(out); hips.call(out)
	elif h == main + "_elbow":
		arm.call(out, main); paddle.call(out)
		if full: chest.call(out); hips.call(out)
	elif h == sup + "_hand" or h == sup + "_elbow":
		arm.call(out, sup)
		if h == sup + "_hand": _p(out, sup + "_hand_offset", "arm", 0.05, 3)
		if full: chest.call(out); hips.call(out)
	elif h == "hips":
		hips.call(out); legs.call(out); chest.call(out)
	elif h.ends_with("_shoulder"):   # rotate the upper body: hips and feet hold
		for f in ["torso_yaw_deg", "torso_pitch_deg", "torso_roll_deg"]: _p(out, f, "chest", 10.0)
	elif h.ends_with("_hip"):   # rotate the pelvis: the knees follow, feet stay planted
		for f in ["hip_yaw_deg", "body_pitch_deg", "body_roll_deg"]: _p(out, f, "hips", 10.0)
		legs.call(out)
	elif h in EDGE_HANDLES:   # roll the face around the handle (Contact: gameplay, _p skips it unless freed)
		# Turn the paddle in the hand (paddle_in_hand_rotation_deg: about the handle's long axis
		# through the grip), so the hand and arm IK stay as they are; grip and tip pinned (begin).
		# Serves keep the paddle's world angle when the in-hand turn changes (the serve store
		# compensates it), so they turn the face with the three paddle angles: grip and tip
		# pinned, the only freedom left is the turn around the handle.
		if _engine._serve:
			for f in ["paddle_pitch_base_deg", "paddle_yaw_base_deg", "paddle_roll_base_deg"]: _p(out, f, "paddle", 10.0)
		else: _p(out, "paddle_in_hand_rotation_deg", "paddle", 10.0)
	elif h == "torso" or h == "chest":
		chest.call(out); hips.call(out)
	elif h == "head":
		_p(out, "head_yaw_deg", "head", 10.0); _p(out, "head_pitch_deg", "head", 10.0)
		if full: chest.call(out)
	elif h.ends_with("_knee"):
		_p(out, h.trim_suffix("_knee") + "_knee_pole", "legs", 0.25, 3)
		if full: hips.call(out)
	elif h.ends_with("_foot"):
		_p(out, h.trim_suffix("_foot") + "_foot_offset", "foot", 0.05, 3)
		_p(out, h.trim_suffix("_foot") + "_knee_pole", "legs", 0.25, 3)
		if full: hips.call(out)
	if _look_at.is_finite() and h != "head":   # look-at: set after each move, not solved
		_p(out, "head_yaw_deg", "look", 10.0); _p(out, "head_pitch_deg", "look", 10.0)
	return out

# ---------------------------------------------------------------- session

## Start a drag on `h` at the current key. opts: mode (broyden | fd), scope (full | arm),
## stiffness {region: multiplier}, pins [{joint, point?}]. Returns {ok, ...} or {ok: false, error}.
func begin(h: String, opts: Dictionary = {}) -> Dictionary:
	if active: release(false)
	_engine = studio.engine
	if _engine == null or studio.key == "": return {"ok": false, "error": "no pose selected"}
	if not HANDLES.has(h) and h != RELAX: return {"ok": false, "error": "unknown handle: " + h}
	if not studio.at_key(): return {"ok": false, "error": "not at a key (wind-up, contact, finish)"}
	handle = h
	mode = str(opts.get("mode", "broyden"))
	scope = str(opts.get("scope", "full"))
	key = studio.key
	stage = _engine._stage
	var main: String = "left" if studio.main_hand_id() == "left_hand" else "right"
	var sup: String = "right" if main == "left" else "left"
	var unpin_paddle: bool = (opts.get("unpin", []) is Array and (opts.get("unpin") as Array).has("paddle")) and bool(studio.gameplay_edit)
	if stage == 1 and not _engine._base and (h == main + "_hand" or h == "paddle_tip" or h == "paddle" or h in EDGE_HANDLES) and not unpin_paddle:
		return {"ok": false, "error": "pinned at Contact: the paddle hand and paddle are the contact point (gameplay); Gameplay edit frees it", "locked": true}
	var t0 := Time.get_ticks_usec()
	_player = studio.preview.player
	_pose0 = studio.preview.pose
	if _pose0 == null: return {"ok": false, "error": "no displayed pose"}
	_cand = _pose0.duplicate(true)
	# User pins (handle ids; the dragged handle is never pinned against itself).
	pinned = []
	for up in opts.get("pins", []):
		var pj: String = str(up.get("joint", "")) if up is Dictionary else str(up)
		if pj == "torso": pj = "chest"
		if HANDLES.has(pj) and pj != h and not (pj == "chest" and h == "torso") and not pinned.has(pj): pinned.append(pj)
	var unpin: Array = opts.get("unpin", []) if opts.get("unpin") is Array else []
	_paddle_free = stage == 1 and not _engine._base and unpin.has("paddle") and bool(studio.gameplay_edit)
	# Elbow carry needs the hand and paddle free to travel: a pinned paddle hand / tip reshapes instead.
	_carry = h == main + "_elbow" and stage != 1 and not pinned.has(main + "_hand") and not pinned.has("paddle_tip")
	_balance_on = bool(opts.get("balance", true))
	var la = opts.get("look_at")
	_look_at = Vector3.INF
	if la is Vector3: _look_at = la
	elif la is Array and la.size() == 3: _look_at = Vector3(float(la[0]), float(la[1]), float(la[2]))
	_evals = 0; _eval_usec.clear(); _arm_eval_usec.clear(); _lambda = 0.01
	_params = _build_params(main)
	var n := _params.size()
	if n == 0: return {"ok": false, "error": "no animation fields to solve for " + h}
	_x0.resize(n); _k.resize(n); _frozen.resize(n); _frozen.fill(0)
	_look_idx = PackedInt32Array()
	for i in n:   # look-at fields: frozen for the solve, set after each move (_apply_look)
		if _params[i].region == "look": _frozen[i] = 1; _look_idx.append(i)
	if _look_idx.size() != 2: _look_idx = PackedInt32Array()
	var stiff: Dictionary = opts.get("stiffness", {}) if opts.get("stiffness") is Dictionary else {}
	for i in n:
		var pr: Dictionary = _params[i]
		var v = _cand.get(pr.field)
		_x0[i] = float(v) if pr.comp < 0 else float(v[pr.comp])
		# multiplier = all x group (arms / torso / legs) x region (arm, paddle, chest, head, hips, legs, foot)
		var gm := 1.0
		for g in GROUPS:
			if pr.region in GROUPS[g]: gm = float(stiff.get(g, 1.0))
		_k[i] = float(STIFFNESS.get(pr.region, 1.0)) * float(stiff.get("all", 1.0)) * gm * float(stiff.get(pr.region, 1.0))
	# Automatic guides (zero poles) seeded like the engine gizmo; kept only if nothing jumps.
	# The engine's foot-plant / reach check (mobile_pose_editor _body_edit_limit, what set_field
	# runs): a guarded field it refuses both ways is frozen, one way = that bound becomes the start.
	var guarded: Array = []
	var sig: String = studio._sig(_engine._current)
	if _guard_cache.size() > 2000: _guard_cache.clear()
	var probes := 0
	for i in n:
		var pr: Dictionary = _params[i]
		if not (pr.field in _engine.FOOT_GUARDED_FIELDS): continue
		var ck := "%s|%d|%s|%s" % [key, stage, sig, _pname(i)]
		var res: String
		if _guard_cache.has(ck): res = _guard_cache[ck]
		else:
			var d: Dictionary = studio._descriptor(pr.field)
			var ev: float = _x0[i] - float(pr.off)
			var up_ok: bool = _engine._body_edit_limit(d, pr.comp, minf(ev + 0.25 * float(pr.scale), float(d.max))) == ""
			var dn_ok: bool = _engine._body_edit_limit(d, pr.comp, maxf(ev - 0.25 * float(pr.scale), float(d.min))) == ""
			res = "" if up_ok and dn_ok else "both" if not up_ok and not dn_ok else "up" if not up_ok else "down"
			_guard_cache[ck] = res; probes += 2
		match res:
			"both": _frozen[i] = 1
			"up": pr.hi = _x0[i]
			"down": pr.lo = _x0[i]
		if res != "": guarded.append({"field": _pname(i), "refused": res})
	# Clean start: the validator probes above (and a previous drag) leave the rig on another pose;
	# show the displayed pose again through the engine, then evaluate from canonical arms (_eval).
	_engine._refresh_preview()
	var preview_pts := _read()
	_x_orig = _x0.duplicate()
	_pts0 = _eval(_x0)
	var seeded: Array = []
	for i in n:
		var pr: Dictionary = _params[i]
		if not str(pr.field).ends_with("_pole") or pr.comp != 0: continue
		var cur: Vector3 = Vector3(_x0[i], _x0[i + 1], _x0[i + 2])
		if cur.length_squared() > 1e-8: continue
		var guide := Vector3(0, .5, 1) if str(pr.field).contains("knee") else Vector3(-.5 if str(pr.field).begins_with("left") else .5, -1, -.5)
		var xs := _x0.duplicate()
		for c in 3: xs[i + c] = guide[c]
		var jump := _max_move(_eval(xs), _pts0)
		if jump < 0.001:
			for c in 3: _x0[i + c] = guide[c]
			seeded.append({"field": pr.field, "jump_m": jump})
		else:
			for c in 3: _frozen[i + c] = 1
			seeded.append({"field": pr.field, "jump_m": jump, "frozen": true})
	_x = _x0.duplicate()
	_pts0 = _eval(_x)
	_pts = _pts0
	# Pins: feet (not the dragged one), Contact paddle grip + tip, user pins.
	_pins = []
	for pi in [R_FOOT, R_ANKLE, L_FOOT, L_ANKLE]:
		var side: String = "right_foot" if pi in [R_FOOT, R_ANKLE] else "left_foot"
		if h == side or (unpin.has(side) and not pinned.has(side)): continue
		_pins.append([pi, _pts0[pi], W_PIN])
	if (stage == 1 and not _engine._base and not _paddle_free) or h in EDGE_HANDLES:   # edges: roll along the handle
		_pins.append([GRIP, _pts0[GRIP], W_PIN]); _pins.append([TIP, _pts0[TIP], W_PIN])
	for up in opts.get("pins", []):
		var pj: String = str(up.get("joint", "")) if up is Dictionary else str(up)
		if pj == "torso": pj = "chest"
		if not pinned.has(pj) or pj.ends_with("_foot"): continue   # feet: the foot pins above
		var idx: int = HANDLES[pj]
		var at: Vector3 = _pts0[idx]
		var w = up.get("point") if up is Dictionary else null
		if w is Array and w.size() == 3: at = Vector3(float(w[0]), float(w[1]), float(w[2]))
		_pins.append([idx, at, W_PIN])
	_goals = []
	_reach = []
	_bal_free = maxf(BAL_FREE, float(balance(_pts0).off_m))   # never pull a pose toward balance it did not have: only stop it getting worse
	_arm_path = _arm_path_check()
	_compute_J()
	var grab_evals := _evals
	# At Contact: freeze fields that move the paddle (reach clamp), measured from the Jacobian.
	var excluded: Array = []
	if stage == 1 and not _engine._base and not _paddle_free:
		for i in n:
			var col: PackedFloat64Array = _J[i]
			var mv := _pin_motion(col, [GRIP, TIP])
			if mv > CONTACT_COUPLED and _frozen[i] == 0:
				_frozen[i] = 1; excluded.append({"field": _pname(i), "paddle_m_per_unit": mv})
	# Elbow carry (wind-up / finish): forearm, hand and paddle keep their relation to the elbow.
	# Each move first translates the paddle by the mouse's elbow offset (warm start: POS is linear
	# in the stance axes), then the solve keeps hand - elbow and tip - elbow as at grab (relation
	# pins, POS free, paddle angles frozen) while the elbow goes to the target, so where the elbow
	# cannot follow (balance, reach) the hand and paddle stop with it instead of running ahead;
	# the body (shoulder, chest) follows.
	_carry_axes = {}
	_rel = []
	if _carry:
		var axes := {"paddle_forehand_mul": _player._get_forehand_axis(), "paddle_y_offset": Vector3.UP,
			"paddle_forward_mul": _player._get_forward_axis()}
		for i in n:
			if _params[i].region == "paddle":
				if axes.has(_params[i].field): _carry_axes[i] = axes[_params[i].field]
				else: _frozen[i] = 1
		var hand_i: int = R_HAND if main == "right" else L_HAND
		var elbow_i: int = R_ELBOW if main == "right" else L_ELBOW
		_rel = [[hand_i, elbow_i, _pts0[hand_i] - _pts0[elbow_i], W_PIN], [TIP, elbow_i, _pts0[TIP] - _pts0[elbow_i], W_PIN]]
	# Body follow (hand / paddle tip drags): the arm keeps a little of its shape (hand - shoulder
	# as at grab, weight W_FOLLOW x the Arms stiffness), so the chest turns and leans a little
	# after the hand, the hips less (their stiffness), the feet not at all (pinned). Soft: the
	# hand still goes to the mouse (the paddle fields place it).
	_follow = []
	if scope == "full":
		var fw: float = float(opts.get("follow", W_FOLLOW)) * float(stiff.get("all", 1.0)) * float(stiff.get("arms", 1.0))
		var arm_side := ""
		if h == main + "_hand" or h == "paddle_tip": arm_side = main
		elif h == sup + "_hand": arm_side = sup
		if arm_side != "" and fw > 0.0:
			var hi2: int = R_HAND if arm_side == "right" else L_HAND
			var si: int = R_SHOULDER if arm_side == "right" else L_SHOULDER
			_follow = [[hi2, si, _pts0[hi2] - _pts0[si], fw]]
	# The engine refuses a torso turn that stretches an arm past max(arm length, its stretch now)
	# (mobile_pose_editor _body_edit_limit): keep that as a constraint so commit() is not stopped,
	# only while the torso turn is a free field (the engine checks it on that field alone).
	var yaw_free := false
	for i in n:
		if _params[i].field == "torso_yaw_deg" and not _frozen[i]: yaw_free = true
	if yaw_free:
		for side in [[R_SHOULDER, R_WRIST, _player.right_arm_node], [L_SHOULDER, L_WRIST, _player.left_arm_node]]:
			var arm = side[2]
			var reach0: float = _pts0[side[0]].distance_to(_pts0[side[1]])
			var lim: float = maxf(arm.upper_arm_length + arm.forearm_length, reach0)
			# A slack arm keeps a small safety margin; an arm already at its limit gets none (no pull).
			_reach.append([side[0], side[1], lim, clampf(lim - reach0, 0.0, REACH_MARGIN)])
	_sig = sig
	active = true
	var plist: Array = []
	for i in n: plist.append(_pname(i))
	info = {"ok": true, "handle": h, "stage": ["windup", "contact", "finish"][stage], "key": key, "mode": mode, "scope": scope,
		"params": plist, "n": n, "frozen": _frozen_names(), "contact_excluded": excluded, "seeded_guides": seeded, "validator_refused": guarded, "validator_probes": probes,
		"grab_usec": Time.get_ticks_usec() - t0, "grab_evals": grab_evals, "carry": _carry, "balance": _balance_on, "arm_path": _arm_path,
		"baseline_vs_preview_m": _max_move(_pts0, preview_pts), "handle_start": _pts0[HANDLES[h]] if HANDLES.has(h) else null,
		"pins": pinned.duplicate(), "feet_pinned": [_foot_pinned(R_FOOT), _foot_pinned(L_FOOT)],
		"paddle_pinned": stage == 1 and not _engine._base and not _paddle_free, "paddle_free": _paddle_free,
		"look": not _look_idx.is_empty(), "look_at": _look_at if _look_at.is_finite() else null}
	return info

func _foot_pinned(idx: int) -> bool:
	for pn in _pins:
		if pn[0] == idx: return true
	return false

## Look-at: turn the head (yaw / pitch fields) toward _look_at from the torso as it stands now,
## the same frame and limits as the game's ball gaze (player_head_gaze.gd local_gaze_basis), and
## set the head node like stroke_body_pose.apply does (head rotation moves no solver point, so
## no evaluation). Returns the angle left between the face and the point (deg; > 0 when a
## limit holds it), or -1 when off.
func _apply_look() -> float:
	if _look_idx.is_empty() or not _look_at.is_finite(): return -1.0
	var torso: Node3D = _player.body_pivot.get_node("TorsoMesh")
	var head: Node3D = torso.get_node("HeadMesh")
	var dir: Vector3 = _look_at - head.global_position
	if dir.length_squared() < 1e-6: return -1.0
	var tb: Basis = torso.global_transform.basis.orthonormalized()
	var local: Vector3 = tb.inverse() * dir.normalized()
	var fwd: Vector3 = _player._get_forward_axis()
	var flat := Vector3(local.x, 0, local.z)
	var yaw: float = fwd.signed_angle_to(flat.normalized(), Vector3.UP) if flat.length_squared() > 1e-6 else 0.0
	var pitch: float = atan2(local.y, maxf(flat.length(), 1e-5))
	yaw = clampf(yaw, -deg_to_rad(LOOK_YAW), deg_to_rad(LOOK_YAW))
	pitch = clampf(pitch, -deg_to_rad(LOOK_DOWN), deg_to_rad(LOOK_UP))
	var s: float = _player._get_swing_sign()
	var yi: int = _look_idx[0] if str(_params[_look_idx[0]].field) == "head_yaw_deg" else _look_idx[1]
	var pi: int = _look_idx[1] if yi == _look_idx[0] else _look_idx[0]
	_x[yi] = clampf(-rad_to_deg(yaw), float(_params[yi].lo), float(_params[yi].hi))
	_x[pi] = clampf(rad_to_deg(pitch * -fwd.z) / s, float(_params[pi].lo), float(_params[pi].hi))
	_cand.set("head_yaw_deg", _x[yi]); _cand.set("head_pitch_deg", _x[pi])
	head.rotation_degrees = Vector3(_x[pi] * s, -_x[yi], 0)
	var face: Vector3 = head.global_transform.basis.orthonormalized() * fwd
	return rad_to_deg(face.angle_to(dir))

func _pname(i: int) -> String:
	var pr: Dictionary = _params[i]
	return str(pr.field) + ("" if pr.comp < 0 else "[%d]" % pr.comp)

func _frozen_names() -> Array:
	var out: Array = []
	for i in _params.size():
		if _frozen[i]: out.append(_pname(i))
	return out

func _max_move(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var m := 0.0
	for i in mini(a.size(), b.size()): m = maxf(m, a[i].distance_to(b[i]))
	return m

## Largest motion (m per unit) of the given points in a Jacobian column (pin rows are not in
## the column layout, so this re-derives it from the stored per-point deltas).
func _pin_motion(col: PackedFloat64Array, idxs: Array) -> float:
	var m := 0.0
	for idx in idxs:
		var o: int = _pt_row(idx)
		if o >= 0: m = maxf(m, Vector3(col[o], col[o + 1], col[o + 2]).length())
	return m

# Jacobian rows: every point (NPTS * 3, raw metres per unit) - residuals are built from them, so
# goals / pins can change per move without recomputing columns.
func _pt_row(idx: int) -> int: return idx * 3

func _compute_J() -> void:
	var n := _params.size()
	_J.resize(n)
	# The player must stand at _x for the arm-only columns (they keep the body as it is).
	_pts = _eval(_x)
	var base := _flat(_pts)
	var order: Array = []
	for i in n:
		if _params[i].region == "arm" or _params[i].region == "paddle": order.push_front(i)
		else: order.append(i)
	for i in order:
		var col := PackedFloat64Array(); col.resize(NPTS * 3)
		if _frozen[i]: _J[i] = col; continue
		var pr: Dictionary = _params[i]
		var h: float = FD_H * float(pr.scale)
		var xs := _x.duplicate()
		if xs[i] + h > float(pr.hi): h = -h
		xs[i] += h
		var arm_only: bool = _arm_path and (pr.region == "arm" or pr.region == "paddle")
		var pts := _eval_arm(xs) if arm_only else _eval(xs)
		var f := _flat(pts)
		var sgn := 1.0 if h > 0 else -1.0
		for r in col.size(): col[r] = (f[r] - base[r]) / FD_H * sgn
		_J[i] = col
	_J_ok = true

## Does the arm-only path hold at this pose? Some poses move the body with the paddle / arm
## (reach clamp at a stretched arm), and arm-only columns would then miss the body (and the
## balance) and mislead every step. One combined arm / paddle perturbation, both paths.
func _arm_path_check() -> bool:
	var xs := _x.duplicate()
	var any := false
	for i in _params.size():
		var pr: Dictionary = _params[i]
		if _frozen[i] or not (pr.region == "arm" or pr.region == "paddle"): continue
		var h: float = 0.2 * float(pr.scale)
		xs[i] = xs[i] + h if xs[i] + h <= float(pr.hi) else xs[i] - h
		any = true
	if not any: return true
	_eval(_x)
	var pa := _eval_arm(xs)
	var pf := _eval(xs)
	return _max_move(pa, pf) < 1e-5

func _flat(pts: PackedVector3Array) -> PackedFloat64Array:
	var f := PackedFloat64Array(); f.resize(NPTS * 3)
	for i in NPTS:
		f[i * 3] = pts[i].x; f[i * 3 + 1] = pts[i].y; f[i * 3 + 2] = pts[i].z
	return f

# ---------------------------------------------------------------- residuals

func _com(p: PackedVector3Array) -> Vector3:
	return p[HIPS] * 0.40 + p[TORSO] * 0.30 + p[HEAD] * 0.08 \
		+ ((p[L_THIGH] + p[L_KNEE]) * 0.5 + (p[R_THIGH] + p[R_KNEE]) * 0.5) * 0.08 \
		+ ((p[L_KNEE] + p[L_ANKLE]) * 0.5 + (p[R_KNEE] + p[R_ANKLE]) * 0.5) * 0.03

## Horizontal offset of the centre of gravity from the ankle line (m, xz) and t along it.
func balance(p: PackedVector3Array) -> Dictionary:
	var com := _com(p)
	var a := Vector2(p[L_ANKLE].x, p[L_ANKLE].z)
	var b := Vector2(p[R_ANKLE].x, p[R_ANKLE].z)
	var c := Vector2(com.x, com.z)
	var ab := b - a
	var t: float = clampf((c - a).dot(ab) / maxf(ab.length_squared(), 1e-4), 0.0, 1.0)
	var off: Vector2 = c - (a + ab * t)
	return {"off": off, "off_m": off.length(), "t": t}

## Residual vector (weighted) from the points.
func _residual(p: PackedVector3Array) -> PackedFloat64Array:
	var r := PackedFloat64Array()
	for g in _goals:
		var d: Vector3 = (p[g[0]] - g[1]) * float(g[2])
		r.append(d.x); r.append(d.y); r.append(d.z)
	for pn in _pins:
		var d2: Vector3 = (p[pn[0]] - pn[1]) * float(pn[2])
		r.append(d2.x); r.append(d2.y); r.append(d2.z)
	for rl in _rel:
		var d3: Vector3 = (p[rl[0]] - p[rl[1]] - rl[2]) * float(rl[3])
		r.append(d3.x); r.append(d3.y); r.append(d3.z)
	for fl in _follow:
		var d4: Vector3 = (p[fl[0]] - p[fl[1]] - fl[2]) * float(fl[3])
		r.append(d4.x); r.append(d4.y); r.append(d4.z)
	if _balance_on:
		var bal := balance(p)
		var o: Vector2 = bal.off
		var excess: float = maxf(0.0, float(bal.off_m) - _bal_free)
		var dir: Vector2 = o.normalized() if o.length() > 1e-9 else Vector2.ZERO
		r.append(dir.x * excess * W_BAL); r.append(dir.y * excess * W_BAL)
	for rc in _reach:
		r.append(maxf(0.0, p[rc[0]].distance_to(p[rc[1]]) - float(rc[2]) + float(rc[3])) * W_PIN)
	return r

## Hard step rule (a step breaking it is rejected like one that does not lower the cost): with
## balance on, the centre of gravity never ends further off the ankle line than max(free zone,
## where the step started) + BAL_TOL (the tolerance never stacks). Arm reach stays a soft term
## (W_PIN hinge plus the one-sided row in _step): a stretched arm's length is second order in a
## sideways hand move, so a hard rule would stall the hand, and the engine checks only the torso
## turn's own share at commit.
func _feasible(p_new: PackedVector3Array, p_cur: PackedVector3Array) -> bool:
	if _balance_on:
		var bc: float = float(balance(p_cur).off_m)
		var cap: float = _bal_free + BAL_TOL if bc <= _bal_free else bc
		if float(balance(p_new).off_m) > cap: return false
	return true

## Residual Jacobian (rows of _residual) from the point Jacobian columns; balance rows by a
## finite-difference-free linearisation of the centre of gravity (same weights as _com).
func _rjac() -> Array:
	var out: Array = []
	var bal := balance(_pts)
	# d(offset) = d(centre of gravity) - d(closest point on the ankle line): the ankles count with
	# -(1 - t) (left) and -t (right) on top of their centre-of-gravity share (a dragged foot).
	var bt: float = float(bal.t)
	var com_w := {HIPS: 0.40, TORSO: 0.30, HEAD: 0.08, L_THIGH: 0.04, R_THIGH: 0.04,
		L_KNEE: 0.04 + 0.015, R_KNEE: 0.04 + 0.015, L_ANKLE: 0.015 - (1.0 - bt), R_ANKLE: 0.015 - bt}
	var o: Vector2 = bal.off
	var active_bal: bool = _balance_on and float(bal.off_m) > _bal_free
	var dir: Vector2 = o.normalized() if o.length() > 1e-9 else Vector2.ZERO
	# Limits close by but not passed: one-sided constraints the step only uses when it would
	# push toward them (else a step the model sees as free is refused by _feasible: a stall).
	_ineq = []
	var n := _params.size()
	var bal_band: bool = _balance_on and not active_bal and float(bal.off_m) > _bal_free - BAND and dir != Vector2.ZERO
	var bal_a := PackedFloat64Array(); bal_a.resize(n)
	var reach_band: Array = []
	var reach_a: Array = []
	for rq in _reach:
		var gap: float = _pts[rq[0]].distance_to(_pts[rq[1]]) - float(rq[2]) + float(rq[3])
		reach_band.append(gap <= 0.0 and gap > -BAND)
		var ra := PackedFloat64Array(); ra.resize(n); reach_a.append(ra)
	for i in _params.size():
		var col: PackedFloat64Array = _J[i]
		var rc := PackedFloat64Array()
		for g in _goals:
			var o3: int = _pt_row(g[0])
			for c in 3: rc.append(col[o3 + c] * float(g[2]))
		for pn in _pins:
			var o4: int = _pt_row(pn[0])
			for c in 3: rc.append(col[o4 + c] * float(pn[2]))
		for rl in _rel:
			var oa: int = _pt_row(rl[0]); var ob: int = _pt_row(rl[1])
			for c in 3: rc.append((col[oa + c] - col[ob + c]) * float(rl[3]))
		for fl in _follow:
			var fa: int = _pt_row(fl[0]); var fb: int = _pt_row(fl[1])
			for c in 3: rc.append((col[fa + c] - col[fb + c]) * float(fl[3]))
		if active_bal:
			var dc := Vector2.ZERO
			for idx in com_w:
				var o5: int = _pt_row(idx)
				dc += Vector2(col[o5], col[o5 + 2]) * float(com_w[idx])
			# d(excess * dir)/dx ~ dir * (dir . d offset)
			var s: float = dir.dot(dc) * W_BAL
			rc.append(dir.x * s); rc.append(dir.y * s)
		elif _balance_on:
			rc.append(0.0); rc.append(0.0)
			if bal_band:
				var dc2 := Vector2.ZERO
				for idx in com_w:
					var o8: int = _pt_row(idx)
					dc2 += Vector2(col[o8], col[o8 + 2]) * float(com_w[idx])
				bal_a[i] = dir.dot(dc2)
		for qi in _reach.size():
			var rq: Array = _reach[qi]
			var sh: Vector3 = _pts[rq[0]]; var wr: Vector3 = _pts[rq[1]]
			var u: Vector3 = (sh - wr).normalized()
			var o6: int = _pt_row(rq[0]); var o7: int = _pt_row(rq[1])
			var dsh := Vector3(col[o6], col[o6 + 1], col[o6 + 2]); var dwr := Vector3(col[o7], col[o7 + 1], col[o7 + 2])
			if sh.distance_to(wr) - float(rq[2]) + float(rq[3]) <= 0.0:
				rc.append(0.0)
				if reach_band[qi]: reach_a[qi][i] = u.dot(dsh - dwr)
				continue
			rc.append(u.dot(dsh - dwr) * W_PIN)
		out.append(rc)
	if bal_band: _ineq.append([bal_a, W_PIN])
	for qi in _reach.size():
		if reach_band[qi]: _ineq.append([reach_a[qi], W_PIN])
	return out

func _cost(r: PackedFloat64Array, x: PackedFloat64Array) -> float:
	var c := 0.0
	for v in r: c += v * v
	for i in x.size():
		if _frozen[i]: continue   # never moved by the solve (look-at fields are set outside it)
		var u: float = (x[i] - _x0[i]) / float(_params[i].scale)
		c += MU * _k[i] * u * u
	return 0.5 * c

# ---------------------------------------------------------------- one mouse move

## Move the handle toward `target` (world). Returns per-move stats.
func move(target: Vector3) -> Dictionary:
	if not active: return {"ok": false, "error": "no autopose drag (begin first)"}
	if studio.key != key or studio.engine._stage != stage or not studio.at_key() or studio._sig(_engine._current) != _sig:
		release(false); return {"ok": false, "error": "pose, key or working copy changed: drag ended"}
	var t0 := Time.get_ticks_usec()
	var e0 := _evals
	_eval_usec.clear(); _arm_eval_usec.clear()
	var hi: int = HANDLES[handle]
	_goals = [[hi, target, W_TARGET]]
	var n := _params.size()
	if _carry:   # warm start: the paddle translates by the elbow's remaining offset (kept only if it helps)
		var c0 := _cost(_residual(_pts), _x)
		var d: Vector3 = target - _pts[hi]
		for frac in [1.0, 0.5]:
			var x_c := _x.duplicate()
			for i in _carry_axes:
				x_c[i] = clampf(_x[i] + frac * d.dot(_carry_axes[i]), float(_params[i].lo), float(_params[i].hi))
			var p_c := _eval(x_c)
			if mode == "broyden": _broyden(x_c, p_c)
			if _feasible(p_c, _pts) and _cost(_residual(p_c), x_c) < c0:
				_x = x_c; _pts = p_c; break
	var r := _residual(_pts)
	var cost := _cost(r, _x)
	var iters := 0
	var fails := 0
	var rebuilt := 0
	var stop := "max_iters"
	var last_it := 0   # usec of the previous iteration: the budget stops before one that would overrun it
	for it in MAX_ITERS:
		if _pts[hi].distance_to(target) <= TOL and _pins_ok(_pts) and (_follow.is_empty() or it >= 2): stop = "reached"; break   # follow: let the body settle a little
		var t_it := Time.get_ticks_usec()
		if budget_usec > 0 and it > 0 and t_it - t0 + last_it > budget_usec: stop = "budget"; break
		if mode == "fd" or not _J_ok:
			if mode == "broyden" and rebuilt >= 1: stop = "stalled"; break   # one rebuild per move
			# A Jacobian rebuild costs about one evaluation per free field: skip it when it would overrun.
			if budget_usec > 0 and it > 0 and not _eval_usec.is_empty():
				var avg := 0.0
				for u in _eval_usec: avg += u
				avg /= _eval_usec.size()
				var free := 0
				for i in n: free += 0 if _frozen[i] else 1
				if t_it - t0 + avg * float(free) > budget_usec: stop = "budget"; break
			if mode == "broyden": rebuilt += 1
			_compute_J()
		var A := _rjac()
		var x_try := _step(A, r)
		if x_try.is_empty(): stop = "singular"; break
		if _pred_gain < 1e-3 * cost + 1e-10: stop = "converged"; break   # at the best the model sees: no evaluation spent
		var pts_new := _eval(x_try)
		var r_new := _residual(pts_new)
		var c_new := _cost(r_new, x_try)
		if mode == "broyden": _broyden(x_try, pts_new)
		iters += 1
		if not _follow.is_empty() and not _feasible(pts_new, _pts):
			# Body follow is a nicety: when the body part of the step breaks balance, keep the
			# arm / paddle part (the hand still goes to the mouse) and drop the body's share.
			var x_arm := _x.duplicate()
			for i in n:
				if _params[i].region == "arm" or _params[i].region == "paddle": x_arm[i] = x_try[i]
			var p_arm := _eval(x_arm)
			if mode == "broyden": _broyden(x_arm, p_arm)
			var r_arm := _residual(p_arm)
			var c_arm := _cost(r_arm, x_arm)
			if c_arm < cost and _feasible(p_arm, _pts): x_try = x_arm; pts_new = p_arm; r_new = r_arm; c_new = c_arm
		if c_new < cost and _feasible(pts_new, _pts):
			var gain := cost - c_new
			_x = x_try; _pts = pts_new; r = r_new; cost = c_new
			_lambda = maxf(_lambda * 0.3, 1e-6); fails = 0
			if gain < 1e-3 * cost + 1e-10: stop = "converged"; break   # best possible
		else:
			_lambda *= 4.0; fails += 1
			if mode == "broyden" and fails >= 2: _J_ok = false
			if fails >= 4 or _lambda > 1e4: stop = "converged"; break
		last_it = Time.get_ticks_usec() - t_it
	var clamped: Array = []
	for i in n:
		var pr: Dictionary = _params[i]
		if _frozen[i]: continue
		var at_lo: bool = _x[i] <= float(pr.lo) + 1e-9 and _x0[i] > float(pr.lo) + 1e-9
		var at_hi: bool = _x[i] >= float(pr.hi) - 1e-9 and _x0[i] < float(pr.hi) - 1e-9
		if at_lo or at_hi: clamped.append(_pname(i))
	# The player must show the accepted solution (the last evaluation may have been a rejected step).
	var shown := _eval(_x)
	_pts = shown
	var look_err := _apply_look()
	var usec := Time.get_ticks_usec() - t0
	PerfMonitor.record("studio.autopose_move", usec)
	var rep := _report(target, usec, _evals - e0, iters, clamped)
	rep["stop"] = stop; rep["rebuilt_j"] = rebuilt
	if look_err >= 0.0: rep["look_err_deg"] = look_err
	return rep

func _pins_ok(p: PackedVector3Array) -> bool:
	for pn in _pins:
		if p[pn[0]].distance_to(pn[1]) > 0.0005: return false
	for rl in _rel:
		if (p[rl[0]] - p[rl[1]]).distance_to(rl[2]) > 0.0005: return false
	return true

## LM step with box constraints (active set). A field at a bound whose gradient pushes it outward
## is held before the solve; a free field the step would push through a bound it already sits on
## is held and the system solved again (at most n + 1 passes, one more field held each time). The
## result is always the projected step (clamped to the field ranges), never nothing, so a field
## at a one-sided limit cannot stall the drag.
func _step(A: Array, r: PackedFloat64Array) -> PackedFloat64Array:
	var n := _params.size()
	var m := r.size()
	var hold := PackedByteArray(); hold.resize(n)
	var g := PackedFloat64Array(); g.resize(n)
	for i in n:
		hold[i] = _frozen[i]
		if hold[i]: continue
		var ci: PackedFloat64Array = A[i]
		var gi := 0.0
		for k in m: gi += ci[k] * r[k]
		var ui: float = (_x[i] - _x0[i]) / float(_params[i].scale)
		g[i] = gi + MU * _k[i] * ui
		# descent moves x by -g: at the low bound with g > 0 (or the high one with g < 0) it pushes outward
		var pr: Dictionary = _params[i]
		if (g[i] > 0.0 and _x[i] <= float(pr.lo) + 1e-9) or (g[i] < 0.0 and _x[i] >= float(pr.hi) - 1e-9): hold[i] = 1
	# Gauss-Newton matrix of the unfrozen fields, built once (held fields are masked per pass).
	var H0 := PackedFloat64Array(); H0.resize(n * n)
	for i in n:
		if _frozen[i]: continue
		var ci: PackedFloat64Array = A[i]
		for j in range(i, n):
			if _frozen[j]: continue
			var cj: PackedFloat64Array = A[j]
			var s := 0.0
			for k in m: s += ci[k] * cj[k]
			H0[i * n + j] = s; H0[j * n + i] = s
	var x_try := _x.duplicate()
	var on_ineq := PackedByteArray(); on_ineq.resize(_ineq.size())
	for round_n in _ineq.size() + 1:
		var Hb := H0
		if round_n > 0:   # one-sided limits the previous solve pushed toward: held where they are this step
			Hb = H0.duplicate()
			for q in _ineq.size():
				if not on_ineq[q]: continue
				var aq: PackedFloat64Array = _ineq[q][0]
				var w2: float = float(_ineq[q][1]) * float(_ineq[q][1])
				for i in n:
					if aq[i] == 0.0: continue
					for j in n: Hb[i * n + j] += w2 * aq[i] * aq[j]
		x_try = _bounded_step(Hb, g, hold)
		if x_try.is_empty(): return x_try
		var worst := -1
		var worst_v := 1e-7
		for q in _ineq.size():
			if on_ineq[q]: continue
			var aq2: PackedFloat64Array = _ineq[q][0]
			var dv := 0.0
			for i in n: dv += aq2[i] * (x_try[i] - _x[i]) / float(_params[i].scale)
			if dv > worst_v: worst_v = dv; worst = q
		if worst < 0: break
		on_ineq[worst] = 1
	return x_try

## One damped Gauss-Newton solve with the bound active set (see _step); `hold` is updated.
func _bounded_step(H0: PackedFloat64Array, g: PackedFloat64Array, hold: PackedByteArray) -> PackedFloat64Array:
	var n := _params.size()
	var x_try := _x.duplicate()
	for pass_n in n + 1:
		var H := H0.duplicate()
		var gg := g.duplicate()
		for i in n:
			if not hold[i]: continue
			for j in n:
				H[i * n + j] = 0.0; H[j * n + i] = 0.0
			H[i * n + i] = 1.0; gg[i] = 0.0
		for i in n:
			if hold[i]: continue
			H[i * n + i] = (H[i * n + i] + MU * _k[i]) * (1.0 + _lambda) + 1e-9
		var du := _solve(H, gg, n)
		if du.is_empty(): return du
		var len2 := 0.0
		for i in n: len2 += du[i] * du[i]
		var sc: float = minf(1.0, STEP_UNITS / sqrt(maxf(len2, 1e-18)))
		x_try = _x.duplicate()
		var again := false
		_pred_gain = 0.0
		for i in n:
			if hold[i]: continue
			_pred_gain += 0.5 * gg[i] * du[i] * sc
			var pr: Dictionary = _params[i]
			var nv: float = _x[i] - du[i] * sc * float(pr.scale)
			if nv > float(pr.hi):
				if _x[i] >= float(pr.hi) - 1e-9: hold[i] = 1; again = true
				nv = float(pr.hi)
			elif nv < float(pr.lo):
				if _x[i] <= float(pr.lo) + 1e-9: hold[i] = 1; again = true
				nv = float(pr.lo)
			x_try[i] = nv
		if not again: break
	return x_try   # projected step (clamped to the field ranges)

## Gaussian elimination with partial pivoting (n <= ~30).
func _solve(H: PackedFloat64Array, g: PackedFloat64Array, n: int) -> PackedFloat64Array:
	var a := H.duplicate()
	var b := g.duplicate()
	for c in n:
		var piv := c
		for r2 in range(c + 1, n):
			if absf(a[r2 * n + c]) > absf(a[piv * n + c]): piv = r2
		if absf(a[piv * n + c]) < 1e-14: return PackedFloat64Array()
		if piv != c:
			for k in n:
				var tmp: float = a[c * n + k]; a[c * n + k] = a[piv * n + k]; a[piv * n + k] = tmp
			var tb: float = b[c]; b[c] = b[piv]; b[piv] = tb
		var d: float = a[c * n + c]
		for r2 in range(c + 1, n):
			var f: float = a[r2 * n + c] / d
			if f == 0.0: continue
			for k in range(c, n): a[r2 * n + k] -= f * a[c * n + k]
			b[r2] -= f * b[c]
	var x := PackedFloat64Array(); x.resize(n)
	for c in range(n - 1, -1, -1):
		var s: float = b[c]
		for k in range(c + 1, n): s -= a[c * n + k] * x[k]
		x[c] = s / a[c * n + c]
	return x

## Broyden rank-1 update of the point Jacobian from one evaluation (unit space). Each column (a
## packed array, copy on write) is read once for the prediction and written back once.
func _broyden(x_new: PackedFloat64Array, pts_new: PackedVector3Array) -> void:
	var n := _params.size()
	var act := PackedInt32Array()
	var du := PackedFloat64Array()
	var dd := 0.0
	for i in n:
		if _frozen[i]: continue
		var d: float = (x_new[i] - _x[i]) / float(_params[i].scale)
		if d == 0.0: continue
		act.append(i); du.append(d); dd += d * d
	if dd < 1e-12: return
	var rows := NPTS * 3
	var e := _flat(pts_new)   # e = observed change - predicted change, per row
	var f0 := _flat(_pts)
	for rr in rows: e[rr] -= f0[rr]
	for a in act.size():
		var col: PackedFloat64Array = _J[act[a]]
		var d: float = du[a]
		for rr in rows: e[rr] -= col[rr] * d
	for rr in rows:
		if absf(e[rr]) < 1e-12: e[rr] = 0.0
	for a in act.size():
		var col: PackedFloat64Array = _J[act[a]]
		var w: float = du[a] / dd
		for rr in rows: col[rr] += e[rr] * w
		_J[act[a]] = col

func _report(target: Vector3, usec: int, evals: int, iters: int, clamped: Array) -> Dictionary:
	var hi: int = HANDLES[handle]
	var feet := 0.0
	for pi in [R_FOOT, R_ANKLE, L_FOOT, L_ANKLE]:
		if (handle == "right_foot" and pi in [R_FOOT, R_ANKLE]) or (handle == "left_foot" and pi in [L_FOOT, L_ANKLE]): continue
		feet = maxf(feet, _pts[pi].distance_to(_pts0[pi]))
	var paddle := maxf(_pts[GRIP].distance_to(_pts0[GRIP]), _pts[TIP].distance_to(_pts0[TIP]))
	var eval_total := 0
	for u in _eval_usec: eval_total += u
	for u in _arm_eval_usec: eval_total += u
	return {"ok": true, "usec": usec, "evals": evals, "iters": iters, "eval_total_usec": eval_total,
		"target_err_m": _pts[hi].distance_to(target), "feet_drift_m": feet, "paddle_drift_m": paddle,
		"balance_before_m": float(balance(_pts0).off_m), "balance_after_m": float(balance(_pts).off_m),
		"clamped": clamped, "eval_usec": Array(_eval_usec), "arm_eval_usec": Array(_arm_eval_usec),
		"handle_at": _pts[hi], "arm_reach_m": _arm_reach(), "carry_rel_m": _rel_err()}

## Carry mode: how far hand and paddle tip are from their grab offset to the elbow (m).
func _rel_err() -> float:
	var m := 0.0
	for rl in _rel: m = maxf(m, (_pts[rl[0]] - _pts[rl[1]]).distance_to(rl[2]))
	return m

## Shoulder-wrist distance of each arm (right, left): [at grab, now] plus the limit when the
## torso-turn reach rule is in force.
func _arm_reach() -> Array:
	var out: Array = []
	for sw in [[R_SHOULDER, R_WRIST], [L_SHOULDER, L_WRIST]]:
		var row := [_pts0[sw[0]].distance_to(_pts0[sw[1]]), _pts[sw[0]].distance_to(_pts[sw[1]])]
		for rc in _reach:
			if rc[0] == sw[0]: row.append(rc[2])
		out.append(row)
	return out

# ---------------------------------------------------------------- release / commit

## Values the solver changed, as engine (studio.set_field) values.
## Changes below COMMIT_MIN of a field's scale are solver noise and stay out of the pose file.
## A seeded automatic guide (zero pole) is written whole when any of its components changes.
const COMMIT_MIN := 0.002
func changes() -> Array:
	var out: Array = []
	var take := PackedByteArray(); take.resize(_params.size())
	for i in _params.size():
		take[i] = 1 if absf(_x[i] - _x0[i]) >= COMMIT_MIN * float(_params[i].scale) else 0
	for i in _params.size():
		var pr: Dictionary = _params[i]
		if pr.comp == 0 and str(pr.field).ends_with("_pole") and (take[i] or take[i + 1] or take[i + 2]):
			for c in 3: take[i + c] = 1 if absf(_x[i + c] - _x_orig[i + c]) > 1e-9 or take[i + c] else 0
	for i in _params.size():
		if not take[i]: continue
		var pr: Dictionary = _params[i]
		out.append({"field": pr.field, "axis": null if pr.comp < 0 else pr.comp, "value": _x[i] - float(pr.off),
			"from": _x_orig[i] - float(pr.off)})
	return out

func _commit_rank(c: Dictionary, order: Dictionary) -> int:
	if c.field == "torso_yaw_deg": return 9
	for pr in _params:
		if pr.field == c.field: return int(order.get(pr.region, 5))
	return 5

## End the drag. commit: write the changes as one undo step (studio.set_field path) and compare
## the committed pose with the solver's prediction; else restore the preview from the engine.
## backoff (the studio's drag UI): when the engine's foot-plant / reach check stops a field, the
## step is rolled back and the largest fraction t of the whole drag (every field at
## from + t * (to - from), bisection, 6 steps) that commits with no stop is written instead, so
## the committed pose is a pose between the start and the drag, never a mix with some fields
## missing (reported as `kept`).
const BACKOFF_STEPS := 6
func release(commit := false, backoff := false) -> Dictionary:
	if not active: return {"ok": true, "active": false}
	active = false
	var predicted := _pts
	var out := {"ok": true, "committed": commit}
	if commit:
		# Body first, arm next, torso turn last: the engine checks each field against the pose it
		# lands on, and the torso-turn check is the strict one (it sees the final pose this way).
		var order := {"hips": 0, "legs": 0, "foot": 0, "chest": 1, "head": 2, "arm": 3, "paddle": 4}
		var ch := changes()
		ch.sort_custom(func(a, b): return _commit_rank(a, order) < _commit_rank(b, order))
		var label := "relax" if handle == RELAX else "AutoPose " + handle.replace("_", " ")
		studio.begin_edit(label)
		var stops := _commit_set(ch, 1.0)
		var kept := 1.0
		if backoff and not stops.is_empty():
			var t_us := Time.get_ticks_usec()
			var lo := 0.0
			var hi := 1.0
			for b_n in BACKOFF_STEPS:
				studio.abort_edit(); studio.begin_edit(label)
				var t := (lo + hi) * 0.5
				if _commit_set(ch, t).is_empty(): lo = t
				else: hi = t
			studio.abort_edit(); studio.begin_edit(label)
			kept = lo
			out["first_stops"] = stops
			stops = _commit_set(ch, kept) if kept > 0.0 else []
			var xt := _x.duplicate()
			for i in xt.size(): xt[i] = _x_orig[i] + kept * (_x[i] - _x_orig[i])
			predicted = _eval(xt)
			out["backoff_usec"] = Time.get_ticks_usec() - t_us
		studio.end_edit()
		_engine._refresh_preview(); _engine._refresh_status()
		var now := _read()
		var worst := 0
		for i in NPTS:
			if now[i].distance_to(predicted[i]) > now[worst].distance_to(predicted[worst]): worst = i
		out["worst_point"] = worst
		out.merge({"changes": ch.size(), "stopped": stops, "kept": kept, "commit_vs_prediction_m": _max_move(now, predicted)})
		if HANDLES.has(handle): out["handle_commit_vs_prediction_m"] = now[HANDLES[handle]].distance_to(predicted[HANDLES[handle]])
	else:
		_engine._refresh_preview()
		out["restore_vs_grab_m"] = _max_move(_read(), _pts0)
	return out

## Write changes at fraction t of the drag (from + t * (value - from)); returns the stopped ones.
## Batch write: the engine applies each value without its full refresh; the preview pose is
## brought up to date (no ghosts / arc rebuild) only before a foot-plant-checked field, whose
## check reads it, so every check sees the same pose as with one refresh per field. The caller
## refreshes fully at the end (end_edit, then _engine._refresh_preview()).
func _commit_set(ch: Array, t: float) -> Array:
	var stops: Array = []
	var stale := false
	for c in ch:
		if stale and c.field in _engine.FOOT_GUARDED_FIELDS:
			_pose_refresh(); stale = false
		var v: float = float(c.from) + t * (float(c.value) - float(c.from))
		var r: Dictionary = studio.set_field(c.field, c.axis, v, false, false)
		if not r.get("ok", false) or r.get("stopped") != null: stops.append({"field": c.field, "axis": c.axis, "reply": r})
		else: stale = true
	if stale: _pose_refresh()
	return stops

## The engine's preview refresh without the motion rebuild (ghosts, arc, joint samples): the
## motion stays marked dirty, so the next full refresh rebuilds it.
func _pose_refresh() -> void:
	var md: bool = _engine._motion_dirty
	_engine._motion_dirty = false
	_engine._refresh_preview()
	_engine._motion_dirty = md

# ---------------------------------------------------------------- Relax

## Checker groups (tools/pose_check.py HOLDS, OVERHEADS): held poses are not swung, overheads
## reach up on purpose.
const HOLDS := ["s08", "s09", "s20"]
const OVERHEADS := ["s03", "s04"]

## Relax ("Start fresh"): re-settle the pose at this key toward the checker's rules (level B of
## tools/pose_check.py, with a margin inside each threshold) without moving pins (feet, Contact
## paddle, user pins) or any gameplay field: centre of gravity within RELAX_BAL of the ankle line
## (balance on), knees bent >= 25 deg (no locked leg), trunk lean <= 32 deg forward / 18 sideways,
## and for swung strokes the paddle arm bent >= 18 deg (no locked / hyperextended elbow), wrist
## flex <= 52 / angle <= 96 deg, elbow <= 2 cm above the shoulder, hips no more than 7 cm above
## both other keys (no pop-up). One-sided rows: a pose that already meets a rule is not pulled.
## Fields: both arms, chest, hips, knee guides (look-at sets the head after). Damped least squares
## on a finite-difference Jacobian (full evaluations), prior toward the current pose with the drag
## stiffness. The caller commits with release(true, true) (one undo step).
func relax(opts: Dictionary = {}) -> Dictionary:
	var b := begin(RELAX, opts)
	if not b.get("ok", false): return b
	var t0 := Time.get_ticks_usec()
	var e0 := _evals
	for i in _k.size(): _k[i] *= RELAX_PRIOR   # Relax is asked to fix: a weaker pull toward the current pose than a drag
	_relax_setup()
	if _balance_on: _bal_free = RELAX_BAL
	var pts := _eval(_x)
	var r := _relax_residual(pts)
	var before := _rule_metrics(pts)
	var flags0 := _flags(before)
	var cost := _cost(r, _x)
	var cost0 := cost
	_lambda = 0.01
	var fails := 0
	var iters := 0
	var stop := "max_iters"
	var trace: Array = []
	for it in RELAX_ITERS:
		if cost < 1e-12: stop = "natural"; break
		var A := _relax_jac(r)
		_ineq = []
		var x_try := _step(A, r)
		if _pred_gain < 1e-4 * cost + 1e-12: stop = "converged"; break
		var p2 := _eval(x_try)
		var r2 := _relax_residual(p2)
		var c2 := _cost(r2, x_try)
		iters += 1
		# A step that changes nothing sits in a dead zone (the engine clamps the body to the legs'
		# reach, e.g. crouch has no effect until it passes that clamp): go further the same way.
		var mult := 2.0
		var rs0 := _sq(r)
		while c2 >= cost and _sq(r2) >= rs0 - 1e-12 and mult <= 8.0:
			var xm := _x.duplicate()
			for i in xm.size(): xm[i] = clampf(_x[i] + mult * (x_try[i] - _x[i]), float(_params[i].lo), float(_params[i].hi))
			var pm := _eval(xm)
			var rm := _relax_residual(pm)
			var cm := _cost(rm, xm)
			x_try = xm; p2 = pm; r2 = rm; c2 = cm
			mult *= 2.0
		var feas := _feasible(p2, pts) and _no_new_flags(p2, flags0)
		trace.append({"cost": c2, "feasible": feas, "mult": mult / 2.0, "lambda": _lambda, "pred": _pred_gain, "bal": float(balance(p2).off_m)})
		if c2 < cost and feas:
			_x = x_try; pts = p2; r = r2; cost = c2
			_lambda = maxf(_lambda * 0.3, 1e-6); fails = 0
		else:
			_lambda *= 4.0; fails += 1
			if fails >= 4: stop = "converged"; break
	_pts = _eval(_x)
	var look_err := _apply_look()
	var after := _rule_metrics(_pts)
	var usec := Time.get_ticks_usec() - t0
	PerfMonitor.record("studio.autopose_relax", usec)
	var feet := 0.0
	for pi in [R_FOOT, R_ANKLE, L_FOOT, L_ANKLE]: feet = maxf(feet, _pts[pi].distance_to(_pts0[pi]))
	var pin_drift := 0.0
	for pn in _pins: pin_drift = maxf(pin_drift, _pts[pn[0]].distance_to(pn[1]))
	var out := {"ok": true, "stop": stop, "iters": iters, "evals": _evals - e0, "usec": usec, "cost_before": cost0, "cost_after": cost,
		"rules_before": before, "rules_after": after, "violations_before": _violations(before), "violations_after": _violations(after),
		"flags_before": flags0, "flags_after": _flags(after),
		"feet_drift_m": feet, "pin_drift_m": pin_drift, "paddle_drift_m": maxf(_pts[GRIP].distance_to(_pts0[GRIP]), _pts[TIP].distance_to(_pts0[TIP])),
		"rules": _rules.map(func(q): return q[0]), "begin": b, "fields": changes().size(), "trace": trace}
	if look_err >= 0.0: out["look_err_deg"] = look_err
	return out

func _sq(r: PackedFloat64Array) -> float:
	var t := 0.0
	for v in r: t += v * v
	return t

func _relax_setup() -> void:
	var k := key
	var stroke: bool = not _engine._base and k.begins_with("s")
	var swung: bool = stroke and not (k in HOLDS)
	# [name, metric, kind, goal (margin inside the checker), weight, checker flag threshold]
	var knee_flag := 21.0 if swung else 0.0   # the checker flags a straight leg on swung strokes only (elsewhere: a goal, never a flag)
	_rules = [["left_knee_straight", "left_knee_bend", "min", 25.0, W_DEG, knee_flag], ["right_knee_straight", "right_knee_bend", "min", 25.0, W_DEG, knee_flag],
		["lean_forward", "trunk_lean_fwd", "max", 32.0, W_DEG * 2.0, 35.0], ["lean_side", "trunk_lean_side", "absmax", 18.0, W_DEG, 20.0]]
	if swung:
		_rules.append_array([["wrist_flex", "wrist_flex_deg", "absmax", 52.0, W_DEG * 2.0, 55.0], ["wrist_angle", "wrist_angle_deg", "max", 96.0, W_DEG * 2.0, 100.0]])
		if not (k in OVERHEADS):
			_rules.append_array([["elbow_up", "elbow_above_shoulder_m", "max", 0.02, 2.0, 0.03], ["arm_straight", "right_elbow_bend", "min", 18.0, W_DEG * 2.0, 15.0]])
		if stage == 0: _rules.append(["coil", "separation", "absmin", 12.0, W_DEG, 10.0])
	# Pop-up (a swung stroke): hip height of the other keys from the engine's motion samples.
	_pop = {}
	var pv = studio.preview
	if swung and not (k in OVERHEADS) and pv != null and pv.joint_samples.has("hips"):
		var hs: PackedVector3Array = pv.joint_samples["hips"]
		var last: int = pv.ARC_STEPS
		if hs.size() == last + 1:
			_pop = {"ys": [hs[0].y, hs[last / 2].y, hs[last].y], "sample_vs_now_m": hs[[0, last / 2, last][stage]].y - _pts0[HIPS].y}
			_rules.append(["pop_up", "pop_up_m", "max", 0.07, 3.0, 0.08])

## Rule metrics of the solved player (the same definitions as pose_shots.gd _body_metrics,
## unrounded): player-local frame x forehand side, y up, z toward the net.
func _rule_metrics(p: PackedVector3Array) -> Dictionary:
	var fh: Vector3 = _player._get_forehand_axis()
	var fw: Vector3 = _player._get_forward_axis()
	var o: Vector3 = _player.global_position
	var loc := func(v: Vector3) -> Vector3: return Vector3((v - o).dot(fh), v.y, (v - o).dot(fw))
	var ldir := func(v: Vector3) -> Vector3: return Vector3(v.dot(fh), v.y, v.dot(fw)).normalized()
	var bend := func(a: Vector3, m: Vector3, c: Vector3) -> float: return 180.0 - rad_to_deg((a - m).angle_to(c - m))
	var hips: Vector3 = loc.call(p[HIPS]); var torso: Vector3 = loc.call(p[TORSO])
	var spine := torso - hips
	var rs: Vector3 = loc.call(p[R_SHOULDER]); var re: Vector3 = loc.call(p[R_ELBOW]); var rw: Vector3 = loc.call(p[R_HAND])
	var bb: Basis = _player.paddle_node.global_transform.basis
	var axis: Vector3 = ldir.call(bb.y); var face_n: Vector3 = ldir.call(bb.z)
	var fore: Vector3 = (rw - re).normalized()
	var m := {"left_knee_bend": bend.call(loc.call(p[L_THIGH]), loc.call(p[L_KNEE]), loc.call(p[L_ANKLE])),
		"right_knee_bend": bend.call(loc.call(p[R_THIGH]), loc.call(p[R_KNEE]), loc.call(p[R_ANKLE])),
		"trunk_lean_fwd": rad_to_deg(atan2(spine.z, spine.y)), "trunk_lean_side": rad_to_deg(atan2(spine.x, spine.y)),
		"right_elbow_bend": bend.call(rs, re, rw), "elbow_above_shoulder_m": re.y - rs.y,
		"wrist_flex_deg": rad_to_deg(asin(clampf(fore.dot(face_n), -1.0, 1.0))), "wrist_angle_deg": rad_to_deg(fore.angle_to(axis)),
		"com_off_base_m": float(balance(p).off_m), "hip_y": p[HIPS].y}
	var yaw := func(a: Vector3, b: Vector3) -> float: return rad_to_deg(atan2(b.z - a.z, b.x - a.x))
	m["separation"] = yaw.call(loc.call(p[L_SHOULDER]), loc.call(p[R_SHOULDER])) - yaw.call(loc.call(p[L_THIGH]), loc.call(p[R_THIGH]))
	if not _pop.is_empty():
		var ys: Array = (_pop.ys as Array).duplicate()
		ys[stage] = p[HIPS].y + float(_pop.sample_vs_now_m)
		m["pop_up_m"] = float(ys[1]) - maxf(float(ys[0]), float(ys[2]))
	return m

func _rule_excess(q: Array, m: Dictionary, limit_at := 3) -> float:
	var v: float = float(m.get(q[1], 0.0))
	var lim: float = float(q[limit_at])
	match str(q[2]):
		"min": return maxf(0.0, lim - v)
		"max": return maxf(0.0, v - lim)
		"absmin": return maxf(0.0, lim - absf(v))
		_: return maxf(0.0, absf(v) - lim)

## Rule metrics and checker flags of the pose the engine shows now (after a Relax commit that
## the foot-plant / reach check cut short, the committed pose is not the predicted one).
func flags_now() -> Dictionary:
	_pose_refresh()
	var m := _rule_metrics(_read())
	return {"rules": m, "flags": _flags(m)}

## Rules the checker itself would flag (its thresholds, no margin), plus balance (0.15 m).
func _flags(m: Dictionary) -> Array:
	var out: Array = []
	for q in _rules:
		if _rule_excess(q, m, 5) > 0.0: out.append(q[0])
	if float(m.get("com_off_base_m", 0.0)) > 0.15: out.append("balance")
	return out

## Relax never trades one checker flag for another: a step may not raise a flag that was not
## raised at the start.
func _no_new_flags(p: PackedVector3Array, start: Array) -> bool:
	for f in _flags(_rule_metrics(p)):
		if not (f in start): return false
	return true

func _violations(m: Dictionary) -> Array:
	var out: Array = []
	for q in _rules:
		if _rule_excess(q, m) > 0.0: out.append(q[0])
	if _balance_on and float(m.get("com_off_base_m", 0.0)) > RELAX_BAL: out.append("balance")
	return out

## Residual for Relax: pins, balance, reach (_residual) plus one row per rule (weighted excess).
## Reads the player as the last evaluation left it (call right after _eval).
func _relax_residual(p: PackedVector3Array) -> PackedFloat64Array:
	var r := _residual(p)
	var m := _rule_metrics(p)
	for q in _rules: r.append(_rule_excess(q, m) * float(q[4]))
	return r

func _relax_jac(r: PackedFloat64Array) -> Array:
	var out: Array = []
	for i in _params.size():
		var col := PackedFloat64Array(); col.resize(r.size())
		if _frozen[i]: out.append(col); continue
		var pr: Dictionary = _params[i]
		var h: float = FD_H * float(pr.scale)
		var xs := _x.duplicate()
		if xs[i] + h > float(pr.hi): h = -h
		xs[i] += h
		var ri := _relax_residual(_eval(xs))
		var sgn := 1.0 if h > 0 else -1.0
		var hu := FD_H
		var flat := true
		for k in r.size():
			if absf(ri[k] - r[k]) > 1e-10: flat = false; break
		if flat:   # dead zone (see relax): a secant over RELAX_PROBE units, either way
			for dirn in [1.0, -1.0]:
				var x2 := _x.duplicate()
				x2[i] = clampf(_x[i] + dirn * RELAX_PROBE * float(pr.scale), float(pr.lo), float(pr.hi))
				var du: float = (x2[i] - _x[i]) / float(pr.scale)
				if absf(du) < 1e-6: continue
				var r2 := _relax_residual(_eval(x2))
				var moved := false
				for k in r.size():
					if absf(r2[k] - r[k]) > 1e-10: moved = true; break
				if moved: ri = r2; hu = absf(du); sgn = signf(du); break
		for k in r.size(): col[k] = (ri[k] - r[k]) / hu * sgn
		out.append(col)
	return out

# ---------------------------------------------------------------- measurement

## Evaluation cost and path checks at the current key (read-only: the preview is restored).
## {samples}: random perturbations of every parameter of the `handle` set.
func probe(h: String, samples := 60) -> Dictionary:
	var b := begin(h, {"mode": "fd"})
	if not b.get("ok", false): return b
	var n := _params.size()
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	_eval_usec.clear(); _arm_eval_usec.clear()
	var a := _eval(_x0); var a2 := _eval(_x0)
	var determinism := _max_move(a, a2)
	# Path independence: the same candidate after other candidates (full and arm-only path).
	var after_other := 0.0
	var which := {}
	for s2 in 8:
		var xo := _x0.duplicate()
		for i in n:
			if not _frozen[i]: xo[i] = clampf(xo[i] + rng.randf_range(-0.3, 0.3) * float(_params[i].scale), float(_params[i].lo), float(_params[i].hi))
		_eval(xo)
		var a3 := _eval(_x0)
		after_other = maxf(after_other, _max_move(a, a3))
		for q in NPTS:
			if a3[q].distance_to(a[q]) > 0.0: which[q] = maxf(float(which.get(q, 0.0)), a3[q].distance_to(a[q]))
	_eval_usec.clear()
	for s in samples:
		var xs := _x0.duplicate()
		for i in n:
			if not _frozen[i]: xs[i] = clampf(xs[i] + rng.randf_range(-0.3, 0.3) * float(_params[i].scale), float(_params[i].lo), float(_params[i].hi))
		_eval(xs)
	var full := _eval_usec.duplicate()
	# Arm path vs full path for arm / paddle parameters.
	var arm_err := 0.0
	_arm_eval_usec.clear()
	for i in n:
		var pr: Dictionary = _params[i]
		if not (pr.region == "arm" or pr.region == "paddle") or _frozen[i]: continue
		var xs2 := _x0.duplicate()
		xs2[i] = clampf(xs2[i] + 0.2 * float(pr.scale), float(pr.lo), float(pr.hi))
		_eval(_x0)
		var pa := _eval_arm(xs2)
		var pf := _eval(xs2)
		arm_err = maxf(arm_err, _max_move(pa, pf))
	var arm := _arm_eval_usec.duplicate()
	# Contact coupling: how far each parameter moves the paddle and the feet (per scale unit).
	_x = _x0.duplicate(); _pts = _eval(_x0); _compute_J()
	var coupling: Array = []
	for i in n:
		coupling.append({"field": _pname(i), "paddle_m_per_unit": _pin_motion(_J[i], [GRIP, TIP]),
			"feet_m_per_unit": _pin_motion(_J[i], [R_FOOT, L_FOOT, R_ANKLE, L_ANKLE])})
	release(false)
	return {"ok": true, "handle": h, "n": n, "determinism_m": determinism, "after_other_m": after_other, "after_other_points": which, "arm_vs_full_m": arm_err,
		"full_eval_usec": Array(full), "arm_eval_usec": Array(arm), "coupling": coupling, "begin": b}
