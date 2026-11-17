# Strings & Steel

A 2D marionette sword-fighting game built in **Godot 4.7**. Two puppets hang from their control bars on a candle-lit theatre stage and duel with longswords, rapiers and executioner's blades. Blade collision is physical, so parries come from where your sword actually is. Limbs can be cut off and left swinging from their strings.

## Features

- **Physical blade combat.** Blade-vs-blade and blade-vs-body capsule collision. Parries, blocks and clashes depend on the actual position of the blade.
- **Cursor sword control.** The sword arm follows the mouse (or right stick) through two-bone IK. Fling the blade to cut: faster swings hit harder and cost more stamina.
- **Perfect parries.** Raise your guard just before the blow lands to stagger the attacker.
- **Dismemberment that matters.** Losing a leg slows you and stops dashing. Losing the right shin stops kicks. Losing the off-hand weakens your guard. Losing the sword arm disarms you. Severed parts stay hanging from their marionette strings, and you can cut those strings too.
- **5 distinct fighters** (see `scripts/FighterStats.gd`):

  | Fighter | Style |
  |---|---|
  | Landsknecht | Hits hard, recovers fast, no armour |
  | Fechtmeister | Wide perfect-parry window, half plate |
  | Plague Executioner | Slow, limb-cleaving chops, brigandine |
  | Black Knight | Full plate, slow, tires quickly |
  | Venetian Bravo | Lightning rapier thrusts, fragile |

- **Modes:**
  - **Duel**: best of 3 rounds with a 90 s timer.
  - **Gauntlet**: endless waves of random challengers that get tougher each wave. Your best wave is saved.
- **AI** with human-like reaction time, imperfect guard reads and per-fighter spacing. Three difficulties.
- **Juice:** hitstop, slow-motion KO cam, screen shake, controller rumble, arterial blood, persistent blood on the backdrop and floor, bloody bootprints. All audio is synthesised procedurally, with no audio files.
- Keyboard + mouse, gamepad, and an optional touch overlay. Settings are saved automatically.

## Controls

| Action | Keyboard / Mouse | Gamepad |
|---|---|---|
| Move | A / D (or ← →) | Left stick / D-pad |
| Aim & cut | Move and fling the mouse | Right stick |
| Slash | J (or LMB in *Aim: Keys* mode) | X / RB |
| Thrust | K | Y |
| Kick | E | A |
| Parry | Space / RMB | B / LB / LT |
| Low guard | S (or aim low) | Left stick down |
| Dash | Shift / ↑ | RT / D-pad up |
| Pause | Esc / P | Start |
| Restart round | R | Back |

Letter keys bind by physical position, so they also work on AZERTY and QWERTZ layouts.

## Running

Open the `string-and-steel` folder in Godot 4.7+ and press **F5**. The main scene is `scenes/Arena.tscn`.

## Project layout

```
scripts/
  ArenaController.gd   match flow, combat resolution, camera, stage & FX
  FighterController.gd puppet fighter: input, IK, animation, damage, dismemberment
  AIController.gd      rival AI (perception delay + state machine)
  FighterStats.gd      per-fighter tuning table
  GameUI.gd            HUD, title/character select, pause, results, touch overlay
  BloodCanvas.gd       persistent GPU blood layers (non-clearing SubViewports)
  GameInput.gd         InputMap registration
  PhysicsDebris.gd     severed limbs: ballistic or dangling on a string
  SoundFX.gd           procedural sound effects
tools/
  CharacterRigBuilder.gd  builds fighter .tscn rigs from data/rig_metadata.json
  BuildAllRigs.gd         headless rig + arena builder
  SmokeTest.gd            headless gameplay test suite
data/rig_metadata.json    sprite parts, pivots and sockets for every fighter
```

## Tests

```
godot --headless --path . --script res://tools/SmokeTest.gd
```

The test drives real matches through the arena and checks the rules: stamina, parries, guard breaks, armour, dismemberment effects, clotting, round and gauntlet flow, pause, persistence and AI reaction time. The exit code is the number of failures.

## Regenerating fighter rigs

```
godot --headless --path . --script res://tools/BuildAllRigs.gd
```

> Note: this also rebuilds `scenes/Arena.tscn`.
