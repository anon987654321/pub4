#!/usr/bin/env zsh
set -euo pipefail

# Default application.css for all Rails apps
# Based on bsdports.sh professional styling
# Supports light/dark mode, responsive design

generate_default_css() {
  local app_name="${1:-App}"
  local primary_color="${2:-#000084}"
  local accent_color="${3:-#5623ee}"
  
  log "Generating default CSS for $app_name"
  
  mkdir -p app/assets/stylesheets
  
  cat <<'CSS_EOF' > app/assets/stylesheets/application.css
/* Default Rails 8 Application Styles */
/* Auto-generated - customize per app */

/* Light mode colors (default) */
:root {
  --white: #ffffff;
  --black: #000000;
  --primary: #000084;
  --accent: #5623ee;
  --bg: #ffffff;
  --surface: #f0f0f0;
  --text: #000000;
  --text-secondary: #666666;
  --border: #ababab;
  --grey-light: #f0f0f0;
  --grey: #999999;
  --grey-dark: #666666;
  --warning: #b04243;
  --success: #28a745;
  --info: #17a2b8;
}

/* Dark mode colors - with improved focus-visible */
@media (prefers-color-scheme: dark) {
  :root {
    --white: #000000;
    --black: #ffffff;
    --primary: #5623ee;
    --accent: #000084;
    --bg: #1a1a1a;
    --surface: #2a2a2a;
    --text: #ffffff;
    --text-secondary: #ababab;
    --border: #666666;
    --grey-light: #666666;
    --grey: #ababab;
    --grey-dark: #f0f0f0;
  }
  
  /* Dark mode focus enhancement */
  *:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: 3px;
  }
}

/* CSS Reset */
* {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}

html {
  font-size: 16px;
  line-height: 1.6;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  background: var(--bg);
  color: var(--text);
  min-height: 100vh;
  display: flex;
  flex-direction: column;
}

/* Typography - using clamp() for responsive sizing */
h1, h2, h3, h4, h5, h6 {
  margin-bottom: 1rem;
  font-weight: 600;
  line-height: 1.2;
}

h1 { font-size: clamp(2rem, 5vw, 2.5rem); }
h2 { font-size: clamp(1.75rem, 4vw, 2rem); }
h3 { font-size: clamp(1.5rem, 3vw, 1.75rem); }
h4 { font-size: clamp(1.25rem, 2.5vw, 1.5rem); }
h5 { font-size: clamp(1.125rem, 2vw, 1.25rem); }
h6 { font-size: 1rem; }

p {
  margin-bottom: 1rem;
}

a {
  color: var(--primary);
  text-decoration: none;
  transition: opacity 0.2s;
}

a:hover {
  opacity: 0.8;
}

/* Layout */
.container {
  max-width: 1200px;
  margin: 0 auto;
  padding: 0 1rem;
}

.site-header {
  background: var(--surface);
  border-bottom: 1px solid var(--border);
  padding: 1rem 0;
}

.site-main {
  flex: 1;
  padding: 2rem 0;
}

.site-footer {
  background: var(--surface);
  border-top: 1px solid var(--border);
  padding: 2rem 0;
  margin-top: auto;
  text-align: center;
  color: var(--text-secondary);
}

/* Navigation */
.nav-main {
  display: flex;
  align-items: center;
  gap: 2rem;
  flex-wrap: wrap;
}

.nav-brand {
  font-size: 1.5rem;
  font-weight: 700;
}

.nav-links {
  display: flex;
  gap: 1.5rem;
  flex-wrap: wrap;
}

.nav-link {
  color: var(--text);
  font-weight: 500;
}

.nav-link:hover {
  color: var(--primary);
}

/* Forms */
input, textarea, select, button {
  font-family: inherit;
  font-size: 1rem;
  line-height: 1.5;
}

input[type="text"],
input[type="email"],
input[type="password"],
input[type="search"],
input[type="number"],
input[type="date"],
textarea,
select {
  width: 100%;
  padding: 0.75rem;
  border: 1px solid var(--border);
  border-radius: 4px;
  background: var(--bg);
  color: var(--text);
  transition: border-color 0.2s;
}

input:focus,
textarea:focus,
select:focus {
  outline: none;
  border-color: var(--primary);
}

/* Buttons */
button,
.button,
input[type="submit"] {
  padding: 0.75rem 1.5rem;
  background: var(--primary);
  color: var(--white);
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-weight: 500;
  transition: opacity 0.2s;
  display: inline-block;
}

button:hover,
.button:hover,
input[type="submit"]:hover {
  opacity: 0.9;
}

button:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.button-secondary {
  background: var(--grey);
}

.button-danger {
  background: var(--warning);
}

/* Flash messages */
.flash {
  padding: 1rem;
  margin-bottom: 1rem;
  border-radius: 4px;
}

.flash-notice {
  background: var(--success);
  color: var(--white);
}

.flash-alert {
  background: var(--warning);
  color: var(--white);
}

/* Cards */
.card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 1.5rem;
  margin-bottom: 1rem;
}

.card h3 {
  margin-top: 0;
}

/* Grid - use gap instead of margin utilities */
.grid {
  display: grid;
  gap: 1.5rem;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
}

/* Utilities */
.hidden {
  display: none;
}

/* Visually hidden but accessible to screen readers */
.visually-hidden {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border-width: 0;
}

.text-center {
  text-align: center;
}

.text-muted {
  color: var(--text-secondary);
}

/* Native <dialog> element styling */
dialog {
  border: none;
  border-radius: 8px;
  padding: 2rem;
  background: var(--surface);
  color: var(--text);
  box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
  max-width: 600px;
  width: 90%;
}

dialog::backdrop {
  background: rgba(0, 0, 0, 0.5);
  backdrop-filter: blur(2px);
}

dialog[open] {
  animation: dialog-fade-in 0.2s ease-out;
}

@keyframes dialog-fade-in {
  from {
    opacity: 0;
    transform: translateY(-20px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

/* Note: Use loading="lazy" on img and iframe elements for performance */

/* Responsive */
@media (max-width: 768px) {
  .container {
    padding: 0 0.5rem;
  }
  
  .nav-main {
    flex-direction: column;
    gap: 1rem;
  }
  
  .nav-links {
    width: 100%;
    justify-content: center;
  }
  
  .grid {
    grid-template-columns: 1fr;
  }
}

/* Focus visible for accessibility */
*:focus-visible {
  outline: 2px solid var(--primary);
  outline-offset: 2px;
}
CSS_EOF

  log "✓ Default CSS generated"
}
