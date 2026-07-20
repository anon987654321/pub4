#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/master_web_assets_gate"

Deploy::MasterWebAssetsGate.run.report!(
  "MASTER/web assets gate passed (#{Deploy::MasterWebAssetsGate::REQUIRED.size} required assets present)."
)
