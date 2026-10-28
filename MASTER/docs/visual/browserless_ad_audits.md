# Browserless visual audit for ad creatives

The ad-visual audit can run without Chromium, Firefox, WebKit, a hosted browser, or network access. It uses a deterministic Ruby source analyzer for a supported subset of static HTML/CSS and records its measurement mode in the report.

## Run it

Create a JSON manifest containing the creative source, CSS, placement, and optionally an asset root and viewport. For example:

    {
      "placement": "display-320x250",
      "html": "<aside class=\"ad-organ\"><h1 class=\"ad-organ-headline\">Strong offer</h1><img class=\"ad-organ-logo\" src=\"logo.png\" alt=\"Brand logo\" width=\"40\" height=\"20\"><span class=\"ad-organ-disclosure\">Sponsored</span><a class=\"ad-organ-cta\">Shop now</a></aside>",
      "css": "html, body { margin: 0; padding: 0; } .ad-organ { position: relative; width: 320px; height: 250px; background-color: var(--ad-organ-surface); color: var(--ad-organ-on-surface); } .ad-organ-headline { margin: 0; position: absolute; left: 16px; top: 16px; width: 180px; height: 40px; font-size: 18px; line-height: 1.2; } .ad-organ-logo { position: absolute; left: 260px; top: 12px; width: 40px; height: 20px; } .ad-organ-disclosure { display: inline-block; position: absolute; left: 16px; top: 60px; width: 86px; height: 24px; font-size: 14px; line-height: 1.2; color: var(--ad-organ-disclosure-foreground); background-color: var(--ad-organ-disclosure-background); } .ad-organ-cta { display: block; position: absolute; left: 200px; top: 200px; width: 100px; height: 32px; font-size: 14px; line-height: 1.2; color: var(--ad-organ-on-surface); background-color: var(--ad-organ-surface); }",
      "asset_root": "."
    }

Save as creative.json beside logo.png, then run from MASTER:

    ruby tools/visual/audit_ad.rb /path/to/creative.json

or:

    AD_VISUAL_MANIFEST=/path/to/creative.json bundle exec rake ad_organ:lint_visual

A relative asset_root is resolved against the creative manifest directory; when omitted, the manifest directory itself is used. Asset paths are constrained to that directory; the analyzer does not fetch remote URLs. Embedded data images and local PNG, GIF, JPEG, WebP VP8X, and SVG metadata are inspected. The placement should contain dimensions such as 320x250, or the manifest must provide viewport with width 320 and height 250.

Run focused tests using bundle exec rake ad_organ:test_browserless. The full rake audit task includes this focused suite.

## Evidence and boundaries

The report distinguishes browserless_static evidence from evidence supplied by a real renderer. The analyzer measures the declared viewport, explicit pixel boxes, local asset byte counts and supported image metadata. It estimates glyph width with a conservative character-width model, estimates text fit, resolves simple CSS selector/cascade rules, measures token-resolved colour contrast, and measures disclosure distance from the nearest headline/logo/CTA box, and reports overlaps between the headline, logo, CTA and disclosure.

High-confidence safe-zone passes require explicit absolute/fixed left, top, width, and height for headline, logo, and CTA. Full-document inputs must explicitly reset body margin and padding. Headings need explicit font size and zero margins; CTA/disclosure boxes must declare a measurable display mode. Non-zero margin, padding, or border on critical boxes is outside this static geometry subset. Overlapping key-element boxes fail the structural proof. Flow/flex-derived geometry is marked estimated and cannot certify the safe zone. Text-fit values are heuristic and reserve 20% headroom. Remote assets, external stylesheets, JavaScript, custom web fonts, CSS Grid, unsupported media queries, complex calc/clamp/min/max geometry, dynamic selectors, and layout-changing animation/transition cause an incomplete result rather than an optimistic pass.

Static source analysis cannot observe paints, JavaScript runtime behaviour, font rasterization, network timing, or actual Cumulative Layout Shift. When static evidence qualifies, the report uses the basis browserless_structural_proxy_not_measured_cls: it proves only that the supported source reserves media geometry and has no detected late layout changes. It never writes a fabricated numeric CLS score. This proxy is accepted by the render-integrity law only when its structural proof is complete. Use a real render capture for creatives that need evidence outside the supported static subset.
