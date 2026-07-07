# bp — business plans

Static HTML/CSS/JS business-plan sites. No generator — hand-maintained pages.

## Layout

```
bp/
  *.html *.css *.js    site pages
  mg_*.yml             structured plan data (footwear, space, …)
```

Open `*.html` in a browser or serve via httpd. YAML files hold tabular/plan data consumed by inline scripts where wired.

## Rules

- Self-contained assets per site
- No committed secrets
- Changes reviewed like any DEPLOY surface