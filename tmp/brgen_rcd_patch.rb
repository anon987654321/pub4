# frozen_string_literal: true
# Fix /etc/rc.d/brgen: correct bind address + pexp to match actual ruby34 process name

content = <<~'SH'
  #!/bin/ksh
  daemon="/usr/local/bin/bundle"
  daemon_flags="exec env RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 falcon serve --bind http://127.0.0.1:11006"
  daemon_user="brgen"
  daemon_execdir="/home/brgen/app"
  daemon_timeout="60"
  . /etc/rc.d/rc.subr
  pexp="ruby.*11006"
  rc_bg=YES
  rc_reload=NO
  rc_cmd $1
SH

File.write("/etc/rc.d/brgen", content)
puts "written"
