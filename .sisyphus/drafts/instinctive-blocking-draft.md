# Instinctive Blocking — System Documentation

## Overview

"Instinctive blocking" refers to the **trajectory-centric ghost pool system** where the player's paddle automatically positions itself for incoming balls without the player manually choosing a stance.

---

## Core Architecture

| Component | File | Purpose |
|-----------|------|---------|
| `PlayerPaddlePosture` | `player_paddle_posture.gd` | Commit decision making, ghost management, scoring |
| `PlayerArmIK` | `player_arm_ik.gd` | Right arm → paddle IK, left arm two-handed grip |
| `PlayerDebugVisual` | `player_debug_visual.gd` | 3D debug markers (intercept, step, trajectory) |
| `PlayerAIBrain` | `player_ai_brain.gd` | AI state machine, trajectory prediction |
| `PlayerAwarenessGrid` | `player_awareness_grid.gd` | Volumetric trajectory detection |

---

## The Commit System (FIRST / TRACE / LOCK)

| Phase | Trigger | Behavior |
|-------|---------|----------|
| **FIRST** | Ball incoming + trajectory available + ghost closest | Sets `_committed_incoming_posture` |
| **TRACE** | Player moves > 0.4m + different ghost closest + ball > 1.5m | Commits to new ghost; 0.15s cooldown |
| **LOCK** | Ball < 1.5m from player | No more switching |
| **Zone Exit** | Committed zone no longer valid + stage < BLUE | Late recommit |

---

## Color Stages (PINK / PURPLE / BLUE)

| Stage | TTC Threshold | Meaning |
|-------|-------------|---------|
| **PINK** | > 0.8s | Ball far, early tracking |
| **PURPLE** | < 0.8s | Committed, preparing |
| **BLUE** | < 0.2s | Contact imminent, latch |

- BLUE hold: 0.35s one-shot latch
- BLUE fallback: ball-to-ghost < 0.35m

---

## Scoring Rubric

| Grade | ball2ghost | Meaning |
|-------|------------|---------|
| PERFECT | < 0.25m | Ball through ghost |
| GREAT | < 0.40m | Clean intercept |
| GOOD | < 0.60m | Slight adjustment |
| OK | < 0.80m | Stretch needed |
| MISS | >= 0.80m | Wrong posture |

---

## Green Glow System

- Ghosts within **0.45m** of trajectory glow green
- Green = hittable posture
- Fade to yellow over 0.6s when leaving trajectory
- Green-first commit selection

---

## Console Logs

| Tag | Shows |
|-----|-------|
| `[COMMIT]` | FIRST/TRACE decisions |
| `[COLOR]` | PINK/PURPLE/BLUE transitions |
| `[GREEN]` | Ghosts entering green set |
| `[SCORE]` | Grade + counters |

---

## Audit Status

**Resolved**: GAP-1, 3, 4, 6, 9, 20, 28, 33, 34, 40, 41, 44, 45, 47

**Open**: GAP-7b (pole IK), GAP-25 (AI jump), GAP-43 (body anticipation), GAP-15 (sweet-spot)
