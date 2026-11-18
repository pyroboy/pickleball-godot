# Pickleball Godot

3D pickleball game in Godot 4.6 (GDScript), targeting iPhone.

- Main scene: `scenes/game.tscn` · main script: `scripts/game.gd`
- Player logic is split into modules under `scripts/player_*.gd`, attached in `player.gd:_ready()`
- Court: net at Z=0, Blue/human (player 0) on +Z, Red/AI (player 1) on -Z, floor Y=0.075

## Working rules

- Keep changes small; read only the files the task needs.
- Don't add verbose per-frame `print()` logging — Godot output floods quickly.
- Headless smoke check:

```bash
godot --headless --path . --quit-after 30 2>&1 | grep -i error
```

## Latest iPhone (duos) source

The newest build (0.3.28 build 31, doubles) is on the `iphone-duos` branch
(worktree: `../pickleball-godot-iphone-duos`).
