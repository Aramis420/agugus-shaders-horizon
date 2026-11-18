# Agugus Shaders (Stable)

A native **Horizon** shader pack (`.hshader`) for **shader API 0.1** — the
line served by Horizon's **stable releases** (`v0.2.97` and its era, built
2026-10-28). Soft pastel light, warm torchlight, fancy water, atmospheric
fog, bloom and a gentle grade, across the Overworld, Nether and End.

A shader API **0.2 edition** of Agugus Shaders exists for newer builds
(nightly-2026-11-18 and later). This pack is pinned to the 0.1 line, and a
0.1 pack is refused on a 0.2 build: `needs shader API 0.1; this Horizon
serves 0.2`.

## The stages

Shader API 0.1 has three stages — `[sky]`, `[material]`, `[[post]]` — plus
options. The pack is built entirely on them:

| Stage | File | What it does |
| --- | --- | --- |
| `[sky]` | `sky.wgsl` | the two-colour sky gradient and the sun glare, from dawn through night |
| `[material]` | `material.wgsl` | the pack light mix over every terrain surface, and fancy water: the pack's colour over the biome tint, layered wave normals, fresnel, sky reflection with a sun glint |
| post: Atmosphere | `atmosphere.wgsl` | the height-gated atmospheric mist, the border fade toward the sky, the underwater colour treatment, blindness/darkness fog, and the End's aurora sky |
| post: Godrays | `godrays.wgsl` | a screen-space march toward the sun or moon, counting the sky it sees through (off by default) |
| post: SSAO | `ssao.wgsl` | eight poisson samples against the depth with a screen-derivative normal (off by default) |
| post: Bloom | `bloom.wgsl` | one pass, two rings of taps, gated by a luminance curve |
| post: Grade | `final.wgsl` | exposure, the tonemap operator, gamma, CAS sharpening, vibrance, saturation, contrast, film grain, vignette, dither |

The shared helpers — the colour schemes, the time-of-day windows, the light
mix, the tonemap operators, the fog stack and the procedural noise — live in
`common.wgsl`.

## What the 0.1 API line carries, and what it doesn't

This line's `MaterialInput` has no normal field (the surface normal comes
from screen derivatives) and no fluid field (water is told from glass by the
biome tint). It predates `[[textures]]`, so every noise is procedural. The
engine always draws vanilla's sun, moon, stars and clouds over the `[sky]`
result, and lights entities and weather itself.

Not available on this line (these need shader API 0.2):

- waving plants, leaves and water (a `[vertex]` stage)
- the pack's entity and weather lighting (`[entity]`/`[weather]` stages)
- pack-drawn clouds, stars and the aurora borealis
- the water mirror (`[reflection]`)
- SMAA (lookup textures) and motion blur
- the moon phase's influence on night light

## Options

A flat list (0.1 has no pages), the ~40 with visible effect: the colour
scheme (Default / Vanilla / Choc v7 / Visually Vibrant) and tonemap operator
(ACES Film / Reinhard-Jodie / ACES Slow / Hejl 2015), exposure and the
grade, the torch light and the time-of-day ambients, the water colour set,
bloom, godrays, SSAO, film grain, vignette and sharpening. The per-channel
colour trims beyond those live in `common.wgsl` as constants at the shipped
defaults.

## Note on colour

The 0.1 line is the gamma line: stages read and return display values. This
pack works in linear light between its stages (the `[sky]` and `[material]`
stages encode what they return; the post chain encodes in its last pass).

## License

MIT — see `LICENSE`.
