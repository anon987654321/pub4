#!/bin/sh
# Sweep amber Solid Queue backlog on vm23. Run as dev after git pull.
set -e
APP=amber
DIR=/home/${APP}/app
export HOME=/home/${APP}

run_amber() {
  doas su -m "${APP}" -c "export HOME=/home/${APP}; [ -r /etc/${APP}.env ] && . /etc/${APP}.env; cd ${DIR} && bundle34 exec rails $* RAILS_ENV=production"
}

echo "==> amber queue report"
run_amber amber:queue:report

echo "==> amber queue sweep"
run_amber amber:queue:sweep

echo "==> amber queue report (after)"
run_amber amber:queue:report