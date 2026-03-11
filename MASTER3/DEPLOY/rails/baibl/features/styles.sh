#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

typeset -r APP_DIR="/home/baibl/app"

echo "==> [styles] Baibl — scripture/gold contemplative theme"
cd "$APP_DIR"

mkdir -p app/assets/stylesheets

cat > app/assets/stylesheets/application.scss << 'SCSS'
/* BAIBL — Scripture & Contemplation */

:root {
  --bg:          #0f0e0b;
  --surface:     #1a1812;
  --surface-alt: #221f16;
  --primary:     #c9a96e;
  --primary-light:#e2c98c;
  --primary-dark: #a07c40;
  --accent:      #d4b483;
  --text:        #f0ead6;
  --text-dim:    #8a7f68;
  --border:      #2e2a1e;
  --gold-line:   rgba(201, 169, 110, 0.25);
  --radius:      10px;
  --shadow:      0 4px 24px rgba(0, 0, 0, 0.45);
}

* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  font-family: 'Palatino Linotype', 'Book Antiqua', Palatino, Georgia, serif;
  background: var(--bg);
  color: var(--text);
  line-height: 1.85;
  min-height: 100vh;
}

a {
  color: var(--primary);
  text-decoration: none;
  &:hover { color: var(--primary-light); }
}

header {
  background: var(--surface);
  border-bottom: 1px solid var(--gold-line);
  padding: 1.25rem 2rem;
  display: flex;
  align-items: center;
  justify-content: space-between;

  .logo {
    font-size: 1.5rem;
    font-weight: 600;
    color: var(--primary);
    letter-spacing: 0.04em;
    font-variant: small-caps;
  }

  nav a {
    margin-left: 1.5rem;
    color: var(--text-dim);
    font-size: 0.9rem;
    letter-spacing: 0.02em;
    &:hover { color: var(--primary); }
  }
}

main { max-width: 820px; margin: 0 auto; padding: 3rem 1.5rem; }

h1 {
  font-size: 1.85rem;
  color: var(--primary-light);
  margin-bottom: 1rem;
  font-weight: 400;
  letter-spacing: 0.03em;
  font-variant: small-caps;
}

h2 {
  font-size: 1.3rem;
  color: var(--primary);
  margin-bottom: 0.75rem;
  font-weight: 400;
}

.verse-block {
  background: var(--surface);
  border: 1px solid var(--gold-line);
  border-left: 3px solid var(--primary);
  border-radius: var(--radius);
  padding: 1.75rem 2rem;
  margin-bottom: 1.75rem;
  box-shadow: var(--shadow);

  .verse-reference {
    font-size: 0.78rem;
    color: var(--primary);
    letter-spacing: 0.08em;
    text-transform: uppercase;
    margin-bottom: 0.75rem;
    font-family: system-ui, sans-serif;
  }

  .verse-text {
    font-size: 1.1rem;
    line-height: 1.95;
    color: var(--text);
    font-style: italic;
  }

  .verse-translation {
    font-size: 0.75rem;
    color: var(--text-dim);
    margin-top: 0.75rem;
    font-family: system-ui, sans-serif;
  }
}

.devotional-card {
  background: var(--surface-alt);
  border: 1px solid var(--gold-line);
  border-radius: var(--radius);
  padding: 1.5rem;
  margin-bottom: 1.25rem;
  box-shadow: var(--shadow);
  transition: border-color 0.2s;

  &:hover { border-color: var(--primary-dark); }

  .card-date {
    font-size: 0.75rem;
    color: var(--text-dim);
    font-family: system-ui, sans-serif;
    margin-bottom: 0.5rem;
    letter-spacing: 0.04em;
    text-transform: uppercase;
  }

  h3 { font-size: 1rem; color: var(--primary-light); margin-bottom: 0.5rem; font-weight: 400; }
  p  { font-size: 0.9rem; color: var(--text-dim); line-height: 1.7; }
}

.ornament {
  text-align: center;
  color: var(--primary-dark);
  font-size: 1.2rem;
  letter-spacing: 0.5em;
  margin: 2rem 0;
  opacity: 0.6;
}

.search-bar {
  display: flex;
  gap: 0.5rem;
  margin-bottom: 2rem;

  input {
    flex: 1;
    padding: 0.65rem 1rem;
    background: var(--surface);
    border: 1px solid var(--gold-line);
    border-radius: 8px;
    color: var(--text);
    font-family: inherit;
    font-size: 0.95rem;
    outline: none;
    &:focus { border-color: var(--primary); }
    &::placeholder { color: var(--text-dim); }
  }

  button {
    background: var(--primary);
    color: var(--bg);
    border: none;
    border-radius: 8px;
    padding: 0.65rem 1.25rem;
    font-size: 0.9rem;
    cursor: pointer;
    font-weight: 600;
    &:hover { background: var(--primary-light); }
  }
}

.btn {
  display: inline-block;
  padding: 0.6rem 1.4rem;
  border-radius: 8px;
  font-size: 0.9rem;
  cursor: pointer;
  border: none;
  transition: all 0.2s;
  font-family: inherit;

  &-primary {
    background: var(--primary);
    color: var(--bg);
    font-weight: 600;
    &:hover { background: var(--primary-light); color: var(--bg); }
  }

  &-ghost {
    background: transparent;
    border: 1px solid var(--gold-line);
    color: var(--text-dim);
    &:hover { border-color: var(--primary); color: var(--primary); }
  }
}

.form-group {
  margin-bottom: 1.25rem;
  label { display: block; font-size: 0.85rem; color: var(--text-dim); margin-bottom: 0.35rem; font-family: system-ui, sans-serif; letter-spacing: 0.03em; }
  input, select, textarea {
    width: 100%;
    padding: 0.65rem 1rem;
    border: 1px solid var(--gold-line);
    border-radius: 8px;
    background: var(--surface);
    color: var(--text);
    font-family: inherit;
    font-size: 0.95rem;
    outline: none;
    &:focus { border-color: var(--primary); box-shadow: 0 0 0 3px rgba(201,169,110,0.10); }
  }
  textarea { min-height: 140px; resize: vertical; line-height: 1.75; }
}

.flash-notice { background: #0a1a0a; color: #86efac; border: 1px solid #166534; border-radius: 8px; padding: 0.7rem 1rem; margin-bottom: 1rem; font-family: system-ui, sans-serif; }
.flash-alert  { background: #1a0a0a; color: #fca5a5; border: 1px solid #9f1239; border-radius: 8px; padding: 0.7rem 1rem; margin-bottom: 1rem; font-family: system-ui, sans-serif; }

@media (max-width: 640px) {
  header { padding: 1rem; }
  main { padding: 1.5rem 1rem; }
  .verse-block { padding: 1.25rem; }
}
SCSS

echo "==> baibl styles written"
