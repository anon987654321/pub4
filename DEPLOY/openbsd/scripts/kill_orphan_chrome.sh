#!/bin/sh
# CC04: daily cron — kill orphaned chrome/chromium from reach/web.rb tool use.

pkill -9 -f 'chrome|chromium' 2>/dev/null && echo "killed orphan browser processes" || echo "no orphan chrome"