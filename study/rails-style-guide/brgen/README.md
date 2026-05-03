# Abort on syntax errors; exit 1 signals the caller (e.g. CI) that the config is invalid
relayd -n -f /etc/relayd.conf || exit 1
