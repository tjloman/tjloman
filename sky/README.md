# The painted sky

Drop an image here and it is added to the sky. Delete it and the sky goes back
to its gradient and its stars. Nothing here is required — the game ships and
runs with this folder empty, which is the state it is in now.

Names tried, in order: `band` · `horizon` · `sky`
Extensions: `.png` `.webp` `.jpg` `.jpeg` `.exr`

So `sky/band.png` is the file to make.

## What it has to be

**4:1, covering the zenith down to the horizon, across the full 360°.**
2048×512 is a good size. Any aspect is accepted and stretched to fit, but if
you hand it something else you are choosing the stretch rather than deciding it.

- **Left and right edges must meet.** The image wraps all the way round the
  camera. A seam behind the player is the usual way this goes wrong, and it is
  the first thing to check before anything else about the picture.
- **The bottom edge is the horizon. The top edge is straight up.**
- **Black is transparent.** The image is ADDED to the sky the game already
  draws, so black adds nothing and the existing gradient, dusk violet and
  alignment tint all show through untouched. Paint the band and leave the rest
  black — that is why this is a band and not a whole sky.

## Import settings

Set the texture's **Compress > Mode** to **Lossless** in the Import dock, not
VRAM Compressed. The game reads this image pixel by pixel to build the sky, and
a mobile export block-compresses textures (ASTC/ETC2) by default — which reads
back fine on a PC and not at all on a phone or an iPad. The code copes with it
now, but decompressing at boot costs time for nothing.

## What must NOT be in it

These are not style notes. Each one breaks something specific.

- **No sun and no moon.** The game draws both from the actual `DirectionalLight3D`
  that casts the actual shadows, so they are in the right place at every hour
  and every heading. A painted one is wrong within minutes.
- **No stars.** A painted star is always the same brightness, so it cannot come
  out slowly as the player's eyes adapt — and that arrival is the entire effect
  the light meter exists for (see `scripts/world/light_meter.gd`). The stars are
  generated and driven; leave them to it.
- **No ground, no landscape, no trees, no birds.** The bottom edge is the
  horizon line itself. Anything below it is buried in terrain.
- **No lens flare, no vignette, no watermark, no border.**

## What it should be

Cloud form, horizon haze, and the colour of the air. That is the whole job.

**Keep it desaturated and mid-value.** Everything downstream tints it — the
time of day, the dusk violet, and the player's own alignment, which gilds the
sky gold when they are saintly and bruises it toward ash and blood when they
are not. A band that arrives already vivid fights all three and the tinting
stops reading. A band that arrives quiet gets pushed somewhere interesting four
different ways.

**Remember it is additive.** A bright band will blow out over a noon sky. Aim
for something that looks slightly too dim on its own.

## A prompt to start from

> equirectangular 360 degree sky panorama strip, horizon to zenith, seamless
> left-right tiling, layered stratus and cumulus cloud banks near the horizon
> thinning to clear sky above, soft haze, painterly matte backdrop, desaturated
> muted palette, no sun, no moon, no stars, no ground, no horizon line, no
> landscape, flat even lighting, 4:1 aspect ratio

Then check, in this order:

1. Put the left and right edges side by side. If there is a seam, nothing else
   matters yet.
2. Is there a sun in it? Generators add one almost every time, whatever the
   prompt says.
3. Is the bottom edge sky rather than land?
4. Squint. Is it quiet enough to be pushed around?

## Notes for the second one

One band, tinted by everything, is where this starts, deliberately — a single
quiet band under a working light meter goes further than anybody expects, and
you will know much better what the next one should be after you have watched
this one through a few dawns.

When there is a set, the axis worth spending them on is probably **weather**
(clear / overcast / storm) rather than time of day, because the hour is already
handled by the gradient underneath and the weather is not handled at all.

That needs the game to have weather first. It does not: rain is a miracle
somebody casts, not a condition the world is in.
