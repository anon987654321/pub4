#!/bin/sh
# Sweep amber Solid Queue backlog on vm23. Run as dev after git pull.
set -e
APP=amber
DIR=/home/${APP}/app
export HOME=/home/${APP}

echo "==> amber queue report"
su -m "${APP}" -c "cd ${DIR} && bundle exec rails amber:queue:report RAILS_ENV=production"

echo "==> amber queue sweep"
su -m "${APP}" -c "cd ${DIR} && bundle exec rails amber:queue:sweep RAILS_ENV=production"

echo "==> amber queue report (after)"
su -m "${APP}" -c "cd ${DIR} && bundle exec rails amber:queue:report RAILS_ENV=production"