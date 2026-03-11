#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

typeset -r APP_DIR="/home/privcam/app"

echo "==> [styles] Privcam — dark private camera theme"
cd "$APP_DIR"

mkdir -p app/assets/stylesheets

cat > app/assets/stylesheets/application.scss << 'SCSS'
/* PRIVCAM — Private Video / Webcam */

:root {
  --bg:          #0d0d0d;
  --surface:     #1a1a1a;
  --surface-alt: #222222;
  --primary:     #e11d48;
  --primary-dark:#be123c;
  --accent:      #fb7185;
  --live:        #22c55e;
  --text:        #f3f4f6;
  --text-dim:    #6b7280;
  --border:      #2d2d2d;
  --radius:      10px;
  --shadow:      0 4px 20px rgba(0, 0, 0, 0.5);
}

* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  font-family: system-ui, -apple-system, sans-serif;
  background: var(--bg);
  color: var(--text);
  line-height: 1.5;
  min-height: 100vh;
}

a {
  color: var(--accent);
  text-decoration: none;
  &:hover { color: var(--primary); }
}

header {
  background: #000;
  border-bottom: 1px solid var(--border);
  padding: 0.85rem 1.5rem;
  display: flex;
  align-items: center;
  justify-content: space-between;
  position: sticky;
  top: 0;
  z-index: 100;

  .logo {
    font-size: 1.3rem;
    font-weight: 800;
    color: var(--primary);
    letter-spacing: -0.03em;
  }

  nav a {
    margin-left: 1.25rem;
    color: var(--text-dim);
    font-size: 0.85rem;
    &:hover { color: var(--text); }
  }
}

main { max-width: 1280px; margin: 0 auto; padding: 1.5rem 1rem; }

h1 { font-size: 1.6rem; font-weight: 700; margin-bottom: 1rem; }
h2 { font-size: 1.1rem; font-weight: 600; margin-bottom: 0.6rem; }

.camera-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 1rem;
}

.camera-card {
  background: var(--surface);
  border-radius: var(--radius);
  overflow: hidden;
  border: 1px solid var(--border);
  box-shadow: var(--shadow);
  transition: border-color 0.2s;
  cursor: pointer;

  &:hover { border-color: var(--primary); }

  .camera-thumb {
    width: 100%;
    aspect-ratio: 16/9;
    background: #000;
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;

    img { width: 100%; height: 100%; object-fit: cover; }

    .live-badge {
      position: absolute;
      top: 0.5rem;
      left: 0.5rem;
      background: var(--live);
      color: #fff;
      font-size: 0.65rem;
      font-weight: 700;
      letter-spacing: 0.05em;
      padding: 0.15rem 0.5rem;
      border-radius: 4px;
    }

    .viewer-count {
      position: absolute;
      bottom: 0.5rem;
      right: 0.5rem;
      background: rgba(0,0,0,0.75);
      color: #fff;
      font-size: 0.75rem;
      padding: 0.15rem 0.5rem;
      border-radius: 4px;
    }
  }

  .camera-info {
    padding: 0.75rem 1rem;
    .name { font-weight: 600; font-size: 0.9rem; }
    .meta { color: var(--text-dim); font-size: 0.8rem; margin-top: 0.25rem; }
  }
}

.video-player-wrapper {
  background: #000;
  border-radius: var(--radius);
  overflow: hidden;
  aspect-ratio: 16/9;
  width: 100%;
  max-width: 900px;
  margin: 0 auto 1.5rem;
  border: 1px solid var(--border);

  video { width: 100%; height: 100%; }
}

.chat-panel {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  display: flex;
  flex-direction: column;
  height: 400px;

  .chat-messages {
    flex: 1;
    overflow-y: auto;
    padding: 0.75rem;
    scrollbar-width: thin;
    scrollbar-color: var(--border) transparent;

    .message {
      margin-bottom: 0.5rem;
      font-size: 0.85rem;
      .username { color: var(--accent); font-weight: 600; margin-right: 0.4rem; }
    }
  }

  .chat-input {
    border-top: 1px solid var(--border);
    display: flex;
    padding: 0.5rem;
    gap: 0.5rem;

    input {
      flex: 1;
      background: var(--surface-alt);
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 0.4rem 0.75rem;
      color: var(--text);
      font-size: 0.85rem;
      outline: none;
      &:focus { border-color: var(--primary); }
    }

    button {
      background: var(--primary);
      color: #fff;
      border: none;
      border-radius: 6px;
      padding: 0.4rem 0.9rem;
      font-size: 0.85rem;
      cursor: pointer;
      &:hover { background: var(--primary-dark); }
    }
  }
}

.btn {
  display: inline-block;
  padding: 0.55rem 1.25rem;
  border-radius: 6px;
  font-size: 0.875rem;
  cursor: pointer;
  border: none;
  transition: all 0.15s;
  font-weight: 500;

  &-primary {
    background: var(--primary);
    color: #fff;
    &:hover { background: var(--primary-dark); color: #fff; }
  }

  &-ghost {
    background: transparent;
    border: 1px solid var(--border);
    color: var(--text-dim);
    &:hover { border-color: var(--text-dim); color: var(--text); }
  }
}

.form-group {
  margin-bottom: 1rem;
  label { display: block; font-size: 0.85rem; color: var(--text-dim); margin-bottom: 0.3rem; }
  input, select, textarea {
    width: 100%;
    padding: 0.55rem 0.85rem;
    border: 1px solid var(--border);
    border-radius: 6px;
    background: var(--surface-alt);
    color: var(--text);
    font-size: 0.9rem;
    outline: none;
    &:focus { border-color: var(--primary); }
  }
}

.flash-notice { background: #052e16; color: #4ade80; border: 1px solid #166534; border-radius: 6px; padding: 0.65rem 1rem; margin-bottom: 1rem; }
.flash-alert  { background: #1f0a0d; color: #fb7185; border: 1px solid #9f1239; border-radius: 6px; padding: 0.65rem 1rem; margin-bottom: 1rem; }

@media (max-width: 640px) {
  .camera-grid { grid-template-columns: 1fr; }
  main { padding: 1rem 0.75rem; }
}
SCSS

echo "==> privcam styles written"
