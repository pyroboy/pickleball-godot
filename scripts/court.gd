extends Node
## Court.gd - Creates the court floor and all lines

# Court constants (same as physics.gd)
const COURT_LENGTH := 13.4
const COURT_WIDTH := 6.1
const NET_HEIGHT := 0.91
const LINE_WIDTH := 0.05
const NON_VOLLEY_ZONE := PickleballConstants.NON_VOLLEY_ZONE

# Feature flag for debug zone visualization
const SHOW_DEBUG_ZONES := true

func create_court(parent: Node3D) -> StaticBody3D:
	var court: StaticBody3D = StaticBody3D.new()
	court.name = "Court"
	parent.add_child(court)

	# Outer apron — dark blue-grey. Sits slightly LOWER than the playing
	# surface so the two layers don't z-fight where they overlap and players
	# (who stand at COURT_FLOOR_Y=0.075) don't sink into the court.
	var apron_mesh: BoxMesh = BoxMesh.new()
	apron_mesh.size = Vector3(16.0, 0.15, 24.0)
	var apron_inst: MeshInstance3D = MeshInstance3D.new()
	apron_inst.mesh = apron_mesh
	apron_inst.name = "CourtApron"
	apron_inst.position = Vector3(0, -0.006, 0)  # top at 0.069
	var apron_mat: StandardMaterial3D = StandardMaterial3D.new()
	apron_mat.albedo_color = Color(0.12, 0.16, 0.22)
	apron_mat.roughness = 0.9
	apron_mat.metallic = 0.0
	apron_inst.material_override = apron_mat
	court.add_child(apron_inst)

	# Playing surface — pickleball blue. Top lands exactly at y=0.075 so
	# player feet (COURT_FLOOR_Y) sit flush with it.
	var surface_mesh: BoxMesh = BoxMesh.new()
	surface_mesh.size = Vector3(COURT_WIDTH + 0.6, 0.006, COURT_LENGTH + 0.6)
	var surface_inst: MeshInstance3D = MeshInstance3D.new()
	surface_inst.mesh = surface_mesh
	surface_inst.name = "CourtSurface"
	surface_inst.position = Vector3(0, 0.072, 0)  # top at 0.075
	var surface_mat: StandardMaterial3D = StandardMaterial3D.new()
	surface_mat.albedo_color = Color(0.16, 0.32, 0.52)
	surface_mat.roughness = 0.75
	surface_mat.metallic = 0.0
	surface_inst.material_override = surface_mat
	court.add_child(surface_inst)

	# Floor collision — matches playing surface extent
	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(COURT_WIDTH, 0.15, COURT_LENGTH)
	col.shape = shape
	court.add_child(col)

	# Physics material
	court.physics_material_override = PhysicsMaterial.new()
	court.physics_material_override.bounce = 0.64
	court.physics_material_override.friction = 0.4

	_create_stadium_backdrop(parent)
	return court

func _create_stadium_backdrop(parent: Node3D) -> void:
	# Dark ring around the court — gives the scene depth without needing glow.
	var backdrop: MeshInstance3D = MeshInstance3D.new()
	backdrop.name = "StadiumBackdrop"
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 30.0
	cyl.bottom_radius = 30.0
	cyl.height = 14.0
	cyl.radial_segments = 12  # Mobile: reduced from 24
	cyl.rings = 1
	backdrop.mesh = cyl
	backdrop.position = Vector3(0, 5.5, 0)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.07, 0.09, 0.14)
	mat.cull_mode = BaseMaterial3D.CULL_FRONT  # render the inside of the cylinder
	mat.disable_receive_shadows = true
	backdrop.material_override = mat
	parent.add_child(backdrop)

func create_lines(parent: Node3D) -> void:
	var half_length: float = COURT_LENGTH / 2.0
	var half_width: float = COURT_WIDTH / 2.0
	var nz: float = NON_VOLLEY_ZONE
	
	var line_y: float = 0.077  # 2mm above the playing surface top (0.075)
	var lines_root: Node3D = Node3D.new()
	lines_root.name = "CourtLines"
	parent.add_child(lines_root)
	
	var line_mat: StandardMaterial3D = StandardMaterial3D.new()
	line_mat.albedo_color = Color.WHITE
	line_mat.emission_enabled = true
	line_mat.emission = Color.WHITE
	line_mat.emission_energy_multiplier = 0.1
	
	# Baselines
	_create_line(lines_root, Vector3(-half_width, line_y, -half_length), Vector3(half_width, line_y, -half_length), line_mat)
	_create_line(lines_root, Vector3(-half_width, line_y, half_length), Vector3(half_width, line_y, half_length), line_mat)
	
	# Sidelines
	_create_line(lines_root, Vector3(-half_width, line_y, -half_length), Vector3(-half_width, line_y, half_length), line_mat)
	_create_line(lines_root, Vector3(half_width, line_y, -half_length), Vector3(half_width, line_y, half_length), line_mat)
	
	# Non-volley zone
	_create_line(lines_root, Vector3(-half_width, line_y, -nz), Vector3(half_width, line_y, -nz), line_mat)
	_create_line(lines_root, Vector3(-half_width, line_y, nz), Vector3(half_width, line_y, nz), line_mat)
	
	# Centerline (single vertical line at center X=0, from non-volley zone to baseline)
	_create_line(lines_root, Vector3(0, line_y, -nz), Vector3(0, line_y, -half_length), line_mat)
	_create_line(lines_root, Vector3(0, line_y, nz), Vector3(0, line_y, half_length), line_mat)
	
	# ═══════════════════════════════════════════════════════════════════════════════
	# DEBUG ZONES - Feature flag: SHOW_DEBUG_ZONES
	# Color-code the service boxes and non-volley zones for debugging
	# ═══════════════════════════════════════════════════════════════════════════════
	print("[COURT] SHOW_DEBUG_ZONES=", SHOW_DEBUG_ZONES)
	if SHOW_DEBUG_ZONES:
		_create_debug_zones(parent)
		print("[COURT] Debug zones created!")

func _create_debug_zones(parent: Node3D) -> void:
	var half_length: float = COURT_LENGTH / 2.0
	var half_width: float = COURT_WIDTH / 2.0
	var nz: float = NON_VOLLEY_ZONE
	
	var debug_root: Node3D = Node3D.new()
	debug_root.name = "DebugZones"
	debug_root.visible = false  # hidden by default — Z key toggles
	parent.add_child(debug_root)
	print("[DEBUG_ZONES] half_length=", half_length, " half_width=", half_width, " nz=", nz)
	
	# Service box depth = from kitchen line (Z=±NVZ) to baseline (Z=±half_length)
	# With NVZ=2.134 and half_length=6.7: service_depth = 6.7 - 2.134 = 4.566
	var service_depth: float = half_length - nz
	# Center of service box from net: nz + service_depth/2
	var service_box_center_z: float = nz + service_depth / 2
	
	print("[DEBUG_ZONES] service_depth=", service_depth, " service_box_center_z=", service_box_center_z)
	
	# ═══════════════════════════════════════════════════════════════════════════════
	# RED'S SIDE (Z < 0) - Top of court
	# ═══════════════════════════════════════════════════════════════════════════════
	
	# RED Right Service Box (X > 0 in world) - MAGENTA
	_create_zone(debug_root, Vector3(half_width/2, 0.01, -service_box_center_z), 
		Vector3(half_width, 0.02, service_depth), 
		Color(1, 0, 1, 0.6), "Red Right")
	
	# RED Left Service Box (X < 0 in world) - PURPLE  
	_create_zone(debug_root, Vector3(-half_width/2, 0.01, -service_box_center_z), 
		Vector3(half_width, 0.02, service_depth), 
		Color(0.5, 0, 0.8, 0.6), "Red Left")
	
	# RED Non-Volley Zone (kitchen) - RED - Z: 0 to -NVZ (2.134m)
	_create_zone(debug_root, Vector3(0, 0.01, -nz/2), 
		Vector3(half_width * 2, 0.02, nz), 
		Color(1, 0, 0, 0.4), "Red Kitchen (NVZ)")
	
	# ═══════════════════════════════════════════════════════════════════════════════
	# BLUE'S SIDE (Z > 0) - Bottom of court
	# ═══════════════════════════════════════════════════════════════════════════════
	
	# Blue Right Service Box (X > 0 in world) - CYAN
	_create_zone(debug_root, Vector3(half_width/2, 0.01, service_box_center_z), 
		Vector3(half_width, 0.02, service_depth), 
		Color(0, 1, 1, 0.6), "Blue Right")
	
	# Blue Left Service Box (X < 0 in world) - LIME GREEN
	_create_zone(debug_root, Vector3(-half_width/2, 0.01, service_box_center_z), 
		Vector3(half_width, 0.02, service_depth), 
		Color(0, 1, 0, 0.6), "Blue Left")
	
	# Blue Non-Volley Zone (kitchen) - RED - Z: 0 to +NVZ (2.134m)
	_create_zone(debug_root, Vector3(0, 0.01, nz/2), 
		Vector3(half_width * 2, 0.02, nz), 
		Color(1, 0, 0, 0.4), "Blue Kitchen (NVZ)")
	
	# ═══════════════════════════════════════════════════════════════════════════════
	# LEGEND:
	#   YELLOW (1,1,0) = RIGHT service box from player's perspective (X > 0 in world)
	#   ORANGE (1,0.5,0) = LEFT service box from player's perspective (X < 0 in world)
	#   RED (1,0,0) = Non-volley zone (kitchen)
	#
	# PICKLEBALL SERVE RULES (opposite adjacent):
	#   Even score (0-0, 2-0, etc): Serve from RIGHT → target LEFT diagonal of opponent
	#   Odd score (1-0, 3-0, etc): Serve from LEFT → target RIGHT diagonal of opponent
	#
	# Correct targets at 0-0 (even score) — serve from RIGHT to opponent's LEFT diagonal:
	#   Blue (at bottom, Z>0) starts at X=+1.5, serves past net to RED's LEFT box (X<0, Z<-NVZ)
	#   Red  (at top,    Z<0) starts at X=-1.5, serves past net to BLUE's LEFT box (X<0, Z>+NVZ)
	#
	# At 1-0 (odd score) — serve from LEFT to opponent's RIGHT diagonal:
	#   Blue serves to RED's RIGHT box  (X>0, Z<-NVZ)
	#   Red  serves to BLUE's RIGHT box (X>0, Z>+NVZ)
	#
	# Service box extents: Z from ±NVZ (kitchen edge) to ±COURT_LENGTH/2 (baseline).
	# NVZ is defined in constants.gd (2.134m per USA Pickleball Rule 4.B).
	# ═══════════════════════════════════════════════════════════════════════════════

func _create_zone(parent: Node3D, center: Vector3, size: Vector3, color: Color, _label: String) -> void:
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	# Flat boxes (very thin height)
	mesh.size = Vector3(size.x, 0.01, size.z)
	mesh_inst.mesh = mesh
	
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.8
	mesh_inst.material_override = mat
	
	# Place flat on floor
	parent.add_child(mesh_inst)
	mesh_inst.global_position = Vector3(center.x, 0.078, center.z)

func _create_line(parent: Node3D, start: Vector3, end: Vector3, material: StandardMaterial3D) -> void:
	var length: float = start.distance_to(end)
	var center: Vector3 = (start + end) / 2.0
	
	var line_mesh: QuadMesh = QuadMesh.new()
	
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.mesh = line_mesh
	mesh_inst.material_override = material
	mesh_inst.rotation_degrees = Vector3(-90, 0, 0)
	
	var dx: float = abs(start.x - end.x)
	var dz: float = abs(start.z - end.z)
	if dx > dz: 
		line_mesh.size = Vector2(length, LINE_WIDTH)
	else:
		line_mesh.size = Vector2(LINE_WIDTH, length)
	
	parent.add_child(mesh_inst)
	mesh_inst.global_position = center

func create_walls(parent: Node3D) -> void:
	var half_length: float = COURT_LENGTH / 2.0
	var half_width: float = COURT_WIDTH / 2.0
	
	_create_wall(parent, Vector3(-half_width - 0.1, 1, 0), Vector3(0.2, 2, COURT_LENGTH))
	_create_wall(parent, Vector3(half_width + 0.1, 1, 0), Vector3(0.2, 2, COURT_LENGTH))
	_create_wall(parent, Vector3(0, 1, -half_length - 0.1), Vector3(COURT_WIDTH, 2, 0.2))
	_create_wall(parent, Vector3(0, 1, half_length + 0.1), Vector3(COURT_WIDTH, 2, 0.2))

func _create_wall(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var wall: StaticBody3D = StaticBody3D.new()
	parent.add_child(wall)
	wall.global_position = pos
	
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mesh_inst.mesh = mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.55, 0.5, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_inst.material_override = mat
	wall.add_child(mesh_inst)
	
	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	col.shape = shape
	wall.add_child(col)
	
	wall.physics_material_override = PhysicsMaterial.new()
	wall.physics_material_override.bounce = 0.6
	wall.physics_material_override.friction = 0.5

func get_court_bounds() -> Dictionary:
	var half_len: float = COURT_LENGTH / 2.0
	var half_wid: float = COURT_WIDTH / 2.0
	return {
		"left": -half_wid,
		"right": half_wid,
		"top": -half_len,
		"bottom": half_len,
		"net_z": 0.0
	}
