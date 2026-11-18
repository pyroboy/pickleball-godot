# Arjostyle Pickleball (iPhone, doubles)

Pickleball game in Godot 4.6.3 (GDScript), shipped to iPhone. Version 0.3.28 build 31.
Moving to a 2.5D pixel-art look with gameplay locked: north star, phases and next steps
are in `docs/ROADMAP.md`. Read it before planning work.

- Entry scene: `scenes/title.tscn` · gameplay: `scripts/game.gd`
- iOS export settings: `export_presets.cfg` (bundle id `com.arjomagno.arjostylepickleball.ios`)
- Players render as 2.5D pixel cards by default: `scripts/graphics/pixel_card_rig.gd`,
  `assets/pixel_cards/`, `shaders/pixel_card.gdshader`. Classic 3D bodies: setting
  `video.character_style` = 0, or run with `PICKLEBALL_CLASSIC_BODIES=1`.

## Working rules

- Keep changes small; read only the files the task needs.
- Don't add per-frame `print()` logging — Godot output floods quickly.
- Run on Mac: `tools/run_mac.sh` (log in `logs/game.log`), then `tools/game_errors.sh` for a deduplicated error summary.
- Performance: every run writes `logs/perf.jsonl` (PerfMonitor autoload, `scripts/debug/perf_monitor.gd`). Read it with `python3 tools/perf_report.py`, not by opening the log. F3 toggles the in-game frame graph. Time new hot spots with `PerfMonitor.record("label", usec)`.
- iOS Simulator is not usable: Godot 4.6.3's official simulator library is x86_64-only.
- Visual-only changes must leave gameplay identical: compare `tools/bench.sh` runs with
  `python3 tools/pose_diff.py` (expect `IDENTICAL`). Never add nodes or meshes under a
  player's `BodyPivot`; gameplay scans every mesh there.
- The headless smoke check below starts at the title screen, so it does not compile
  gameplay scripts; `tools/bench.sh` loads the match and catches those errors.
- Headless smoke check:

```bash
godot --headless --path . --quit-after 600 2>&1 | grep -iE "script error|parse error|error:"
```
