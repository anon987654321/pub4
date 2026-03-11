#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

typeset -r APP_DIR="/home/hjerterom/app"

echo "==> [styles] Hjerterom — warm, nurturing mental health theme"
cd "$APP_DIR"

mkdir -p app/assets/stylesheets

cat > app/assets/stylesheets/application.scss << 'SCSS'
/* HJERTEROM — Mental Health Journaling */

:root {
  --bg:          #fdf8f2;
  --surface:     #fffdf9;
  --surface-alt: #f5ede0;
  --primary:     #c17f4a;
  --primary-dark:#8b5e34;
  --accent:      #d4956a;
  --warm:        #e8c4a0;
  --text:        #2c1f0f;
  --text-dim:    #7a6454;
  --border:      #e6d5c3;
  --radius:      14px;
  --shadow:      0 2px 16px rgba(139, 94, 52, 0.08);
}

* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  font-family: 'Georgia', 'Palatino Linotype', serif;
  background: var(--bg);
  color: var(--text);
  line-height: 1.8;
  min-height: 100vh;
}

a {
  color: var(--primary);
  text-decoration: none;
  &:hover { color: var(--primary-dark); }
}

header {
  background: var(--surface);
  border-bottom: 1px solid var(--border);
  padding: 1.25rem 2rem;
  display: flex;
  align-items: center;
  justify-content: space-between;

  .logo {
    font-size: 1.5rem;
    font-weight: 600;
    color: var(--primary-dark);
    letter-spacing: 0.01em;
  }

  nav a {
    margin-left: 1.5rem;
    color: var(--text-dim);
    font-size: 0.9rem;
    &:hover { color: var(--primary); }
  }
}

main { max-width: 760px; margin: 0 auto; padding: 2.5rem 1.5rem; }

h1 {
  font-size: 1.9rem;
  color: var(--primary-dark);
  margin-bottom: 1rem;
  font-weight: 600;
}

h2 { font-size: 1.3rem; color: var(--text); margin-bottom: 0.75rem; }

.journal-entry {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 1.75rem;
  margin-bottom: 1.5rem;
  box-shadow: var(--shadow);
  position: relative;

  &::before {
    content: '';
    position: absolute;
    left: 0; top: 0; bottom: 0;
    width: 4px;
    background: var(--accent);
    border-radius: var(--radius) 0 0 var(--radius);
  }

  .entry-date {
    font-size: 0.8rem;
    color: var(--text-dim);
    margin-bottom: 0.6rem;
    font-family: system-ui, sans-serif;
  }

  .entry-content {
    font-size: 1rem;
    line-height: 1.85;
    color: var(--text);
  }

  .mood-tag {
    display: inline-block;
    background: var(--surface-alt);
    color: var(--primary-dark);
    border-radius: 999px;
    padding: 0.15rem 0.7rem;
    font-size: 0.78rem;
    font-family: system-ui, sans-serif;
    margin-top: 0.75rem;
  }
}

.prompt-card {
  background: linear-gradient(135deg, var(--surface-alt), var(--warm));
  border-radius: var(--radius);
  padding: 1.5rem 1.75rem;
  margin-bottom: 1.5rem;
  border: 1px solid var(--border);

  .prompt-label {
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--primary);
    font-family: system-ui, sans-serif;
    margin-bottom: 0.5rem;
  }

  p { font-size: 1.05rem; color: var(--text); font-style: italic; }
}

.btn {
  display: inline-block;
  padding: 0.65rem 1.5rem;
  border-radius: 999px;
  font-size: 0.9rem;
  cursor: pointer;
  border: none;
  transition: all 0.2s;
  font-family: system-ui, sans-serif;

  &-primary {
    background: var(--primary);
    color: #fff;
    &:hover { background: var(--primary-dark); color: #fff; }
  }

  &-soft {
    background: var(--surface-alt);
    color: var(--primary-dark);
    &:hover { background: var(--warm); }
  }
}

.form-group {
  margin-bottom: 1.25rem;

  label {
    display: block;
    font-size: 0.9rem;
    color: var(--text-dim);
    margin-bottom: 0.4rem;
    font-family: system-ui, sans-serif;
  }

  textarea {
    width: 100%;
    padding: 0.85rem 1rem;
    border: 1.5px solid var(--border);
    border-radius: 10px;
    background: var(--surface);
    color: var(--text);
    font-family: 'Georgia', serif;
    font-size: 1rem;
    line-height: 1.8;
    min-height: 180px;
    resize: vertical;
    outline: none;
    &:focus { border-color: var(--primary); box-shadow: 0 0 0 3px rgba(193, 127, 74, 0.12); }
  }

  input, select {
    width: 100%;
    padding: 0.65rem 1rem;
    border: 1.5px solid var(--border);
    border-radius: 10px;
    background: var(--surface);
    color: var(--text);
    font-size: 0.95rem;
    outline: none;
    font-family: system-ui, sans-serif;
    &:focus { border-color: var(--primary); box-shadow: 0 0 0 3px rgba(193, 127, 74, 0.12); }
  }
}

.streak-badge {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  background: var(--surface-alt);
  border-radius: 999px;
  padding: 0.3rem 0.9rem;
  font-size: 0.85rem;
  color: var(--primary-dark);
  font-family: system-ui, sans-serif;
  font-weight: 600;
}

.flash-notice { background: #f0fdf4; color: #166534; border: 1px solid #bbf7d0; border-radius: 10px; padding: 0.75rem 1rem; margin-bottom: 1rem; font-family: system-ui, sans-serif; }
.flash-alert  { background: #fef2f2; color: #991b1b; border: 1px solid #fecaca; border-radius: 10px; padding: 0.75rem 1rem; margin-bottom: 1rem; font-family: system-ui, sans-serif; }

@media (max-width: 640px) {
  header { padding: 1rem; }
  main { padding: 1.5rem 1rem; }
  .journal-entry { padding: 1.25rem 1rem 1.25rem 1.5rem; }
}
SCSS

echo "==> hjerterom styles written"
