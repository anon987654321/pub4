#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../OPENBSD/lib/utf8"
require_relative "gates/lib/port_inventory_gate"

apps = Deploy::Inventory.new(root: Deploy::PortInventoryGate::ROOT).apps
Deploy::PortInventoryGate.run.report!(
  "Port inventory gate passed for #{apps.size} Rails apps."
)
