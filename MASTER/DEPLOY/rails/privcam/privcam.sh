#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Privcam — private webcam streaming (TCPServer, port 10005)

typeset -r APP_NAME="privcam"
typeset -r APP_PORT=10005
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
    <title>privcam</title>
    <style>
      :root {
        --bg: #0d0d0d; --surface: #1a1a1a; --surface-alt: #222;
        --primary: #e11d48; --primary-dark: #be123c; --accent: #fb7185; --live: #22c55e;
        --text: #f3f4f6; --text-dim: #6b7280; --border: #2d2d2d; --radius: 10px;
      }
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body { font-family: system-ui, sans-serif; background: var(--bg); color: var(--text); line-height: 1.5; }
      header { background: #000; border-bottom: 1px solid var(--border); padding: .85rem 1.5rem; display: flex; align-items: center; justify-content: space-between; position: sticky; top: 0; z-index: 100; }
      .logo { font-size: 1.3rem; font-weight: 800; color: var(--primary); letter-spacing: -.03em; }
      nav a { margin-left: 1.25rem; color: var(--text-dim); font-size: .85rem; text-decoration: none; }
      nav a:hover { color: var(--text); }
      main { max-width: 1280px; margin: 0 auto; padding: 1.5rem 1rem; }
      h1 { font-size: 1.6rem; font-weight: 700; margin-bottom: 1rem; }
      .camera-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 1rem; }
      .camera-card { background: var(--surface); border-radius: var(--radius); border: 1px solid var(--border); overflow: hidden; transition: border-color .2s; }
      .camera-card:hover { border-color: var(--primary); }
      .camera-thumb { width: 100%; aspect-ratio: 16/9; background: #000; display: flex; align-items: center; justify-content: center; position: relative; }
      .live-badge { position: absolute; top: .5rem; left: .5rem; background: var(--live); color: #fff; font-size: .65rem; font-weight: 700; padding: .15rem .5rem; border-radius: 4px; }
      .camera-info { padding: .75rem 1rem; }
      .camera-info .name { font-weight: 600; font-size: .9rem; }
      .camera-info .meta { color: var(--text-dim); font-size: .8rem; margin-top: .25rem; }
      .cta { display: inline-block; padding: .55rem 1.25rem; background: var(--primary); color: #fff; border-radius: 6px; font-size: .875rem; text-decoration: none; margin-top: 1.5rem; }
    </style>
  </head>
  <body>
    <header>
      <span class="logo">privcam</span>
      <nav><a href="/browse">browse</a><a href="/stream">go live</a><a href="/login">logg inn</a></nav>
    </header>
    <main>
      <h1>private streaming</h1>
      <div class="camera-grid">
        <div class="camera-card">
          <div class="camera-thumb"><span class="live-badge">LIVE</span></div>
          <div class="camera-info"><div class="name">Room 1</div><div class="meta">0 viewers</div></div>
        </div>
      </div>
      <a class="cta" href="/signup">start streaming</a>
    </main>
  </body>
  </html>
HTML

RESP = "HTTP/1.0 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: #{HTML.bytesize}\r\nConnection: close\r\n\r\n#{HTML}"
trap("TERM") { exit }
trap("INT")  { exit }
TCPServer.new("0.0.0.0", 10005).tap do |s|
  $stdout.puts "privcam on 10005"; $stdout.flush
  loop { c = s.accept; c.recv(4096) rescue nil; c.print(RESP) rescue nil; c.close rescue nil }
end
FALCONEOF

chown -R ${APP_NAME}:${APP_NAME} "${APP_DIR}"

cat > "/etc/rc.d/${APP_NAME}" << 'RCDEOF'
#!/bin/ksh
daemon="/usr/local/bin/ruby34"
daemon_flags="/home/privcam/app/config/falcon.rb"
daemon_user="privcam"
daemon_timeout=30
. /etc/rc.d/rc.subr
pexp="ruby34 /home/privcam/app/config/falcon.rb"
rc_bg=YES
rc_reload=NO
rc_cmd $1
RCDEOF

chmod 755 "/etc/rc.d/${APP_NAME}"
rcctl enable ${APP_NAME}
rcctl restart ${APP_NAME} || rcctl start ${APP_NAME}
echo "==> [${APP_NAME}] done"
