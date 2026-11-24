# Stamina you can read: visuals, cues and tips

Stamina now matters (Gameplay v2 and the player feel pass). Drives in a row cost more, fast
blocks cost a reflex, a tired player hits weaker drives and pops up more, and a long rally
won refills a little. None of that helps if you can't see it while playing.

## What the game shows today
- A small bar over every player (build 35): blue for your team, red for the opponents,
  amber below 50 (the penalty line). Shown the whole rally, hidden between points unless
  stamina is changing or low.
- The card's tired face and hunched, heavy-breathing idle below the penalty line.
- The Settings text explaining the rule.
- No numbers, no cost preview, no word when something stamina-related happens.

## Ideas, most useful first

### 1. A better bar
- **Notch at 50**: a tick mark on every bar where the penalty starts, so you see how close
  you are before it turns amber.
- **Cost ghost**: when stamina drops, the lost part stays as a white chunk for half a second,
  then drains. A big drive streak cost is visible at a glance.
- **Colours**: full colour above 50, amber below, red below 25, with a slow pulse.
- **Your own bar, larger**, under the score or beside the HIT circle, always visible, with
  the number (e.g. 64). The bars over heads stay small, without numbers.

### 2. Cost preview while you hold HIT
- The hold ring already shows power. Add a small chip "-8" next to it with the stamina this
  shot will cost: it grows with your drive streak (-8, -10, -12 …).
- The chip turns amber when the shot would take you below 50.
- A tap (touch shot) shows "-1", so dinking reads as rest.

### 3. Pop-up numbers and words over the player
- "-10" floats up from a player on a costly shot (drive streak, smash, fast block). Your team
  only, or everyone (see the open questions).
- "TIRED" tag on a bar the moment it crosses below 50; "+12 LONG RALLY" on the winners of a
  15+ shot rally, joined to the rally counter's finish.
- Between points: your bar shows the refill counting up ("+10"), so you see that it is only
  partial.

### 4. Tips (short, contextual, each once per match, off in Settings)
| When | Tip |
|---|---|
| Your third drive in a row | "Drive streak: each drive costs more. Mix in a dink to rest." |
| You drop below 50 the first time | "Tired: weaker drives, more pop-ups. Dinks and resets are rest." |
| An opponent drops below 50 | "Red 2 is tired: drive at them, their blocks pop up." |
| You win a long rally | "Long rally won: +12 stamina." |
| You are below 25 at a serve | "Very tired: play it soft this point." |
- Shown as a small banner at the top, about 2.5 s, never over the ball or the HIT circle.
- Uses the existing cinematic banner / rally banner style. Logged to the phone log, so we
  can see which tips fire.

### 5. Body language
- Faster breathing and a slower walk between points when tired (the poses exist; only the
  timing changes).
- Small pixel sweat drops on a tired card (no glow), so a tired opponent is readable
  without looking at its bar.

### 6. Learn it once
- A "How stamina works" page in the pause menu: four lines and the bar picture.
- The Settings text stays, shortened to point at that page.

## How to check
- Phone log: tips that fired, and how often your stamina crossed 50 (`shot_report.py --human`).
- Screen: the bars and chips never cover the ball or the HIT circle (the existing occlusion
  rules in `stamina_display.gd` apply to the new parts too).
- Performance: a few labels and bars only; the frame graph (F3) should not change.

## Open questions
- Cost numbers over everyone, or only your team?
- Your own big bar: under the score, or by the HIT circle?
- Tips on by default (they can be turned off), or a "first match" only mode?
- Sweat drops: in keeping with the pixel-card look, or too busy?

## Status (2026-11-23, build 37 on the phone)

Built: bars over all four players with a notch at 50, a white ghost chunk for what was just
spent, amber below 50 and red pulsing below 25 (`stamina_display.gd`, custom-drawn); your
big bar with the number at the top of the court area; "-N" over your team on costly shots,
"TIRED" when anyone crosses 50, "+N LONG RALLY" on the refill; pixel sweat drops over tired
players (own random stream); the cost chip beside the HIT ring while you hold (-1 for a tap,
the drive cost with your streak, amber / red by where it leaves you); tips once per match
(`stamina_tips.gd`, Settings "Stamina tips", logged as "stamina_tip"). Tired breathing
already existed (idle_tired). Not built: the "How stamina works" pause-menu page (the pause
menu is the visual session's uncommitted work). Also: shot word and flick chevrons at the HIT
ring on release, and the return-of-serve fix (no low-drive risk on deep or opening shots).

## Status (2026-11-23, build 40 on the phone)

Stamina now drains from footwork, not swings: movement 0.3 per metre walking up to 3.0 sprinting
(`MOVE_COST_*`), power shots 3-4 (were 7-10), streak 1, fast blocks 1-1.5. The between-point
refill grows with what is missing (`STAMINA_REST_RECOVERY` 0.2 + `STAMINA_REST_DEFICIT` 0.03 x
(100 - value) per s): ~4 per point when fresh, ~13 when tired (was a flat ~10, so nobody ever
got tired). An exhausted player already lost clearly (pinned at 0: team share 48% -> 24%).
With the run-them tactic (POSITION_PLAN.md) the smart team wins 65.7% / 57.4% of points over 12
Medium seeds per side (plain 54.0% / 46.0%). Open: in all-AI play Medium/Hard players sit at
median 52-58 stamina, Hard nets/outs 67%, Hard median rally 9 under Medium's 12.
