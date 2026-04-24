# frozen_string_literal: true
# encoding: utf-8

BASE = "/home/dev/pub4/MASTER"
agent_rb = File.read("#{BASE}/lib/master/agent.rb", encoding: "utf-8")

# Find the TOOL_CAPABLE_RE block by line markers
lines = agent_rb.lines
start_idx = lines.index { |l| l.include?("TOOL_CAPABLE_RE = %r{") }

if start_idx.nil?
  puts "agent.rb: TOOL_CAPABLE_RE already changed"
  exit 0
end

# Find the comment line above it
comment_start = start_idx
while comment_start > 0 && lines[comment_start - 1].strip.start_with?("#")
  comment_start -= 1
end

# Find the closing line (}.freeze)
end_idx = lines[start_idx..].index { |l| l.strip =~ /\}ix\.freeze/ }
end_idx = start_idx + end_idx if end_idx

replacement = <<~'NEW'
    # Tool-capable model whitelist -- loaded from data/models.yml.
    # Anchored regex built from tool_capable_prefixes list.
    def self.build_tool_capable_re
      yml_path = File.join(Master::ROOT, "data", "models.yml")
      prefixes = YAML.safe_load_file(yml_path).fetch("tool_capable_prefixes", [])
      escaped = prefixes.map { |p| Regexp.escape(p) }
      Regexp.new("\\A(?:#{escaped.join("|")})(?:[:\\/@\\-.].+)?\\z", Regexp::IGNORECASE).freeze
    end

    TOOL_CAPABLE_RE = build_tool_capable_re
NEW

new_lines = lines[0...comment_start] + replacement.lines + lines[(end_idx + 1)..]

# Add require yaml if needed
unless new_lines.any? { |l| l.include?('require "yaml"') }
  idx = new_lines.index { |l| l.include?('require "digest"') }
  new_lines.insert(idx + 1, "require \"yaml\"\n") if idx
end

File.write("#{BASE}/lib/master/agent.rb", new_lines.join)
puts "agent.rb: TOOL_CAPABLE_RE now loads from data/models.yml"
