#!/usr/bin/env zsh
set -euo pipefail
# Modern CSS 2024: Container Queries, Cascade Layers, Native Nesting
# Zero framework dependencies - native browser features
generate_modern_css() {
  local app_name="${1:-App}"
  log "Generating modern CSS with 2024 features"
  cat <<'EOF' > app/assets/stylesheets/modern.css
/* Modern CSS 2024 - Container Queries, Cascade Layers, Native Nesting */
/* Cascade Layers: Explicit specificity control */
@layer reset, base, components, utilities;
@layer reset {
  *, *::before, *::after { box-sizing: border-box; }
  * { margin: 0; padding: 0; }
  body { line-height: 1.5; -webkit-font-smoothing: antialiased; }
  img, picture, video, canvas, svg { display: block; max-width: 100%; }
  input, button, textarea, select { font: inherit; }
  p, h1, h2, h3, h4, h5, h6 { overflow-wrap: break-word; }
}
@layer base {
  :root {
    --spacing-xs: 0.25rem;
    --spacing-sm: 0.5rem;
    --spacing-md: 1rem;
    --spacing-lg: 1.5rem;
    --spacing-xl: 2rem;
    --color-primary: #1a73e8;
    --color-secondary: #5f6368;
    --color-success: #0f9d58;
    --color-danger: #d93025;
    --color-warning: #f9ab00;
    --font-sans: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    --font-mono: 'SF Mono', Monaco, 'Cascadia Code', monospace;
    --radius-sm: 0.25rem;
    --radius-md: 0.5rem;
    --radius-lg: 1rem;
    --shadow-sm: 0 1px 2px rgba(0,0,0,0.05);
    --shadow-md: 0 4px 6px rgba(0,0,0,0.1);
    --shadow-lg: 0 10px 15px rgba(0,0,0,0.1);
  }
  body {
    font-family: var(--font-sans);
    color: var(--color-secondary);
  }
  h1, h2, h3, h4, h5, h6 { color: #000; }
}
@layer components {
  /* Container Queries: Component responds to container size, not viewport */
  .card-container {
    container-type: inline-size;
    container-name: card;
  }
  .card {
    background: white;
    border-radius: var(--radius-md);
    padding: var(--spacing-md);
    box-shadow: var(--shadow-sm);
    /* Native CSS Nesting */
    & header {
      margin-bottom: var(--spacing-md);
      padding-bottom: var(--spacing-sm);
      border-bottom: 1px solid #e8eaed;
    }
    & h2 {
      font-size: 1.25rem;
      font-weight: 600;
    }
    & p {
      color: var(--color-secondary);
      line-height: 1.6;
    }
    &:hover {
      box-shadow: var(--shadow-md);
      transform: translateY(-2px);
      transition: all 0.2s ease;
    }
  }
  /* Container query: Larger card layout at 400px+ container width */
  @container card (min-width: 400px) {
    .card {
      display: grid;
      grid-template-columns: 150px 1fr;
      gap: var(--spacing-md);
      & img {
        width: 150px;
        height: 150px;
        object-fit: cover;
        border-radius: var(--radius-md);
      }
      & h2 { font-size: 1.5rem; }
    }
  }
  /* Container query: Full-width hero at 600px+ */
  @container card (min-width: 600px) {
    .card {
      grid-template-columns: 200px 1fr;
      padding: var(--spacing-lg);
      & img {
        width: 200px;
        height: 200px;
      }
      & h2 { font-size: 2rem; }
    }
  }
  /* Form container with responsive behavior */
  .form-container {
    container-type: inline-size;
    container-name: form;
  }
  .form-grid {
    display: grid;
    gap: var(--spacing-md);
    & label {
      display: block;
      margin-bottom: var(--spacing-xs);
      font-weight: 500;
    }
    & input, & textarea, & select {
      width: 100%;
      padding: var(--spacing-sm);
      border: 1px solid #dadce0;
      border-radius: var(--radius-sm);
      &:focus {
        outline: 2px solid var(--color-primary);
        outline-offset: 2px;
      }
    }
  }
  @container form (min-width: 500px) {
    .form-grid {
      grid-template-columns: repeat(2, 1fr);
      & .full-width {
        grid-column: 1 / -1;
      }
    }
  }
  /* Button component with nested states */
  .btn {
    display: inline-block;
    padding: var(--spacing-sm) var(--spacing-md);
    border: none;
    border-radius: var(--radius-sm);
    font-weight: 500;
    cursor: pointer;
    transition: all 0.2s ease;
    &-primary {
      background: var(--color-primary);
      color: white;
      &:hover { background: #1557b0; }
      &:active { transform: scale(0.98); }
    }
    &-secondary {
      background: #f1f3f4;
      color: var(--color-secondary);
      &:hover { background: #e8eaed; }
    }
    &-danger {
      background: var(--color-danger);
      color: white;
      &:hover { background: #b3261e; }
    }
  }
  /* Alert component */
  .alert {
    padding: var(--spacing-md);
    border-radius: var(--radius-md);
    margin-bottom: var(--spacing-md);
    &-success {
      background: #e6f4ea;
      color: #137333;
      border-left: 4px solid var(--color-success);
    }
    &-danger {
      background: #fce8e6;
      color: #c5221f;
      border-left: 4px solid var(--color-danger);
    }
    &-warning {
      background: #fef7e0;
      color: #b06000;
      border-left: 4px solid var(--color-warning);
    }
  }
  /* Navigation with container queries */
  .nav-container {
    container-type: inline-size;
  }
  nav {
    display: flex;
    gap: var(--spacing-sm);
    padding: var(--spacing-md);
    background: white;
    box-shadow: var(--shadow-sm);
    & a {
      padding: var(--spacing-sm) var(--spacing-md);
      text-decoration: none;
      color: var(--color-secondary);
      border-radius: var(--radius-sm);
      &:hover {
        background: #f1f3f4;
      }
      &.active {
        background: var(--color-primary);
        color: white;
      }
    }
  }
  @container (max-width: 600px) {
    nav {
      flex-direction: column;
      & a { width: 100%; }
    }
  }
}
@layer utilities {
  .text-center { text-align: center; }
  .text-left { text-align: left; }
  .text-right { text-align: right; }
  .hidden { display: none; }
  .visible { display: block; }
  .flex { display: flex; }
  .grid { display: grid; }
  .gap-sm { gap: var(--spacing-sm); }
  .gap-md { gap: var(--spacing-md); }
  .gap-lg { gap: var(--spacing-lg); }
  .p-sm { padding: var(--spacing-sm); }
  .p-md { padding: var(--spacing-md); }
  .p-lg { padding: var(--spacing-lg); }
  .m-sm { margin: var(--spacing-sm); }
  .m-md { margin: var(--spacing-md); }
  .m-lg { margin: var(--spacing-lg); }
  .rounded { border-radius: var(--radius-md); }
  .shadow { box-shadow: var(--shadow-md); }
}
/* Reduced motion preference */
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}
/* Dark mode support */
@media (prefers-color-scheme: dark) {
  :root {
    --color-secondary: #e8eaed;
  }
  body {
    background: #202124;
    color: #e8eaed;
  }
  @layer components {
    .card {
      background: #292a2d;
      color: #e8eaed;
    }
  }
}
EOF
  log "✓ Modern CSS generated with container queries, cascade layers, and nesting"
}
# Add to application.css manifest
add_modern_css_to_manifest() {
  local manifest="app/assets/stylesheets/application.css"
  if [[ -f "$manifest" ]]; then
    # Pure zsh: check if already added
    local content=$(<"$manifest")
    [[ "$content" == *"modern.css"* ]] && return 0
    print "
 *= require modern" >> "$manifest"
    log "✓ Added modern.css to application.css manifest"
  fi
}
