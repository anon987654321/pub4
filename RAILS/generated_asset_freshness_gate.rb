#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/generated_asset_gate"

inventory = Deploy::Inventory.new(root: Deploy::GeneratedAssetGate::ROOT)
Deploy::GeneratedAssetGate.run.report!(
  "Generated asset freshness gate passed for #{inventory.apps.size} Rails apps."
)
