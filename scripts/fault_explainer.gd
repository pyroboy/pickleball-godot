extends RefCounted
## A short, friendly reason for how a point ended, for a casual player.
## Returns {"headline", "line", "won"}; `won` is from the human team's view.

# reason -> [when your side lost the point, when your side won it]
const LINES := {
	"DOUBLE_BOUNCE": ["Too slow!", "Too quick for them!"],
	"BALL_IN_NET": ["Into the net!", "They hit the net!"],
	"OUT_OF_BOUNDS": ["Out!", "They hit it out!"],
	"KITCHEN_VOLLEY": ["Kitchen! Let it bounce first.", "They stepped in the kitchen!"],
	"MOMENTUM": ["Kitchen! Stay out after a volley.", "They fell into the kitchen!"],
	"TWO_BOUNCE_RULE": ["Let it bounce first!", "They hit it too early!"],
	"DOUBLE_CONTACT": ["Double hit!", "They hit it twice!"],
	"BODY_HIT": ["Ouch! It hit you.", "Got them!"],
	"SHORT_SERVE": ["Serve too short!", "Their serve was short!"],
	"WRONG_SERVICE_COURT": ["Wrong box!", "Their serve missed the box!"],
	"FOOT_FAULT": ["Foot fault! Stay behind the line.", "They stepped over the line!"],
	"WRONG_HALF": ["Wrong side!", "They hit their own side!"],
	"NET_PLANE": ["Wait for it to cross!", "They reached over the net!"],
	"OPPONENT_COURT": ["Stay on your side!", "They crossed over!"],
	"NET_POST": ["Hit the post!", "They hit the post!"],
	"NET_TOUCH": ["Don't touch the net!", "They touched the net!"],
}

static func explain(reason: String, _detail: String, winner: int, human_team: int) -> Dictionary:
	var won: bool = human_team in [0, 1] and winner == human_team
	var entry: Array = LINES.get(reason, ["Their point.", "Your point!"])
	return {"headline": "Your point!" if won else "Their point", "line": str(entry[1 if won else 0]), "won": won}
