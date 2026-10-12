# Approved visual baselines

This directory holds **approved reference PNGs**, not the latest run's screenshots.
For each surface opted into the structural layout snapshot, the filename is
`<app>-<surface>-<viewport>.png`, derived from
`MASTER/gates/data/geometry_surfaces.yml`. The rendered gate never copies a
fresh screenshot here during an ordinary run or through `GATE_AUTOFIX`.

## Compare

Run the rendered diagnostics with the apps serving and Chromium available:

```zsh
ruby MASTER/gates/runner.rb browser_diagnostics
```

The manifest and PNGs go to the system temporary directory under
`pub4-browser-diagnostics/<run-id>/`. For a surface with an approved PNG, its
row records exact changed-pixel count, ratio, approved reference path and a
red/transparent difference image when pixels changed. The default blocking
budget is 1% of pixels per viewport; set `GATE_PIXEL_DIFF_MAX_RATIO=0` for exact
pixel equality or choose an explicit ratio between 0 and 1. An image-dimension
change is always a failure, not a skipped comparison.

Surfaces without an approved PNG remain explicitly marked as missing and are
reported as soft findings by default, while the structural layout snapshots
continue to run. Set `GATE_PIXEL_BASELINE_STRICT=1` to make missing or
unsupported pixel baselines blocking. This lets the inventory be seeded
gradually without claiming that un-compared pixels passed.

## Approve

Only after visually reviewing a clean, stable capture, explicitly approve the
current PNGs for every passing surface selected by the inventory:

```zsh
GATE_PIXEL_BASELINE_APPROVE=1 ruby MASTER/gates/runner.rb browser_diagnostics
git diff -- MASTER/gates/data/visual_baselines
```

Approval only writes PNGs for surfaces whose runtime checks passed and whose
screenshots were successfully delivered. Inspect the diff images and current
screenshots before committing the generated files. Do not set the approval
variable as part of `/fix`, autofix, deployment or routine verification.

PNG comparisons use a dependency-free Ruby decoder for Chromium's non-interlaced
8-bit RGB/RGBA screenshots. Unsupported/corrupt images are reported rather than
silently treated as equal. Keep the browser, operating system, device scale,
fonts, locale and viewport stable when producing a baseline; use separate
references when the rendering environment deliberately differs.
