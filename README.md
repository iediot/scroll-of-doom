# Scroll of Doom

A platformer about doomscrolling, where scrolling is the only way out.

Scroll of Doom is an iOS game that boots into a fake phone home screen. Open the PLAY app and you land in a
vertical video feed — except every "post" is a playable room. Beat the room, fall through the gate, and the
feed scrolls to the next one. Sponsored posts sell you abilities. Bosses are dismissed with *Not interested*.
You never really stop scrolling; you just get better at it.

Built solo in Swift with SpriteKit and SwiftUI.

## Demo

https://github.com/user-attachments/assets/68c7983e-f550-4b21-9c52-e09c962789a7

## The loop

Each level is one post in the feed:

- A cube spawns from the top of the room, phasing through platforms until it lands.
- Somewhere in the room is a **heart**. Grab it and carry it to the empty heart outline in the engagement
  rail — the same spot a like button would be.
- The heart fills, the **gate** at the bottom of the screen dissolves, and you drop through it. Falling
  through the gate scrolls the feed down to the next level, and you enter the new room at whatever
  horizontal position you left the last one.
- Spikes kill you. The cube gets sucked into itself like a small black hole and the room resets.

Layered on top of that:

- **Ad levels** are sponsored posts (`@wingscorp.official`, `@dashlabs.official`) that hand you a permanent
  ability instead of a heart. The gate opens the moment you take the bait.
- **Boss levels** give you a *broken* heart, which you deliver to the `...` menu. It pops out a
  **Not interested** button, the heart fills it, and the gate opens.
- **Coins** scattered through rooms feed a persistent bank, spent on inventory slots and item merges.

## Abilities

| Ability | What it does |
| --- | --- |
| **Double Jump** (Wings) | One extra mid-air jump. Wings sweep back on the rise and lift on the fall. |
| **Dash** (Dash Boots) | Short horizontal burst that holds its height, with a particle trail and a cooldown. |
| **Jetpack** | Hold jump *after* every jump is spent to thrust upward. Roughly 0.4s of fuel, refills on the ground. The fuel gauge lives behind the jump button. |
| **Spike Boots** | Cling to a wall with grip that decays over about a second, then kick off it. |

Abilities are collected once and kept for the whole run, but only take effect while **equipped**.

## Inventory

The backpack button opens a panel that freezes the level. Items drag from a pool into equip slots — you start
with one slot and buy the second for coins. Drag one item onto a compatible partner to **merge** them: Wings +
Jetpack become a winged jetpack, Dash Boots + Spike Boots become a single pair that does both. Merging costs
coins and gets more expensive each time, and merged pairs are permanent across saves. The cube in the middle of
the panel re-renders live with whatever you have on.

## Save slots

Saves are the TikTok **Saved** tab — a three-column grid of "posts". Each card is a real render of the level
you left, drawn from the actual platform, spike, gate and cube data, with your cube standing exactly where you
walked away. Long-press a save to **Unsave** it. Saves carry your level, position, abilities, equipped loadout,
whether you were holding the heart, and whether the gate was already open.

## Level editor

The Gallery app on the home screen opens **My Levels**, a full editor:

- Drag platforms, walls, spikes, coins and the heart out of a palette that sits exactly where the control bar
  will be in game, so what you build is what you play.
- Everything snaps to a 27-column grid, with half-cell lengths and per-pixel X/Y nudges for the fussy bits.
- Pinch to zoom up to 4x and pan around; multi-select mode edits, duplicates, rotates or deletes a whole group
  at once.
- Rotate anything to any angle, 1–359°.
- Toggle which abilities the player gets for that level, then hit play to **playtest** it instantly with a
  free inventory (no coins needed).
- Every level exports to a base64 **share code** you can copy and paste to import someone else's room.

Custom levels are stored on device and shown as a Photos-style grid, each tile a live miniature render.

## Controls

Everything lives in the fake TikTok tab bar at the bottom: left/right arrows to move, the backpack for
inventory, the double-triangle for dash, and the stacked triangles for jump. The triangles light up to show
what's currently available — the back arrow is your double jump, and it also lights when a wall jump is on
offer.

## Settings

The Settings app exposes real performance knobs, since the feed keeps several scenes warm at once:

- **Frame Rate** — 60 or 120 Hz (only clean divisors of a 120 Hz display).
- **Graphics** — Low / Medium / High, which actually changes the render resolution (0.5x / 0.7x / 1.0x native)
  and drops the wallpaper at Low.
- **Particles** — Off / Low / Medium / High, scaling every burst.

## Some things under the hood

- **Custom movement over SpriteKit physics.** Velocity is driven directly rather than through forces, with
  coyote time, jump buffering, terminal velocity, and a look-ahead wall clamp so the cube stops flush against
  bars instead of jittering against the contact solver. Landing bounces from the collision solver are detected
  and cancelled.
- **Grounding by raycast.** Five rays across the hitbox width, so standing on a platform corner still counts,
  plus a special case for the narrow tops of walls.
- **Layered sprite model.** The cube is a stack of sprites — body, boots, eyes, mouth, two wings, jetpack,
  held heart — riding a squish node anchored at the feet and a walk-bob node inside it, so squash-and-stretch,
  the walking bob and the pose changes all compose instead of fighting.
- **Batched level drawing.** Every bar in a level renders into two shared shape paths (a black rim and a
  grey core) rather than two nodes per platform, with physics bodies kept per segment.
- **Baked particle textures.** Five little shapes are rendered once at launch, so a burst is one draw call of
  sprites instead of a pile of stroked shape nodes.
- **Save thumbnails** are drawn with Core Graphics from the same geometry the scene uses, cropped to the card
  aspect ratio, so a save card looks like the room it came from.

## Build and run

```
open "Scroll of Doom.xcodeproj"
```

Then pick an iOS 26.5+ device or simulator and hit run. No dependencies, no package manager, no config —
it's plain Swift, SpriteKit and SwiftUI. Set your own signing team if you're deploying to a device.

## Project layout

```
Scroll of Doom Shared/
  FeedView.swift       fake home screen, the feed, save slots, settings
  LevelScene.swift     the game itself: physics, abilities, level building, save state
  LevelPageView.swift  the TikTok chrome, control bar, inventory panel, perf plumbing
  LevelEditor.swift    My Levels hub, the editor, playtest
  GameArt.swift        procedurally drawn icons and coin frames
  Assets.xcassets      hand-drawn sprites and app icons
Scroll of Doom iOS/    app and scene delegates
```

## Status

Hobby project, still in progress. Worth knowing:

- The 56 campaign levels currently all use a generated zigzag layout as a placeholder — hand-built rooms
  aren't in yet. The level editor is where the real level design lives right now.
- No audio.
- Most home screen apps (Messages, Camera, Clock, Maps, the dock) are set dressing and don't open.
  PLAY, Gallery and Settings are the real ones.
- `GameScene.swift` is an earlier endless-tower prototype, kept around but no longer part of the game.

## Credits

Everything — code, sprites, app icons — by [@iediot](https://github.com/iediot).
