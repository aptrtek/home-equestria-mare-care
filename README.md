# Mare Care

A mod for [Home: Equestria](https://github.com/homedevanon/home-equestria) that adds new ways to
look after your mare.

Built for game version `0.3.0-maredev`. Works on desktop and in VR.

> **Work in progress.** Farrier work and brushing are in. Tooth brushing and bathing are next.

## Farrier

The first time you load a world with the mod on, a farrier's kit appears in your briefcase: a
**Hoof Pick**, **Hoof Nippers**, a **Hoof Rasp**, a **Farrier's Hammer**, **Hoof Oil**, and
horseshoes in four styles: **Steel**, **Silver**, **Gold** and **Rainbow**. The tools never run
out, and you can use them on any willing pony.

1. **Ask for a hoof.** Hold any farrier tool and look at one of her legs, then click (desktop),
   or touch the leg with the tool (VR). She lifts that hoof for you: a front hoof folds back at
   the knee, and a back hoof lifts out behind her with the sole facing you. She stands still while
   it's up.
2. **Work the hoof** with the tool in hand. On desktop, look at the hoof and hold the mouse
   button; the hint under the crosshair says what the tool will do and how far along it is.
   - **Hoof pick:** when picking is due, stones and packed dirt sit in the sole. Pick each one
     out and it drops to the ground.
   - **Nippers, then rasp:** trim the hoof wall with the nippers, then level it with the rasp.
     On a shod hoof, the nippers pull the shoe off first.
   - **Horseshoe:** fit one to a bare hoof. If the hoof needs a trim, trim it first.
   - **Hammer:** drive in all six nails, one click per nail. A shoe that has worked loose is
     re-nailed the same way.
   - **Hoof oil:** work it in, and the hoof shines for a few minutes.
3. **Walk away**, or ask for another hoof, and she puts it down.

Her shoes stay on, in the style you chose, wherever she goes. Every pony's hooves are saved
with your world.

### Upkeep

Hooves need care again over time. A hoof that's due shows it in the hint when you look at her
leg (for example, "needs: picking, a trim, oil"). A shoe that's due for a reset sits a little
crooked, with its nail heads sticking out.

By default, every job comes due again after **7 in-game days**. To change that, edit
`settings.cfg` in the mod's data folder. The mod creates it the first time it runs:

| System | File |
| --- | --- |
| Windows | `%APPDATA%\home-equestria-public\mods\data\mare_care\settings.cfg` |
| Linux | `~/.local/share/home-equestria-public/mods/data/mare_care/settings.cfg` |

```ini
[upkeep]
pick_days=7.0
trim_days=7.0
shoe_days=7.0
oil_days=7.0
```

Set a value to `0` to turn that job's upkeep off: once it's done, it stays done. Changes apply
the next time you start the game.

### What it does for her

Doing a job on a hoof that needed it gains a little friendship. Once all four of her hooves have
had it, she gains more, plus love if she's an adult who is already fond of you, and she remembers
it, so she can bring it up in conversation.

A pony who is angry with you or has asked for space won't lift a hoof. Neither will sleeping
ponies or ponies at the spa.

## Brushing

The first time you load a world with the mod on, a **Mane & Tail Brush** and a **Coat Brush**
appear in your briefcase. If the briefcase is full, they arrive the next time you load the world
with room in it.

- **Mane and tail:** hold the Mane & Tail Brush and stroke her mane or tail. While you brush her
  mane, she tilts her head into the brush. While you brush her tail, she lifts it aside and looks
  back at you. Once you're done, **her mane or tail sparkles** for about ten minutes before the
  shine slowly fades.
- **Coat:** hold the Coat Brush and stroke her neck, back, sides, chest, rump, flanks, belly or legs.
  She leans into it and finishes a long brushing with a happy stretch.

On desktop, look at the part you want to brush and hold the mouse button. In VR, just brush her.

A finished brushing takes about 10 seconds for the mane, 8 for the tail or 14 for the coat. When
it's done, she sighs contentedly, gains friendship with you, and gains love if she's an adult who
is already fond of you. She also remembers it, so she can bring it up in conversation. Each pony
gives this bonus at most once every 10 minutes per brushing. The sparkle comes every time.

A pony who is angry with you or has asked for space turns away. Sleeping ponies can't be brushed.

## Coming next

- **Tooth brushing**
- **Bathing**

## Credits

- **Brushing** is built on [modChad's Grooming mod](https://github.com/modChad/home-equestria-mods/tree/main/grooming).
  This includes how brushes are detected on a pony, her poses while being brushed, the desktop
  brush strokes, the brush models and the princess hair handling. Thank you, modChad! Their mod
  also does wing preening, which this mod leaves to theirs.
- **Brushing sounds:** modChad's own recordings, from the Grooming mod.
- **Sparkles, farrier tools and horseshoes:** made for this mod.
- **Farrier sounds:** the game's own foley (metal, crunch, rasp and cloth sounds).
- **Contented sigh:** the game's own pony breath sounds.

This is a free fan mod.

## Building from source

You need the game's source project and Godot 4.5 stable.

1. Put this folder at `res://mods/mare_care/`.
2. Open the project once so the sounds import:
   ```
   godot --headless --xr-mode off --path <project> --import
   ```
3. Build the pack:
   ```
   godot --headless --xr-mode off --path <project> --script res://tools/modding/build_mod.gd -- mare_care
   ```

To test without building, run the game with the mod unpacked:
```
godot --xr-mode off --path <project> -- --mod-src mare_care
```

### Layout

- `main.gd`: the entry script. It adds each kind of care as its own child node.
- `brushing/`: the brushes, adapted from the Grooming mod, plus `sparkle.gd` for the glints on a
  freshly brushed mane or tail.
- `farrier/`: the farrier. `farrier.gd` runs the jobs, `hooves.gd` finds her soles and lifts
  her hooves, `shoes.gd` keeps the shoes on, `hoof_care.gd` holds what was done and when, plus
  the upkeep settings, and `models.gd` builds the tools and shoes. To regenerate the tool models:
  `godot --headless --xr-mode off --path <project> --script res://mods/mare_care/farrier/tools/make_farrier_models.gd`.
- `merge/world/food/definitions.json`: the brushes and farrier tools as non-edible briefcase items.
