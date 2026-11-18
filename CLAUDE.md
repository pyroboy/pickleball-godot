# Arjostyle Pickleball (iPhone, doubles)

3D pickleball game in Godot 4.6.3 (GDScript), shipped to iPhone. Version 0.3.28 build 31.

- Entry scene: `scenes/title.tscn` · gameplay: `scripts/game.gd`
- iOS export settings: `export_presets.cfg` (bundle id `com.arjomagno.arjostylepickleball.ios`)

## Working rules

- Keep changes small; read only the files the task needs.
- Don't add per-frame `print()` logging — Godot output floods quickly.
- Headless smoke check:

```bash
godot --headless --path . --quit-after 600 2>&1 | grep -iE "script error|parse error|error:"
```
