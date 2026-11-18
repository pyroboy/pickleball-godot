extends RefCounted
const Delivery = preload("res://scripts/serve_delivery_profile.gd")
const Hand = preload("res://scripts/articulated_hand.gd")





const LOW_HEIGHT: = 0.08
const HIGH_HEIGHT: = 0.45
const BASES: = [
	Basis(Vector3(-0.198878112746, 0.331779509709, 0.922154930125), Vector3(0.958124499049, 0.263631777244, 0.111784300839), Vector3(-0.206021541843, 0.905770724452, -0.370316638114)), 
	Basis(Vector3(-0.239817219925, 0.192760298329, 0.95148884931), Vector3(0.942608807322, 0.280780039155, 0.180696445829), Vector3(-0.232327917532, 0.940215929714, -0.249033406772)), 
	Basis(Vector3(-0.282139019504, -0.325373420753, 0.902512921063), Vector3(0.717839096876, 0.552513236693, 0.423599048441), Vector3(-0.636478172599, 0.767372923491, 0.077680277668)), 
	Basis(Vector3(-0.215286750651, -0.529865871071, 0.820300942102), Vector3(0.761832322794, 0.434393868979, 0.480534575347), Vector3(-0.610952531787, 0.728384527438, 0.310149766296))
]
const POLES: = [Vector3(-0.156634492237, 0.10782046216, 0.336874848936), Vector3(-0.161489734734, 0.073872876431, 0.347550300579), Vector3(-0.115131598736, 0.231724295237, 0.423588473028), Vector3(-0.114249440887, 0.225405568722, 0.448636400221)]
static var _anatomical: Basis = _left_landmark_frame()
static var _high0: Basis = BASES[2] * Basis(_anatomical.z, deg_to_rad(15.0))
static var _high1: Basis = BASES[3] * Basis(_anatomical.z, deg_to_rad(15.0))

static func _left_landmark_frame() -> Basis:
	var wrist: Vector3 = Hand._mirror(Hand.WRIST_SOCKET, true)
	var x: Vector3 = (Hand._mirror(Hand._mcp_point(1), true) - wrist).normalized()
	var y: Vector3 = - (Hand._mirror(Hand._mcp_point(0), true) - Hand._mirror(Hand._mcp_point(3), true))
	y = (y - x * y.dot(x)).normalized()
	return Basis(x, y, x.cross(y).normalized())

static func basis(charge: float, held_height: float) -> Basis:
	var q: float = clampf(charge, 0.0, 1.0)
	var height: float = clampf((held_height - LOW_HEIGHT) / (HIGH_HEIGHT - LOW_HEIGHT), 0.0, 1.0)


	return BASES[0].slerp(BASES[1], q).slerp(_high0.slerp(_high1, q), height).orthonormalized()

static func pole(charge: float, held_height: float) -> Vector3:
	var frame: Basis = basis(charge, held_height)
	var seat_to_wrist: Vector3 = Hand._mirror(Hand.WRIST_SOCKET - Hand.CUP_BALL_CENTER, true)
	var center: = Vector3(Delivery.COLUMN.x, held_height, - Delivery.COLUMN.y)


	var elbow_hint: Vector3 = center + frame * (seat_to_wrist - _anatomical.x * 0.35)
	return Vector3(elbow_hint.x, elbow_hint.y, - elbow_hint.z)

static func protraction(charge: float) -> float:
	return 0.03 * (1.0 - clampf(charge, 0.0, 1.0))
