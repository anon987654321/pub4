#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require_relative "../OPENBSD/lib/utf8"
require_relative "gates/lib/frontend_production_gate_logic"

apps = YAML.safe_load(File.read(Deploy::FrontendProductionGate::APPS_YML)).fetch("apps")
Deploy::FrontendProductionGate.run.report!(
  "Frontend production gate passed (#{apps.size} apps + MASTER/web layouts)."
)
