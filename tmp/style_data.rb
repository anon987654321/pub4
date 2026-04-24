# frozen_string_literal: true

# Add consistent headers to data/*.yml files that lack them

base = "/home/dev/pub4/MASTER/data"

headers = {
  "constitution.yml"     => "# Constitution — protection levels and golden rules for MASTER's pipeline.",
  "council.yml"          => "# Council personas — deliberation panel for code review decisions.",
  "language_rules.yml"   => "# Language rules — per-language coding standards enforced by scan rules.",
  "principles.yml"       => "# Principles — KISS, DRY, YAGNI, SoC, SRP, SOLID and beyond.",
  "standing_orders.yml"  => "# Standing orders — persistent scheduled commands (initially empty).",
  "strunk.yml"           => "# Strunk — prose pruning rules for the Prune stage (preambles, hedges, endings).",
  "platform.yml"         => "# Platform — OS-specific tool mappings (audio, firewall, etc.).",
  "exemplars.yml"        => "# Exemplars — canonical code examples for LLM context injection.",
  "quality_thresholds.yml" => "# Quality thresholds — file size and complexity limits for scan rules.",
  "templates.yml"        => "# Templates — canonical starting points for code generation tasks."
}

headers.each do |file, header|
  path = File.join(base, file)
  next unless File.exist?(path)

  src = File.read(path, encoding: "UTF-8")
  next if src.start_with?("#")

  File.write(path, "#{header}\n\n#{src}")
  puts "headed: #{file}"
end
