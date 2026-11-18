extends RefCounted
## Positive pitch means ankle plantarflexion (toes down). Requested pose pitch
## never moves the ankle/contact to hide floor penetration. A fully planted
## sole stays flat; lifted soles use only their available geometric clearance.
const MIN_PITCH := -30.0
const MAX_PITCH := 45.0
const FLOOR_EPSILON := 0.00001

static func apply(leg, yaw: float, requested_deg: float, grounded: bool) -> float:
	if not "foot_mesh" in leg or leg.foot_mesh == null or leg.foot_mesh.mesh == null: return 0.0
	if absf(requested_deg) < 0.00001: return -rad_to_deg(leg.foot_pivot.global_rotation.x)
	var requested := 0.0 if grounded else clampf(requested_deg, MIN_PITCH, MAX_PITCH)
	var old_position: Vector3 = leg.foot_mesh.position
	leg.foot_mesh.position = Vector3(0, -0.015, -0.03)
	if lowest_y(leg, yaw, 0.0) < PickleballConstants.FLOOR_Y - FLOOR_EPSILON:
		# Preserve the existing solver's floor correction for an authored ankle
		# below the floor; do not introduce a new mesh/contact translation here.
		leg.foot_mesh.position = old_position
	var applied := requested
	if lowest_y(leg, yaw, applied) < PickleballConstants.FLOOR_Y - FLOOR_EPSILON:
		var low := 0.0; var high := 1.0
		for iteration in range(14):
			var middle := (low + high) * 0.5
			if lowest_y(leg, yaw, requested * middle) >= PickleballConstants.FLOOR_Y - FLOOR_EPSILON: low = middle
			else: high = middle
		applied = requested * low
	leg.foot_pivot.global_basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -deg_to_rad(applied))
	return applied

static func lowest_y(leg, yaw: float, pitch_deg: float) -> float:
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -deg_to_rad(pitch_deg))
	var transform: Transform3D = Transform3D(basis, leg.foot_pivot.global_position) * leg.foot_mesh.transform
	var bounds: AABB = leg.foot_mesh.mesh.get_aabb()
	var lowest := INF
	for corner in range(8): lowest = minf(lowest, (transform * bounds.get_endpoint(corner)).y)
	return lowest
