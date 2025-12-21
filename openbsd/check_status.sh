#!/usr/bin/env zsh
# Check Rails app deployment status

print "=== Enabled Services ==="
doas rcctl ls on

print "\n=== Falcon Processes ==="
doas ps aux | grep -i falcon | grep -v grep

print "\n=== Port Listeners ==="
doas netstat -an | grep LISTEN | grep -E ':(3000|3001|3002|3003|3004|3005|3006|3007|443|80)'

print "\n=== Recent Logs (brgen) ==="
doas tail -20 /var/log/brgen.log 2>/dev/null || print "No brgen.log found"

print "\n=== Relayd Status ==="
doas rcctl check relayd

print "\n=== HTTPd Status ==="  
doas rcctl check httpd
