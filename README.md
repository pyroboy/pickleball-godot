# Pickleball Godot — Agent Reference

## Godot Application Location

**Path**: `/Applications/Godot.app`

> If the path above doesn't exist, try:
> - `~/Downloads/Godot.app`
> - `~/Downloads/Godot-4.6.2.app`
> - `brew --prefix godot` (if installed via Homebrew)
> - `ls ~/Downloads/` and look for any `Godot*.app`

## Running the Game

### Via Godot GUI
```bash
open /Applications/Godot.app
# Then File → Open → select pickleball-godot/project.godot
```

### Via Command Line (headless)
```bash
godot --headless --path /Users/arjomagno/Documents/github-repos/pickleball-godot --quit-after 30
```

### Run the MCP Bridge (for agent control)
```bash
godot --headless --path /Users/arjomagno/Documents/github-repos/pickleball-godot
# Keep running — the MCP bridge initializes on boot
```

## Godot Version

**Required**: Godot 4.6.2 (stable)
- Download: https://godotengine.org/download/macos
- Filename: `Godot_v4.6.2-stable_macos.universal.zip`
- Extract to `/Applications/Godot.app` (rename if needed)

## Project Structure

```
pickleball-godot/
├── scenes/          # Godot scenes (.tscn)
│   ├── game.tscn    # Main scene (entry point)
│   ├── ball.tscn    # Ball RigidBody3D
│   ├── player.tscn  # Player character
│   └── court.tscn   # Court geometry
├── scripts/         # GDScript source
│   ├── game.gd     # Game loop, scoring, UI
│   ├── ball.gd     # Ball physics (drag, Magnus, spin, COR)
│   ├── player.gd   # Player controller
│   ├── player_ai_brain.gd   # AI opponent
│   ├── player_paddle_posture.gd  # 20-posture system
│   ├── shot_physics.gd    # Shot velocity/spin computation
│   └── ball_physics_probe.gd  # Calibration tool
├── docs/
│   └── paddle-posture-audit.md  # Full gap audit (51 gaps, 20 resolved)
└── .sisyphus/      # Agent plans and notepads
```

## In-Game Controls

| Key | Action |
|-----|--------|
| `W/A/S/D` | Move player |
| `Space` | Swing / hit |
| `4` | Launch practice ball (full trajectory probe) |
| `T` | Kinematic drop test (bounce COR calibration) |
| `Z` | Toggle debug visuals (posture ghosts, zones, trajectories) |
| `X` | Cycle AI difficulty (EASY / MEDIUM / HARD) |
| `P` | Cycle camera view |

## Physics Calibration

The game has two built-in calibration probes:

**Key `4` — Full trajectory probe**
Launches a ball with realistic topspin and prints aerodynamic comparison:
- Horizontal deceleration vs. real pickleball reference (Lindsey 2025, Cd=0.33)
- Bounce COR vs. velocity-dependent model
- Spin decay halflife vs. real pickleball
- All sections print `MATCHES` if within tolerance

**Key `T` — Kinematic drop test**
Drops ball from known height, measures first bounce, prints COR.

## Key Constants (ball.gd)

```
BALL_MASS          = 0.024 kg
BALL_RADIUS        = 0.0375 m  (oversized vs real 0.0349m)
BOUNCE_COR         = 0.640 (velocity-dependent: 0.78 @ 3 m/s → 0.56 @ 18 m/s)
DRAG_COEFFICIENT   = 0.47  (game value; probe references Cd=0.33 outdoor)
MAGNUS_COEFFICIENT = 0.0003
AERO_EFFECT_SCALE  = 0.79
SPIN_BOUNCE_TRANSFER = 0.25
SPIN_BOUNCE_DECAY  = 0.70
```

## Gap Audit

Full status at `docs/paddle-posture-audit.md`:
- **51 total gaps** across 9 domains (AI, Physics, Paddle, Posture, Grid, Footwork, Trajectory, Visual, Infra)
- **20 resolved**, **8 partial**, **16 open**, **7 deferred**
- Physics domain: 5 resolved, 1 open (GAP-22 dwell time)
