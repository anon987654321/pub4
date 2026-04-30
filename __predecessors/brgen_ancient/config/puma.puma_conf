#!/usr/bin/env puma

# If you are in development mode, replace this file with `puma_dev.rb`

app = "brgen"
home = "/home/www/#{app}"

# Only one ImageMagick process at a time to avoid scraper overload

threads 0, 1

pidfile "#{home}/tmp/puma.pid"
state_path "#{home}/tmp/puma.state"
bind "unix://#{home}/tmp/puma.sock"

stdout_redirect "#{home}/log/puma/access.log", "#{home}/log/puma/errors.log"

# activate_control_app "unix://#{home}/tmp/pumactl.sock"

environment "production"
daemonize

