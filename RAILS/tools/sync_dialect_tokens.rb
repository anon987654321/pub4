#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "design_tokens"

changes = []
changes << "design_tokens: generated from MASTER/data/laws.yml#tokens" if DesignTokens.sync_design_artifact!
changes << "dialect tokens: generated vertical accent block" if DesignTokens.sync_vertical_accents!
changes.concat(DesignTokens.sync_dialect_tokens!)
puts(changes.empty? ? "dialect tokens already in sync with MASTER/data/laws.yml#tokens" : changes.join("\n"))
