# frozen_string_literal: true

# Rewrites the generated block of MASTER/gates/data/geometry_surfaces.yml from
# probed_<app>.jsonl: every HTML GET route that rendered for a guest, minus
# what is already declared by hand or by BrgenVerticalSurfaces.
require "json"
require "yaml"

dir, yaml_path = ARGV
BEGIN_MARK = "  # BEGIN generated view surfaces"
END_MARK = "  # END generated view surfaces"

text = File.read(yaml_path)
text = text.sub(/#{Regexp.escape(BEGIN_MARK)}.*?#{Regexp.escape(END_MARK)}\n/m, "")
config = YAML.safe_load(text)
require_relative File.expand_path("../support/brgen_vertical_surfaces", File.dirname(yaml_path))

declared = Array(config["surfaces"]).map { |s| [s["app"], s["host"].to_s.sub(/\Abrgen\.no\z/, ""), s["path"]] }
Deploy::BrgenVerticalSurfaces::SURFACES.each { |s| declared << ["brgen", s[:host].sub(/\Abrgen\.no\z/, ""), s[:path]] }
labels = Hash.new { |h, k| h[k] = Array(config["surfaces"]).select { |s| s["app"] == k }.map { |s| s["label"] } }
Deploy::BrgenVerticalSurfaces::SURFACES.each { |s| labels["brgen"] << s[:label] }

rows = %w[amber bsdports brgen].flat_map do |app|
  File.readlines(File.join(dir, "probed_#{app}.jsonl")).map { |l| JSON.parse(l) }
      .select { |r| r["kind"] == "page" }.map { |r| r.merge("app" => app) }
end

entries = rows.filter_map do |row|
  app = row["app"]
  host = app == "brgen" ? row["host"] : nil
  next if declared.include?([app, host.to_s.sub(/\Abrgen\.no\z/, ""), row["url"]])

  controller, action = row["action"].split("#")
  sub = host && host != "brgen.no" ? "#{host.split(".").first}_" : ""
  base = "#{sub}#{controller.tr("/", "_")}_#{action}".gsub(/[^a-z0-9_]/, "_")
  label = base
  label = "#{base}_#{labels[app].count { |l| l.start_with?(base) } + 1}" while labels[app].include?(label)
  labels[app] << label
  { "app" => app, "label" => label, "host" => host, "path" => row["url"] }.compact
end

block = [BEGIN_MARK,
         "  # Every HTML GET route that rendered for a guest on the local fleet, from",
         "  # RAILS/tools/view_surfaces/generate.rb. Hand-declared surfaces above win;",
         "  # routes behind sign-in and routes whose parameters no local record fills",
         "  # are not here (the probe browses as a guest). Regenerate, do not edit.",
         *entries.map { |e| "  - { app: #{e["app"]}, label: #{e["label"]}, #{e["host"] ? "host: #{e["host"]}, " : ""}path: #{e["path"].to_json}, viewports: [mobile, desktop] }" },
         END_MARK].join("\n") + "\n"

anchor = "\n# Content that changes between two captures"
abort "anchor missing" unless text.include?(anchor)
File.write(yaml_path, text.sub(anchor, "\n#{block}#{anchor}"))
puts "#{entries.size} generated surfaces (#{entries.group_by { |e| e["app"] }.transform_values(&:size).inspect})"
