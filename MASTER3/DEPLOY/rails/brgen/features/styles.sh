#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

typeset -r APP_DIR="/home/brgen/app"

echo "==> [styles] Dark theme + PWA manifest"
cd "$APP_DIR"

cat > app/assets/stylesheets/application.scss << 'SCSS'
/* BRGEN - Minimalist Dark Theme */

:root {
  --color-bg: #0a0a0a;
  --color-surface: #1a1a1a;
  --color-text: #e8eaed;
  --color-text-dim: #9aa0a6;
  --color-primary: #8ab4f8;
  --color-upvote: #ff4500;
  --color-downvote: #7193ff;
  --spacing-unit: 8px;
  --border-radius: 8px;
}

* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  font-family: system-ui, -apple-system, sans-serif;
  background-color: var(--color-bg);
  color: var(--color-text);
  line-height: 1.6;
}

section {
  max-width: 1200px;
  margin: 0 auto;
  padding: calc(var(--spacing-unit) * 2);
}

h1 { font-size: 2rem;   margin-bottom: calc(var(--spacing-unit) * 2); }
h2 { font-size: 1.5rem; margin-bottom: var(--spacing-unit); }

article.post, article.comment {
  background: var(--color-surface);
  border-radius: var(--border-radius);
  padding: calc(var(--spacing-unit) * 2);
  margin-bottom: calc(var(--spacing-unit) * 2);
  &:hover { transform: translateY(-2px); }
}

.community-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: calc(var(--spacing-unit) * 2);
}

.community-card {
  background: var(--color-surface);
  border-radius: var(--border-radius);
  padding: calc(var(--spacing-unit) * 2);
  transition: transform 0.2s;
  &:hover { transform: scale(1.02); }
  a { color: var(--color-text); text-decoration: none; }
}

.vote-controls {
  display: flex;
  align-items: center;
  gap: var(--spacing-unit);
  margin-top: var(--spacing-unit);
  .karma { color: var(--color-upvote); font-weight: bold; }
}

.meta { color: var(--color-text-dim); font-size: 0.85rem; }

@media (max-width: 768px) {
  section { padding: var(--spacing-unit); }
  .community-grid { grid-template-columns: 1fr; }
}
SCSS

mkdir -p public
cat > public/manifest.json << 'JSON'
{
  "name": "BRGEN",
  "short_name": "BRGEN",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#0a0a0a",
  "theme_color": "#8ab4f8",
  "icons": []
}
JSON

echo "==> [styles] done"
