#!/bin/sh
# Sweep amber Solid Queue backlog on vm23. Run as dev after git pull.
set -e
APP=amber
DIR=/home/${APP}/app
export HOME=/home/${APP}

run_amber() {
  doas sh -c ". /etc/${APP}.env 2>/dev/null || . /etc/rails/${APP}.env; export HOME=/home/${APP}; cd ${DIR} && su -m ${APP} -c 'export HOME=/home/${APP} SECRET_KEY_BASE=${SECRET_KEY_BASE}; cd ${DIR} && bundle34 exec rails $* RAILS_ENV=production'"
}

echo "==> amber queue report"
run_amber amber:queue:report

echo "==> amber queue sweep"
run_amber amber:queue:sweep

echo "==> amber queue report (after)"
run_amber amber:queue:report