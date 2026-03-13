#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

typeset -r APP_DIR="/home/brgen/app"
echo "==> [styles] Dark Reddit theme CSS"
cd "$APP_DIR"

cat > app/assets/stylesheets/application.css << 'CSS'
/* BRGEN — Minimalist Dark Theme */

:root {
  --bg:         #0a0a0a;
  --surface:    #1a1a1a;
  --surface2:   #222;
  --text:       #e8eaed;
  --text-dim:   #9aa0a6;
  --primary:    #8ab4f8;
  --upvote:     #ff4500;
  --downvote:   #7193ff;
  --border:     #333;
  --radius:     6px;
  --sp:         8px;
}

* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  font-family: system-ui, -apple-system, sans-serif;
  background: var(--bg);
  color: var(--text);
  line-height: 1.6;
  font-size: 14px;
}

a { color: var(--primary); text-decoration: none; }
a:hover { text-decoration: underline; }

/* ── Nav ── */
nav {
  background: var(--surface);
  border-bottom: 1px solid var(--border);
  padding: calc(var(--sp) * 1.5) calc(var(--sp) * 3);
  display: flex;
  align-items: center;
  justify-content: space-between;
  position: sticky;
  top: 0;
  z-index: 100;
}

.logo {
  font-size: 1.3rem;
  font-weight: 700;
  color: var(--text);
  letter-spacing: -0.03em;
}

.nav-links a {
  color: var(--text-dim);
  margin-left: calc(var(--sp) * 2);
  font-size: 0.875rem;
}
.nav-links a:hover { color: var(--text); text-decoration: none; }

/* ── Layout ── */
.page {
  max-width: 1200px;
  margin: 0 auto;
  padding: calc(var(--sp) * 2);
  display: grid;
  grid-template-columns: 1fr 300px;
  gap: calc(var(--sp) * 2);
}

.main-col { min-width: 0; }
.side-col  {}

@media (max-width: 768px) {
  .page { grid-template-columns: 1fr; }
  .side-col { display: none; }
  nav { padding: var(--sp) calc(var(--sp) * 2); }
}

/* ── Post card ── */
.post-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  margin-bottom: calc(var(--sp) * 1.5);
  display: flex;
  transition: border-color 0.15s;
}
.post-card:hover { border-color: #555; }

.vote-col {
  width: 40px;
  min-width: 40px;
  background: var(--surface2);
  border-radius: var(--radius) 0 0 var(--radius);
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: calc(var(--sp) * 1.5) 0;
  gap: 4px;
}

.vote-btn {
  background: none;
  border: none;
  color: var(--text-dim);
  cursor: pointer;
  font-size: 1.1rem;
  line-height: 1;
  padding: 2px 4px;
  border-radius: 3px;
  transition: color 0.1s;
}
.vote-btn:hover { color: var(--upvote); }
.vote-btn.down:hover { color: var(--downvote); }
.vote-btn.active-up   { color: var(--upvote); }
.vote-btn.active-down { color: var(--downvote); }

.vote-score {
  font-size: 0.75rem;
  font-weight: 700;
  color: var(--text-dim);
}

.post-body {
  flex: 1;
  padding: calc(var(--sp) * 1.5);
  min-width: 0;
}

.post-meta {
  font-size: 0.75rem;
  color: var(--text-dim);
  margin-bottom: calc(var(--sp) * 0.75);
}
.post-meta a { color: var(--text-dim); }
.post-meta .community { color: var(--primary); font-weight: 600; }

.post-title {
  font-size: 1.05rem;
  font-weight: 500;
  color: var(--text);
  line-height: 1.4;
  margin-bottom: calc(var(--sp) * 0.75);
}
.post-title a { color: var(--text); }
.post-title a:hover { color: var(--primary); text-decoration: none; }

.post-actions {
  display: flex;
  gap: calc(var(--sp) * 1.5);
  font-size: 0.75rem;
  color: var(--text-dim);
}
.post-actions a {
  color: var(--text-dim);
  font-weight: 600;
}
.post-actions a:hover { color: var(--text); text-decoration: none; }

/* ── Post show ── */
.post-show {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: calc(var(--sp) * 2);
  margin-bottom: calc(var(--sp) * 2);
}

.post-content {
  color: var(--text);
  line-height: 1.7;
  margin: calc(var(--sp) * 1.5) 0;
  white-space: pre-wrap;
}

/* ── Comments ── */
.comments-section { margin-top: calc(var(--sp) * 2); }

.comment-form-wrap {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: calc(var(--sp) * 1.5);
  margin-bottom: calc(var(--sp) * 1.5);
}

.comment {
  margin-bottom: var(--sp);
  padding: calc(var(--sp) * 1.25) calc(var(--sp) * 1.5);
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  border-left: 2px solid var(--border);
}
.comment .comment { background: var(--surface2); margin-top: var(--sp); border-left-color: #444; }

.comment-meta {
  font-size: 0.75rem;
  color: var(--text-dim);
  margin-bottom: calc(var(--sp) * 0.5);
}
.comment-meta .author { color: var(--text); font-weight: 600; }

.comment-body { line-height: 1.6; }

/* ── Forms ── */
.form-wrap {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: calc(var(--sp) * 2.5);
  max-width: 600px;
}

.field { margin-bottom: calc(var(--sp) * 1.5); }

label {
  display: block;
  font-size: 0.8rem;
  color: var(--text-dim);
  margin-bottom: calc(var(--sp) * 0.5);
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

input[type=text], input[type=email], input[type=password], textarea, select {
  width: 100%;
  padding: calc(var(--sp) * 1.25) calc(var(--sp) * 1.5);
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  color: var(--text);
  font-size: 0.9rem;
  font-family: inherit;
  outline: none;
  transition: border-color 0.15s;
}
input:focus, textarea:focus, select:focus { border-color: var(--primary); }
textarea { min-height: 120px; resize: vertical; line-height: 1.6; }

.btn {
  display: inline-block;
  padding: calc(var(--sp) * 1) calc(var(--sp) * 2);
  background: var(--primary);
  color: #0a0a0a;
  border: none;
  border-radius: var(--radius);
  font-size: 0.875rem;
  font-weight: 700;
  cursor: pointer;
  transition: opacity 0.15s;
}
.btn:hover { opacity: 0.88; text-decoration: none; color: #0a0a0a; }
.btn-ghost {
  background: transparent;
  border: 1px solid var(--border);
  color: var(--text-dim);
}
.btn-ghost:hover { border-color: var(--text-dim); color: var(--text); }

/* ── Sidebar ── */
.sidebar-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: calc(var(--sp) * 2);
  margin-bottom: calc(var(--sp) * 1.5);
}
.sidebar-card h3 {
  font-size: 0.75rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--text-dim);
  margin-bottom: var(--sp);
}
.sidebar-card ul { list-style: none; }
.sidebar-card li { padding: calc(var(--sp) * 0.5) 0; border-bottom: 1px solid var(--border); }
.sidebar-card li:last-child { border-bottom: none; }

/* ── Page header ── */
.page-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: calc(var(--sp) * 2);
}
.page-header h1 { font-size: 1.3rem; font-weight: 600; }

/* ── Sort tabs ── */
.sort-tabs {
  display: flex;
  gap: 4px;
  margin-bottom: calc(var(--sp) * 1.5);
}
.sort-tab {
  padding: calc(var(--sp) * 0.75) calc(var(--sp) * 1.5);
  border-radius: 99px;
  font-size: 0.8rem;
  font-weight: 700;
  color: var(--text-dim);
  background: var(--surface);
  border: 1px solid var(--border);
}
.sort-tab:hover, .sort-tab.active { background: var(--surface2); color: var(--text); text-decoration: none; }

/* ── Flashes ── */
.flash-notice {
  background: #0a2a1a;
  color: #6ee7a0;
  border: 1px solid #1a5a3a;
  border-radius: var(--radius);
  padding: var(--sp) calc(var(--sp) * 2);
  margin-bottom: calc(var(--sp) * 1.5);
  grid-column: 1 / -1;
}
.flash-alert {
  background: #2a0a0a;
  color: #f87171;
  border: 1px solid #5a1a1a;
  border-radius: var(--radius);
  padding: var(--sp) calc(var(--sp) * 2);
  margin-bottom: calc(var(--sp) * 1.5);
  grid-column: 1 / -1;
}

/* ── Empty state ── */
.empty { color: var(--text-dim); padding: calc(var(--sp) * 4) 0; text-align: center; }
CSS

echo "==> [styles] done"
