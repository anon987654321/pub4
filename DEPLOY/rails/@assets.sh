#!/usr/bin/env zsh
# @assets.sh — sourced via @shared_functions.sh
set -euo pipefail

install_dartsass() {
  add_gem dartsass-rails
  bin/rails dartsass:install 2>/dev/null || true
  log_ok "Dart Sass installed"
}

write_base_scss() {
  mkdir -p app/assets/stylesheets
  rm -f app/assets/stylesheets/application.css
  cat > app/assets/stylesheets/application.scss << 'SCSS'
// VARIABLES
:root {
  // Colors
  --color-black: #000;
  --color-white: #fff;
  --color-extra-light-grey: #f0f0f0;

  // Spacing
  --space-xs: 0.25rem;
  --space-sm: 0.5rem;
  --space-md: 1rem;
  --space-lg: 1.5rem;
  --space-xl: 2rem;

  // Typography
  --font-size-base: 14px;
  --line-height-base: 1.5;
}

// RESET & BASE
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

html,
body {
  height: 100%;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
  font-size: var(--font-size-base);
  line-height: var(--line-height-base);
  color: var(--color-black);
  background-color: var(--color-white);
  display: flex;
  flex-direction: column;
}

img { max-width: 100%; display: block; }

a {
  color: #4285f4;
  text-decoration: none;
  cursor: pointer;

  &:hover { text-decoration: underline; }
  &:focus { outline: 2px solid #4285f4; outline-offset: 2px; }
}

// NAV
nav {
  display: flex;
  align-items: center;
  gap: var(--space-md);
  padding: var(--space-sm) var(--space-md);
  border-bottom: 1px solid var(--color-extra-light-grey);

  a { color: inherit; }
  a:hover { text-decoration: underline; }
  .brand { font-weight: 700; margin-right: auto; }
}

// MAIN
main {
  flex: 1;
  display: grid;
  grid-template-columns: 1fr;
  gap: var(--space-md);
  padding: var(--space-md);
}

// FLASH
.flash {
  padding: var(--space-sm) var(--space-md);
  border-bottom: 1px solid var(--color-extra-light-grey);

  &--error, &--alert { color: #c00; }
  &--notice { color: #060; }
}

// RESPONSIVE
@media (max-width: 768px) {
  .header {
    flex-direction: column;
    gap: var(--space-md);
    padding: var(--space-sm);

    &__tabs {
      gap: var(--space-sm);
      flex-wrap: wrap;
      justify-content: center;
    }
  }
}

@media (max-width: 480px) {
  html, body { font-size: 12px; }

  .header__tabs { gap: var(--space-xs); }
  .header__tab { padding: var(--space-xs) var(--space-sm); font-size: 0.9em; }
}
SCSS
  log_ok "application.scss written"
}

write_base_css() { write_base_scss; }
write_layout()     { write_full_layout "$@"; }
