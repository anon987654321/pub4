#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

typeset -r APP_DIR="/home/amber/app"

echo "==> [styles] Amber — light fashion/wardrobe theme"
cd "$APP_DIR"

mkdir -p app/assets/stylesheets

cat > app/assets/stylesheets/application.scss << 'SCSS'
/* AMBER — Fashion & Wardrobe */

:root {
  --primary:      #d946ef;
  --primary-dark: #a21caf;
  --secondary:    #a855f7;
  --accent:       #ec4899;
  --bg:           #fdf4ff;
  --surface:      #ffffff;
  --surface-alt:  #fae8ff;
  --text:         #1a0a24;
  --text-dim:     #6b7280;
  --border:       #e9d5ff;
  --radius:       12px;
  --shadow:       0 2px 12px rgba(217, 70, 239, 0.10);
}

* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  font-family: 'Georgia', 'Times New Roman', serif;
  background: var(--bg);
  color: var(--text);
  line-height: 1.7;
  min-height: 100vh;
}

a {
  color: var(--primary);
  text-decoration: none;
  &:hover { color: var(--primary-dark); text-decoration: underline; }
}

header {
  background: var(--surface);
  border-bottom: 1px solid var(--border);
  padding: 1rem 2rem;
  display: flex;
  align-items: center;
  justify-content: space-between;
  box-shadow: var(--shadow);

  .logo {
    font-size: 1.6rem;
    font-weight: 700;
    color: var(--primary);
    letter-spacing: -0.02em;
  }

  nav a {
    margin-left: 1.5rem;
    color: var(--text-dim);
    font-size: 0.9rem;
    &:hover { color: var(--primary); text-decoration: none; }
  }
}

main { max-width: 1100px; margin: 0 auto; padding: 2rem 1rem; }

h1 { font-size: 2rem; color: var(--primary-dark); margin-bottom: 1rem; }
h2 { font-size: 1.4rem; color: var(--text); margin-bottom: 0.75rem; }

.item-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
  gap: 1.5rem;
  margin-top: 1.5rem;
}

.item-card {
  background: var(--surface);
  border-radius: var(--radius);
  border: 1px solid var(--border);
  overflow: hidden;
  box-shadow: var(--shadow);
  transition: transform 0.2s, box-shadow 0.2s;

  &:hover {
    transform: translateY(-4px);
    box-shadow: 0 8px 24px rgba(217, 70, 239, 0.18);
  }

  img {
    width: 100%;
    aspect-ratio: 3/4;
    object-fit: cover;
    background: var(--surface-alt);
  }

  .item-info {
    padding: 0.85rem 1rem;
    h3 { font-size: 0.95rem; margin-bottom: 0.25rem; }
    .price { color: var(--primary); font-weight: 700; }
    .brand { color: var(--text-dim); font-size: 0.8rem; }
  }
}

.tag {
  display: inline-block;
  background: var(--surface-alt);
  color: var(--primary-dark);
  border-radius: 999px;
  padding: 0.2rem 0.75rem;
  font-size: 0.8rem;
  margin: 0.2rem;
}

.btn {
  display: inline-block;
  padding: 0.6rem 1.4rem;
  border-radius: 999px;
  font-size: 0.9rem;
  cursor: pointer;
  border: none;
  transition: all 0.2s;

  &-primary {
    background: var(--primary);
    color: #fff;
    &:hover { background: var(--primary-dark); color: #fff; text-decoration: none; }
  }

  &-outline {
    background: transparent;
    border: 1.5px solid var(--primary);
    color: var(--primary);
    &:hover { background: var(--primary); color: #fff; text-decoration: none; }
  }
}

.form-group {
  margin-bottom: 1rem;
  label { display: block; font-size: 0.9rem; color: var(--text-dim); margin-bottom: 0.3rem; }
  input, select, textarea {
    width: 100%;
    padding: 0.6rem 0.9rem;
    border: 1.5px solid var(--border);
    border-radius: 8px;
    background: var(--surface);
    color: var(--text);
    font-size: 0.95rem;
    outline: none;
    &:focus { border-color: var(--primary); box-shadow: 0 0 0 3px rgba(217,70,239,0.12); }
  }
}

.flash-notice { background: #f0fdf4; color: #166534; border: 1px solid #bbf7d0; border-radius: 8px; padding: 0.75rem 1rem; margin-bottom: 1rem; }
.flash-alert  { background: #fef2f2; color: #991b1b; border: 1px solid #fecaca; border-radius: 8px; padding: 0.75rem 1rem; margin-bottom: 1rem; }

@media (max-width: 640px) {
  header { padding: 0.75rem 1rem; }
  .item-grid { grid-template-columns: repeat(2, 1fr); gap: 0.75rem; }
  main { padding: 1rem 0.75rem; }
}
SCSS

echo "==> amber styles written"
