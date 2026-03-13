#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Baibl — scripture and contemplation (TCPServer, port 10007)

typeset -r APP_NAME="baibl"
typeset -r APP_PORT=10007
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
    <title>baibl</title>
    <style>
      :root {
        --bg: #0f0e0b; --surface: #1a1812; --surface-alt: #221f16;
        --primary: #c9a96e; --primary-light: #e2c98c; --primary-dark: #a07c40;
        --text: #f0ead6; --text-dim: #8a7f68; --border: #2e2a1e;
        --gold-line: rgba(201,169,110,.25); --radius: 10px;
      }
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body { font-family: 'Palatino Linotype', Palatino, Georgia, serif; background: var(--bg); color: var(--text); line-height: 1.85; }
      header { background: var(--surface); border-bottom: 1px solid var(--gold-line); padding: 1.25rem 2rem; display: flex; align-items: center; justify-content: space-between; }
      .logo { font-size: 1.5rem; font-weight: 600; color: var(--primary); letter-spacing: .04em; font-variant: small-caps; }
      nav a { margin-left: 1.5rem; color: var(--text-dim); font-size: .9rem; text-decoration: none; }
      nav a:hover { color: var(--primary); }
      main { max-width: 820px; margin: 0 auto; padding: 3rem 1.5rem; }
      h1 { font-size: 1.85rem; color: var(--primary-light); margin-bottom: 1rem; font-weight: 400; font-variant: small-caps; }
      .verse-block { background: var(--surface); border: 1px solid var(--gold-line); border-left: 3px solid var(--primary); border-radius: var(--radius); padding: 1.75rem 2rem; margin-bottom: 1.75rem; }
      .verse-reference { font-size: .78rem; color: var(--primary); letter-spacing: .08em; text-transform: uppercase; margin-bottom: .75rem; font-family: system-ui, sans-serif; }
      .verse-text { font-size: 1.1rem; line-height: 1.95; font-style: italic; }
      .ornament { text-align: center; color: var(--primary-dark); font-size: 1.2rem; letter-spacing: .5em; margin: 2rem 0; opacity: .6; }
      .cta { display: inline-block; padding: .6rem 1.4rem; background: var(--primary); color: var(--bg); border-radius: 8px; font-size: .9rem; text-decoration: none; font-weight: 600; margin-top: 1.5rem; }
    </style>
  </head>
  <body>
    <header>
      <span class="logo">baibl</span>
      <nav><a href="/scripture">skriften</a><a href="/devotional">andakt</a><a href="/login">logg inn</a></nav>
    </header>
    <main>
      <h1>søk i skriften</h1>
      <div class="verse-block">
        <div class="verse-reference">Johannes 3:16</div>
        <div class="verse-text">For så har Gud elsket verden at han ga sin Sønn, den enbårne, for at den som tror på ham, ikke skal gå fortapt, men ha evig liv.</div>
      </div>
      <div class="ornament">✦ ✦ ✦</div>
      <a class="cta" href="/signup">kom i gang</a>
    </main>
  </body>
  </html>
HTML

RESP = "HTTP/1.0 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: #{HTML.bytesize}\r\nConnection: close\r\n\r\n#{HTML}"
trap("TERM") { exit }
trap("INT")  { exit }
TCPServer.new("0.0.0.0", 10007).tap do |s|
  $stdout.puts "baibl on 10007"; $stdout.flush
  loop { c = s.accept; c.recv(4096) rescue nil; c.print(RESP) rescue nil; c.close rescue nil }
end
FALCONEOF

chown -R ${APP_NAME}:${APP_NAME} "${APP_DIR}"

cat > "/etc/rc.d/${APP_NAME}" << 'RCDEOF'
#!/bin/ksh
daemon="/usr/local/bin/ruby34"
daemon_flags="/home/baibl/app/config/falcon.rb"
daemon_user="baibl"
daemon_timeout=30
. /etc/rc.d/rc.subr
pexp="ruby34 /home/baibl/app/config/falcon.rb"
rc_bg=YES
rc_reload=NO
rc_cmd $1
RCDEOF

chmod 755 "/etc/rc.d/${APP_NAME}"
rcctl enable ${APP_NAME}
rcctl restart ${APP_NAME} || rcctl start ${APP_NAME}
echo "==> [${APP_NAME}] done"
