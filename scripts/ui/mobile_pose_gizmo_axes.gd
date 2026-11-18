extends RefCounted
## Positive authored-field directions in the solved preview's world space.
## Ring axes include the field's sign, so a positive right-hand drag always
## adds degrees. Move values are metres, including legacy *_mul fields.
const Body = preload("res://scripts/stroke_body_pose.gd")

## Pass the sampled/displayed preview pose, not an unsampled serve key.
## Serve Contact overlays angles on its baseline before a translation-only
## ball-point pivot; using that sampled pose preserves its real Euler axes.
static func for_selection(player, pose: Resource, id: String, rotate: bool) -> Array[Vector3]:
	var fh: Vector3 = player._get_forehand_axis()
	var fwd: Vector3 = player._get_forward_axis()
	var axes: Array[Vector3] = [fh, Vector3.UP, fwd]
	if pose == null: return axes
	var stance := Basis(fh, Vector3.UP, -fwd)
	var paddle: Basis = player.paddle_node.global_basis.orthonormalized()
	if not rotate:
		if id.ends_with("elbow"):
			# Pole coordinates are authored before the shoulder-guide rotation.
			# These move the guide, not the IK-constrained elbow one-for-one.
			var angles: Vector3 = pose.get(id.replace("elbow", "shoulder_rotation_deg"))
			var turn: Basis = stance * Basis.from_euler(angles * (PI / 180.0)) * stance.inverse()
			axes = [turn * fh, turn * Vector3.UP, turn * fwd]
		elif id.ends_with("hand"):
			var main: bool = (id == "left_hand") == (int(pose.get("paddle_hand")) == 1)
			var gripping: bool = player.arm_ik._support_mode(pose) == 1
			if main or gripping: axes = [paddle.x, paddle.y, paddle.z]
		elif id.ends_with("knee"):
			# Position-edited and serve previews use the planted shoe frame.
			# Ordinary authored previews use stance space. Both are metre-valued
			# foot-relative guides, rather than free knee translations.
			var planted: bool = bool(pose.get_meta("mobile_serve_planted_stance", false)) or Body.has_position_edit(pose)
			if planted:
				var side: int = 0 if id.begins_with("right") else 1
				var forward: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, player.leg_ik._knee_yaw[side])
				axes = [Vector3(-forward.z, 0, forward.x), Vector3.UP, forward]
		return _normalized(axes)
	if id == "paddle":
		# The paddle is Rx(pitch) * Ry(yaw) * R(-Z, roll), not Godot's
		# default YXZ. Local in-hand spin follows these rotations and does
		# not change their world-space angular derivatives.
		var angles: Vector3 = pose.resolve_paddle_rotation_deg(-1.0, -1.0)
		var pitched: Basis = stance * _rx(angles.x)
		axes = [fh, pitched * Vector3.UP, pitched * _ry(angles.y) * Vector3.FORWARD]
	elif id.ends_with("hand"):
		# Both hands rotate positively around the current paddle shaft.
		# Bevel/left-hand offsets and the in-hand counterturn preserve +Y.
		axes = [paddle.x, paddle.y, paddle.z]
	elif id.ends_with("elbow"):
		# Shoulder fields turn the IK pole in stance space. They are YXZ
		# degrees with positive signs, regardless of the body's own lean.
		var angles: Vector3 = pose.get(id.replace("elbow", "shoulder_rotation_deg"))
		var yawed: Basis = stance * _ry(angles.y)
		axes = [yawed * Vector3.RIGHT, Vector3.UP, yawed * _rx(angles.x) * Vector3.BACK]
	elif id.ends_with("foot"):
		# Positive pitch is toes down; positive yaw subtracts global yaw.
		# The grounded-sole solver may limit the amount without changing the
		# authoring axis. Foot +X is invariant under the applied pitch.
		var leg = player.right_leg_node if id.begins_with("right") else player.left_leg_node
		axes = [-leg.foot_pivot.global_basis.x, Vector3.DOWN, fwd]
	else:
		var body: Basis = player.body_pivot.global_basis.orthonormalized()
		if id == "hips":
			# Hips exposes body pitch/roll but pelvis yaw. Each therefore has
			# its own parent frame; these are not one local XYZ triplet.
			var yawed: Basis = player.global_basis * stance * _ry(-float(pose.get("body_yaw_deg")))
			axes = [-(yawed * Vector3.RIGHT), -(body * Vector3.UP), yawed * _rx(-float(pose.get("body_pitch_deg"))) * Vector3.BACK]
		elif id == "torso":
			var prefix: Basis = body * Body.waist_transform(player, pose, false).basis * stance
			var yawed: Basis = prefix * _ry(-float(pose.get("torso_yaw_deg")))
			axes = [-(yawed * Vector3.RIGHT), -(prefix * Vector3.UP), yawed * _rx(-(28.0 + float(pose.get("torso_pitch_deg")))) * Vector3.BACK]
		elif id == "head":
			# Visible HeadMesh uses local YXZ directly, unlike stance-space
			# torso math and the separate reference skeleton's old signs.
			var parent: Basis = player.body_pivot.get_node("TorsoMesh").global_basis.orthonormalized()
			axes = [(parent * _ry(-float(pose.get("head_yaw_deg"))) * Vector3.RIGHT) * player._get_swing_sign(), -(parent * Vector3.UP), parent.z]
	return _normalized(axes)

static func _rx(degrees: float) -> Basis:
	return Basis(Vector3.RIGHT, deg_to_rad(degrees))

static func _ry(degrees: float) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(degrees))

static func _normalized(axes: Array[Vector3]) -> Array[Vector3]:
	for i in range(axes.size()): axes[i] = axes[i].normalized()
	return axes
