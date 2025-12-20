#!/usr/bin/env zsh
set -euo pipefail

# Default Rails application CSS - Based on bsdports.sh pattern
# Federal Standard colors, light/dark mode, zero framework dependencies

generate_default_application_css() {
  local app_name="${1:-App}"
  
  log "Generating default application CSS"
  
  cat <<'CSS' > app/assets/stylesheets/application.scss
// Default Rails Application Styles
// Based on bsdports.sh pattern - Federal Standard colors
// Light/dark mode support, zero framework dependencies

// CSS Variables - Light mode
:root {
  --white: #ffffff;
  --black: #000000;
  --blue: #000084;
  --light-blue: #5623ee;
  --extra-light-grey: #f0f0f0;
  --light-grey: #ababab;
  --grey: #999999;
  --dark-grey: #666666;
  --warning-red: #b04243; // Federal Standard 595c
  
  --font-sans: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  --font-mono: 'SF Mono', Monaco, 'Cascadia Code', monospace;
  
  --spacing-xs: 0.25rem;
  --spacing-sm: 0.5rem;
  --spacing-md: 1rem;
  --spacing-lg: 1.5rem;
  --spacing-xl: 2rem;
  
  --radius-sm: 4px;
  --radius-md: 8px;
  
  --shadow-sm: 0 1px 2px rgba(0,0,0,0.05);
  --shadow-md: 0 4px 6px rgba(0,0,0,0.1);
}

// Dark mode - invert colors
@media (prefers-color-scheme: dark) {
  :root {
    --white: #000000;
    --black: #ffffff;
    --blue: #5623ee;
    --light-blue: #000084;
    --extra-light-grey: #666666;
    --light-grey: #999999;
    --grey: #ababab;
    --dark-grey: #f0f0f0;
  }
}

// Reset
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

html, body {
  height: 100%;
  font-family: var(--font-sans);
  font-size: 14px;
  color: var(--black);
  background-color: var(--white);
  display: flex;
  flex-direction: column;
}

// Links
a {
  color: var(--light-blue);
  text-decoration: underline;
  
  &:hover {
    color: var(--blue);
  }
}

// Layout
header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: var(--spacing-md) var(--spacing-lg);
  border-bottom: 1px solid var(--extra-light-grey);
}

nav {
  display: flex;
  gap: var(--spacing-md);
  
  a {
    padding: var(--spacing-sm) var(--spacing-md);
    text-decoration: none;
    color: var(--black);
    border-bottom: 2px solid transparent;
    
    &:hover, &.active {
      border-bottom-color: var(--black);
    }
  }
}

main {
  flex: 1;
  padding: var(--spacing-lg);
  max-width: 1200px;
  width: 100%;
  margin: 0 auto;
}

footer {
  color: var(--light-grey);
  font-size: 13px;
  text-align: center;
  padding: var(--spacing-lg);
  border-top: 1px solid var(--extra-light-grey);
}

// Forms
fieldset {
  border: 1px solid var(--extra-light-grey);
  border-radius: var(--radius-md);
  padding: var(--spacing-lg);
  margin-bottom: var(--spacing-md);
}

legend {
  font-weight: bold;
  padding: 0 var(--spacing-sm);
}

label {
  display: block;
  margin-bottom: var(--spacing-xs);
  font-weight: 500;
}

input[type="text"],
input[type="email"],
input[type="password"],
input[type="search"],
textarea,
select {
  width: 100%;
  padding: var(--spacing-sm);
  margin-bottom: var(--spacing-md);
  border: 1px solid var(--extra-light-grey);
  border-radius: var(--radius-sm);
  font-family: inherit;
  font-size: inherit;
  
  &:focus {
    outline: 2px solid var(--light-blue);
    outline-offset: 2px;
  }
}

// Buttons
button, .btn {
  padding: var(--spacing-sm) var(--spacing-md);
  border: none;
  border-radius: var(--radius-sm);
  font-family: inherit;
  font-size: inherit;
  cursor: pointer;
  text-decoration: none;
  display: inline-block;
  
  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
}

.btn-primary {
  background: var(--light-blue);
  color: var(--white);
  
  &:hover:not(:disabled) {
    background: var(--blue);
  }
}

.btn-secondary {
  background: var(--extra-light-grey);
  color: var(--black);
  
  &:hover:not(:disabled) {
    background: var(--light-grey);
  }
}

.btn-danger {
  background: var(--warning-red);
  color: var(--white);
  
  &:hover:not(:disabled) {
    filter: brightness(0.9);
  }
}

// Tables
table {
  width: 100%;
  border-collapse: collapse;
  margin-bottom: var(--spacing-lg);
}

th, td {
  padding: var(--spacing-sm);
  text-align: left;
  border-bottom: 1px solid var(--extra-light-grey);
}

th {
  font-weight: bold;
  background: var(--extra-light-grey);
}

tr:hover {
  background: var(--extra-light-grey);
}

// Alerts
.alert {
  padding: var(--spacing-md);
  margin-bottom: var(--spacing-md);
  border-radius: var(--radius-md);
  border-left: 4px solid;
  
  &.alert-success {
    background: #e6f4ea;
    border-color: #0f9d58;
    color: #137333;
  }
  
  &.alert-danger {
    background: #fce8e6;
    border-color: var(--warning-red);
    color: #c5221f;
  }
  
  &.alert-warning {
    background: #fef7e0;
    border-color: #f9ab00;
    color: #b06000;
  }
  
  &.alert-notice {
    background: #e8f0fe;
    border-color: var(--light-blue);
    color: var(--blue);
  }
}

// Loading states
.loading {
  opacity: 0.5;
  pointer-events: none;
}

body.wait {
  cursor: wait;
}

// Utility classes
.hidden {
  display: none;
}

.text-center {
  text-align: center;
}

.empty-state {
  text-align: center;
  color: var(--grey);
  padding: var(--spacing-xl);
}

// Responsive
@media (max-width: 768px) {
  main {
    padding: var(--spacing-md);
  }
  
  nav {
    flex-direction: column;
  }
}

// Reduced motion
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}
CSS
  
  log "✓ Default application CSS generated"
}
