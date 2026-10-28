# frozen_string_literal: true

require "json"
require_relative "../../lib/visual/ad_audit"

manifest_path = ARGV.fetch(0) do
  abort "usage: ruby tools/visual/audit_ad.rb MANIFEST.json"
end
abort "ad_visual_audit: manifest not found: #{manifest_path}" unless File.file?(manifest_path)

manifest = JSON.parse(File.read(manifest_path, encoding: "UTF-8"))
%w[html css placement].each do |key|
  abort "ad_visual_audit: manifest is missing #{key.inspect}" unless manifest.key?(key)
end

report = Master::Visual::AdAudit.audit(
  html: manifest.fetch("html"),
  css: manifest.fetch("css"),
  placement: manifest.fetch("placement"),
  rendered: manifest["rendered"]
)
puts JSON.pretty_generate(report)
exit(report.fetch(:passed) ? 0 : 1)
