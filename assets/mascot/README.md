# Mascot poses (optional artwork)

The bird is drawn in code (`lib/core/widgets/mascot.dart`): `BirdPainter`
draws him and `MascotOverlayPainter` adds each state's extras. Every state
already looks distinct without any files here:

| State         | Drawn version                                                   |
|---------------|-----------------------------------------------------------------|
| `idle`        | gentle bob, blinks, beak a little open                          |
| `calling`     | talking beak, navy phone by his cheek, sound-wave arcs          |
| `celebrating` | happy eyes, hop with squash-stretch, marigold/blue/pink confetti|
| `resting`     | eyes closed, tilted 6°, light-blue "z z" drifting up and fading |
| `thinking`    | head tilt, three dots rising in a thought trail                 |
| `waving`      | wink, waving wing, rocks ±8°, marigold motion lines             |

Under reduced motion (`MediaQuery.disableAnimations`) each state shows one
still frame that still reads clearly (confetti mid-burst, "z z" visible…).

## Replacing a state with artwork

Drop a file named exactly after the state into this folder:

```
assets/mascot/idle.png
assets/mascot/calling.png
assets/mascot/celebrating.png
assets/mascot/resting.png
assets/mascot/thinking.png
assets/mascot/waving.png
```

- **512 × 512 px, transparent PNG** (RGBA), the bird centred with ~6 %
  padding, feet near the bottom edge. Keep each file under ~120 KB
  (run it through `pngquant` / `oxipng`).
- Same character, palette and flat rounded style as
  `assets/brand/mascot_source.png`.
- No rebuild of code needed: `pubspec.yaml` already bundles this folder and
  `Mascot` checks the asset manifest at runtime. A state with a file shows
  the file (with a subtle bob only – no drawn overlays); a state without one
  keeps the drawing.

The older people-style illustrations that used to sit here were never
bundled and did not match the bird; they now live in
`assets/brand/legacy_mascot/` (not shipped).
