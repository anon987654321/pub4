# frozen_string_literal: true

require "json"
require_relative "../../lib/visual/ad_audit"
require_relative "browserless_measurements"

manifest_path = ARGV.fetch(0) { ENV["AD_VISUAL_MANIFEST"] }
abort "usage: ruby tools/visual/audit_ad.rb MANIFEST.json" if manifest_path.to_s.empty?
manifest_path = File.expand_path(manifest_path)
abort "ad_visual_audit: manifest not found: #{manifest_path}" unless File.file?(manifest_path)

manifest = JSON.parse(File.read(manifest_path, encoding: "UTF-8"))
if manifest["rendered"]
  abort "ad_visual_audit: rendered evidence must be a JSON object" unless manifest["rendered"].is_a?(Hash)
  abort "ad_visual_audit: browserless evidence must be generated from source, not supplied" if manifest.dig("rendered", "measurement_mode") == "browserless_static"
end
%w[html css placement].each do |key|
  abort "ad_visual_audit: manifest is missing #{key.inspect}" unless manifest.key?(key)
end

measurement = nil
rendered = manifest["rendered"]
unless rendered
  asset_root = manifest["asset_root"].to_s
  asset_root = File.dirname(manifest_path) if asset_root.empty?
  asset_root = File.expand_path(asset_root, File.dirname(manifest_path))
  measurement = Master::Visual::BrowserlessMeasurements.measure(
    html: manifest.fetch("html"),
    css: manifest.fetch("css"),
    placement: manifest.fetch("placement"),
    token_contract: Master::Visual::AdAudit.contract,
    asset_root:,
    viewport: manifest["viewport"],
  )
  rendered = measurement.fetch(:rendered)
end

report = Master::Visual::AdAudit.audit(
  html: manifest.fetch("html"),
  css: manifest.fetch("css"),
  placement: manifest.fetch("placement"),
  rendered:,
)
report[:measurements] = measurement.fetch(:measurements) if measurement
report[:measurement_mode] = rendered["measurement_mode"] || rendered[:measurement_mode] ||
                            (manifest["rendered"] ? "supplied_render_evidence" : "browserless_static")
puts JSON.pretty_generate(report)
exit(report.fetch(:passed) ? 0 : 1)
