#!/usr/bin/env ruby
# frozen_string_literal: true
# frozen_string_literal: true
# frozen_string_literal: true

# Regenerate data/CANON.md index from live rules.yml + scanner registry.
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "master"

root = Master::ROOT
audit = Master::Review::Scan::RuleRegistryAudit.new(root:).call
data = Master.load_rules(root:)
laws = data.fetch("laws", {}).keys.sort
kernel = (data["rules"] || {}).values.flatten.select { |r| r["tier"] == "kernel" }.map { |r| r["id"] }.sort

body = <<~MD
  # MASTER Rule Canon (generated)

  Generated: #{Time.now.utc.iso8601}

  ## Summary

  - YAML rule ids: #{audit.yaml_rules}
  - Ruby scanner rules: #{audit.registry_ids.size}
  - Adherence: #{audit.adherence_pct}%
  - Semantic-only: #{audit.semantic_only.size}
  - Lexical unwired: #{audit.lexical_unwired.size}

  ## Universal Laws

  #{laws.map { |law| "- #{law}" }.join("\n")}

  ## Kernel Tier (#{kernel.size})

  #{kernel.map { |id| "- #{id}" }.join("\n")}

  ## Registry

  Run `/rules list` for the live scanner registry.
  Run `/rules status` for wiring audit.
MD

path = File.join(root, "data", "CANON.md")
File.write(path, body)
puts "canon: wrote #{path}"
