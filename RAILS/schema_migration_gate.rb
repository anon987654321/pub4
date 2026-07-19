#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/schema_migration_gate"

inventory = Deploy::Inventory.new(root: Deploy::SchemaMigrationGate::ROOT)
Deploy::SchemaMigrationGate.run.report!(
  "Schema/migration gate passed for #{inventory.apps.size} Rails apps."
)
