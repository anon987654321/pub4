# frozen_string_literal: true

# Run the spectral audit over every rendered track and print a table.
#   ruby lib/spectral_audit_run.rb [out_dir]
require "json"
require_relative "spectral_audit"

root = File.expand_path("..", __dir__)
out_dir = ARGV[0] || File.join(root, "renders", "spectro")
tracks = (Dir[File.join(root, "renders", "library", "*", "*.mp3")] +
          Dir[File.join(root, "demo*.mp3")]).sort

abort "no tracks found under #{root}" if tracks.empty?

rows = tracks.map do |path|
  row = SpectralAudit.analyse(path, out_dir)
  row["findings"] = SpectralAudit.findings(row)
  warn format("%-46s centroid %6s  air %6s  crest %5s  %s",
              row["track"][0, 46], row["centroid_hz"], row["bands_db"]["air"],
              row["crest_factor"], row["findings"].empty? ? "ok" : row["findings"].size.to_s + " finding(s)")
  row
end

File.write(File.join(out_dir, "spectral_audit.json"), JSON.pretty_generate(rows))

puts "\n=== #{rows.size} track(s) ==="
flagged = rows.reject { |r| r["findings"].empty? }
puts "clean: #{rows.size - flagged.size}   flagged: #{flagged.size}"
flagged.each do |r|
  puts "\n#{r['track']}"
  r["findings"].each { |f| puts "  - #{f}" }
end

# Outliers matter more than absolutes here: these are all meant to be one
# catalogue, so a track sitting far from its siblings is the signal.
centroids = rows.filter_map { |r| r["centroid_hz"] }
if centroids.size > 2
  mean = centroids.sum / centroids.size
  sd = Math.sqrt(centroids.sum { |c| (c - mean)**2 } / centroids.size)
  puts "\n=== centroid spread: mean #{mean.round} Hz, sd #{sd.round} Hz ==="
  rows.each do |r|
    c = r["centroid_hz"]
    next unless c && sd.positive? && ((c - mean).abs / sd) > 1.8

    puts format("  %-46s %6.0f Hz (%+.1f sd)", r["track"][0, 46], c, (c - mean) / sd)
  end
end
puts "\nspectrograms + spectral_audit.json in #{out_dir}"
