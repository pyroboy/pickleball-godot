# Arjostyle Pickleball (iPhone, doubles)

3D pickleball game in Godot 4.6.3 (GDScript), shipped to iPhone. Version 0.3.28 build 31.

- Entry scene: `scenes/title.tscn` · gameplay: `scripts/game.gd`
- iOS export settings: `export_presets.cfg` (bundle id `com.arjomagno.arjostylepickleball.ios`)

## Working rules

- Keep changes small; read only the files the task needs.
- Don't add per-frame `print()` logging — Godot output floods quickly.
- Run on Mac: `tools/run_mac.sh` (log in `logs/game.log`), then `tools/game_errors.sh` for a deduplicated error summary.
- Performance: every run writes `logs/perf.jsonl` (PerfMonitor autoload, `scripts/debug/perf_monitor.gd`). Read it with `python3 tools/perf_report.py`, not by opening the log. F3 toggles the in-game frame graph. Time new hot spots with `PerfMonitor.record("label", usec)`.
- iOS Simulator is not usable: Godot 4.6.3's official simulator library is x86_64-only.
- Headless smoke check:

```bash
godot --headless --path . --quit-after 600 2>&1 | grep -iE "script error|parse error|error:"
```
