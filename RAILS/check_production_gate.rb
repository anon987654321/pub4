#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require_relative "../OPENBSD/lib/utf8"
require_relative "gates/lib/production_gate"

apps = YAML.safe_load(File.read(Deploy::ProductionGate::APPS_YML)).fetch("apps")
skip_nested = ENV["GATE_SKIP_NESTED"] == "1"
result = Deploy::ProductionGate.run(skip_nested: skip_nested)

result.report!("Production gate passed for #{apps.size} Rails apps.")
