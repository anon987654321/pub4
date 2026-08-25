#!/usr/bin/env ruby
# frozen_string_literal: true

# OPERATOR.sh legitimately contains UTF-8 bytes (em dashes in comments); the
# plain string #include? checks below tolerated that under the remote's
# US-ASCII default external encoding, but the =~ regex checks do not.
script = File.read(File.expand_path("OPERATOR.sh", __dir__), encoding: "UTF-8")

issues = []

backup_idx = script.index("backup_directory /var/nsd/zones/master nsd-zones")
delete_idx = script.index("rm -rf /var/nsd/etc/*(/) /var/nsd/zones/master/*(/)") # scan: intentional — searches for the command, never runs it
issues << "nsd backup does not precede destructive delete" unless backup_idx && delete_idx && backup_idx < delete_idx

# Regexes, not exact strings: the actual variable names in OPERATOR.sh ($src/$d,
# $svc) drift over time, but the two guarantees these check for - a backup copy
# into a quoted destination, and a restart-with-start-fallback - must survive.
issues << "missing guarded /home backup copy path" unless script =~ %r{cp -R "\$\{?src\}?[^"]*"[^\n]*?"[^"]*"}
issues << "missing idempotent Rails DB create/migrate guard" unless script.include?("db:create db:migrate")
issues << "missing restart/start fallback for rc.d services" unless script =~ %r{rcctl restart \$\{?\w+\}?[^\n]*?\|\|[^\n]*?rcctl start \$\{?\w+\}?}

if issues.any?
  warn "idempotency check failed:"
  issues.each { |issue| warn " - #{issue}" }
  exit 1
end

puts "OPERATOR.sh idempotency ok"
