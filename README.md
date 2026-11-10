# Mare Care

A mod for [Home: Equestria](https://github.com/homedevanon/home-equestria) that adds new ways to
look after your mare.

Built for game version `0.3.0-maredev`. Works on desktop and in VR.

> **Work in progress.** This first piece is brushing. Farrier work, tooth brushing and bathing are
> next.

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

- **Farrier:** hoof care and horseshoes.
- **Tooth brushing**
- **Bathing**

## Credits

- **Brushing** is built on [modChad's Grooming mod](https://github.com/modChad/home-equestria-mods/tree/main/grooming).
  This includes how brushes are detected on a pony, her poses while being brushed, the desktop
  brush strokes, the brush models and the princess hair handling. Thank you, modChad! Their mod
  also does wing preening, which this mod leaves to theirs.
- **Brushing sounds:** modChad's own recordings, from the Grooming mod.
- **Sparkles:** made for this mod.
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
- `merge/world/food/definitions.json`: the brushes as non-edible briefcase items.
