#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Hjerterom — mental health journaling (TCPServer, port 10004)

typeset -r APP_NAME="hjerterom"
typeset -r APP_PORT=10004
typeset -r APP_DIR="/home/${APP_NAME}/app"

echo "==> [${APP_NAME}] writing falcon.rb on :${APP_PORT}"

mkdir -p "${APP_DIR}/config"

cat > "${APP_DIR}/config/falcon.rb" << 'FALCONEOF'
#!/usr/bin/env ruby
# frozen_string_literal: true
require "socket"

HTML = <<~HTML
  <!DOCTYPE html>
  <html lang="no">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>hjerterom</title>
    <style>
      :root {
        --bg: #fdf8f2; --surface: #fffdf9; --surface-alt: #f5ede0;
        --primary: #c17f4a; --primary-dark: #8b5e34; --warm: #e8c4a0;
        --text: #2c1f0f; --text-dim: #7a6454; --border: #e6d5c3; --radius: 14px;
      }
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body { font-family: Georgia, Palatino, serif; background: var(--bg); color: var(--text); line-height: 1.8; }
      header { background: var(--surface); border-bottom: 1px solid var(--border); padding: 1.25rem 2rem; display: flex; align-items: center; justify-content: space-between; }
      .logo { font-size: 1.5rem; font-weight: 600; color: var(--primary-dark); }
      nav a { margin-left: 1.5rem; color: var(--text-dim); font-size: .9rem; text-decoration: none; }
      nav a:hover { color: var(--primary); }
      main { max-width: 760px; margin: 0 auto; padding: 3rem 1.5rem; }
      h1 { font-size: 1.9rem; color: var(--primary-dark); margin-bottom: 1rem; }
      .intro { color: var(--text-dim); font-size: 1.05rem; margin-bottom: 2rem; font-style: italic; }
      .prompt-card { background: linear-gradient(135deg, var(--surface-alt), var(--warm)); border-radius: var(--radius); padding: 1.5rem 1.75rem; margin-bottom: 1.5rem; border: 1px solid var(--border); }
      .prompt-label { font-size: .75rem; text-transform: uppercase; letter-spacing: .08em; color: var(--primary); font-family: system-ui, sans-serif; margin-bottom: .5rem; }
      .prompt-card p { font-size: 1.05rem; font-style: italic; }
      .cta { display: inline-block; padding: .65rem 1.5rem; background: var(--primary); color: #fff; border-radius: 999px; font-size: .9rem; text-decoration: none; font-family: system-ui, sans-serif; margin-top: 1.5rem; }
    </style>
  </head>
  <body>
    <header>
      <span class="logo">hjerterom</span>
      <nav><a href="/journal">dagbok</a><a href="/prompts">refleksjon</a><a href="/login">logg inn</a></nav>
    </header>
    <main>
      <h1>et rom for tankene dine</h1>
      <p class="intro">Mental helse journaling — trygt, privat og uten dømmekraft.</p>
      <div class="prompt-card">
        <div class="prompt-label">dagens refleksjon</div>
        <p>Hva er tre ting du er takknemlig for i dag?</p>
      </div>
      <a class="cta" href="/signup">start din dagbok</a>
    </main>
  </body>
  </html>
HTML

RESP = "HTTP/1.0 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: #{HTML.bytesize}\r\nConnection: close\r\n\r\n#{HTML}"
trap("TERM") { exit }
trap("INT")  { exit }
TCPServer.new("0.0.0.0", 10004).tap do |s|
  $stdout.puts "hjerterom on 10004"; $stdout.flush
  loop { c = s.accept; c.recv(4096) rescue nil; c.print(RESP) rescue nil; c.close rescue nil }
end
FALCONEOF

chown -R ${APP_NAME}:${APP_NAME} "${APP_DIR}"

cat > "/etc/rc.d/${APP_NAME}" << 'RCDEOF'
#!/bin/ksh
daemon="/usr/local/bin/ruby34"
daemon_flags="/home/hjerterom/app/config/falcon.rb"
daemon_user="hjerterom"
daemon_timeout=30
. /etc/rc.d/rc.subr
pexp="ruby34 /home/hjerterom/app/config/falcon.rb"
rc_bg=YES
rc_reload=NO
rc_cmd $1
RCDEOF

chmod 755 "/etc/rc.d/${APP_NAME}"
rcctl enable ${APP_NAME}
rcctl restart ${APP_NAME} || rcctl start ${APP_NAME}
echo "==> [${APP_NAME}] done"
