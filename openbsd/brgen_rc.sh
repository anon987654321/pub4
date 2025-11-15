#!/bin/ksh

daemon=/usr/local/bin/bundle
daemon_flags="exec falcon serve -b 0.0.0.0 -p 11006 -c /home/brgen/app"
daemon_user=dev
rc_bg=YES
rc_reload=NO

. /etc/rc.d/rc.subr

pexp="falcon.*11006"

rc_cmd $1
