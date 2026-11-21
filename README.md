# Strings & Steel

A 2D marionette sword-fighting game built in **Godot 4.7**. Two puppets hang from their control bars on a candle-lit theatre stage and duel with longswords, rapiers and executioner's blades. Blade collision is physical, so parries come from where your sword actually is. Limbs can be cut off and left swinging from their strings.

## Features

- **Physical blade combat.** Swept blade-vs-blade and blade-vs-body capsule collision with sweet-spot vs. ricasso scaling, edge cuts vs. armour-piercing thrusts, and physical arm rebound on parry/plate impact.
- **Cursor sword control.** The sword arm follows the mouse (or right stick) through weighted two-bone IK. Swing through a real arc to build limb-chopping momentum (gold trail), or drive the point forward to thrust.
- **Perfect parries & ripostes.** Raise your guard just before impact to stagger the attacker, or block cleanly to earn a brief golden **Riposte** window with faster, harder counters.
- **Half-Swording (`Q` / `R3`) & Mordhau Thunderblow (`Q` -> `K`/`L`).** Grip the centre of a two-handed blade with your off-hand for close-quarters leverage, cheaper blocks, and an overhead crossguard hammer blow (`Mordhau`) that crushes 70%+ of plate armour.
- **Fast-Action Special Moves & Chain/Dash Cancels.** Vault over low sweeps with **Leap Cleave (`W`)**, crack visors at point-blank with **Pommel Bash (`L`/`C` or `Guard + Slash`)**, duck clean under high slashes with **Ankle Sweep (`S + E`)**, shred strings with **Whirlwind Double-Cut (`U`)**, chain-cancel landed hits into follow-ups, or **Dash-Cancel (`Shift`)** recovery with speed afterimages!
- **6 Weapon Loadouts, Disarms & Sword Throws (`F` / `MMB`).** Choose **Signature**, **Crimson Halberd**, **Bec de Corbin Warhammer**, **Iron Pollaxe**, **Sword + Buckler**, or **Katzbalger**. Hurl your weapon across the stage, deflect flying steel, brawl with gauntlet jabs, and scramble to pick up any dropped blade on the floorboards!
- **Knock-Off Hats, Cracking Helmets & Earned Dismemberment.** Solid headshots knock off feathered hats or crack off Gothic plate helmets, exposing bare heads to mid-fight decapitation. High slashes can snap live overhead marionette strings (`Strings & Steel`), and shoving a rival into the proscenium wall triggers a **Corner Crush**.
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
- Keyboard + mouse, gamepad, and a **button-free translucent touch-wheel system** for mobile/Android (screen stays 100% clean until touched; floating low-opacity wheels appear under your thumbs and fade out on release). Settings are saved automatically, and `.github/workflows/android-apk.yml` builds `StringsAndSteel.apk` automatically on push.

## Controls

| Action | Keyboard / Mouse | Gamepad | Touch (Button-Free Translucent Wheels) |
|---|---|---|---|
| Move | A / D (or ← →) | Left stick / D-pad | Slide left/right on Left Stick (tight 36 px full-speed span + frame-1 reversal) |
| Aim & cut | Move and fling the mouse | Right stick | Swipe / arc across 360° Right Blade Wheel (0 ms live 2-bone IK cuts) |
| Quick slash | J (or LMB in *Keys* mode) | X / RB | Quick tap on Right side (high or low) |
| Thrust / Mordhau | K (Mordhau when Half-Swording) | Y | Sharp horizontal forward whip on Right Blade Wheel |
| Leap Plunge Cleave | W (or Fwd-Dash + Slash) | RT + X | Quick Up+Forward diagonal flick on Left Stick |
| Pommel Visor Bash | L / C (or Parry + Slash) | L3 | 2nd-finger tap while holding Rear Guard Parry |
| Whirlwind Spin Cut | U (or Dash + Thrust) | RT + Y | Back-Dash + Quick Right Tap |
| Kick / Ankle Sweep | E (or `S + E` to Duck & Sweep) | A (`Down + A` Sweep) | Down flick = Kick · Down+Forward flick = Leg Sweep |
| Half-Sword stance | Q | Right stick click (R3) | Quick upward flick on Left Stick (fires mid-swipe) |
| Hurl weapon | F / Middle mouse | — | Two-finger flick on Right side |
| Parry | Space / RMB | B / LB / LT | Pull or flick Right Wheel into Rear Guard Arc (or hold 2nd finger) |
| Low guard | S (or aim low) | Left stick down | Pull Rear Guard Arc low (or Left Stick down) |
| Dash | Shift / ↑ | RT / D-pad up | Quick horizontal flick (fires mid-swipe) or 2x tap on Left Stick |
| Pause | Esc / P | Start | Top `II MENU` pill |
| Restart round | R | Back | Pause menu |

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
  WeaponProjectile.gd  hurled spinning blades & recoverable dropped ground weapons
  PhysicsDebris.gd     severed limbs & knocked-off headgear: ballistic or dangling
  SoundFX.gd           procedural sound effects
tools/
  CharacterRigBuilder.gd  builds fighter .tscn rigs from data/rig_metadata.json
  BuildAllRigs.gd         headless rig + arena builder
  SmokeTest.gd            116-check headless gameplay test suite
  BalanceSim.gd           multi-bot headless AI & combat balance simulator
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
