#!/usr/bin/env ruby
# frozen_string_literal: true

script = File.read(File.expand_path("OPERATOR.sh", __dir__))

issues = []

backup_idx = script.index("backup_directory /var/nsd/zones/master nsd-zones")
delete_idx = script.index("rm -rf /var/nsd/etc/*(/) /var/nsd/zones/master/*(/)")
issues << "nsd backup does not precede destructive delete" unless backup_idx && delete_idx && backup_idx < delete_idx

issues << "missing guarded /home backup copy path" unless script.include?("cp -R \"${src}/.\" \"${app_dir}/\"")
issues << "missing idempotent Rails DB create/migrate guard" unless script.include?("db:create db:migrate")
issues << "missing restart/start fallback for rc.d services" unless script.include?("rcctl restart $app || /usr/sbin/rcctl start $app")

if issues.any?
  warn "idempotency check failed:"
  issues.each { |issue| warn " - #{issue}" }
  exit 1
end

puts "OPERATOR.sh idempotency ok"
