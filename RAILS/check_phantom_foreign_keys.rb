#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../OPENBSD/lib/utf8"
require_relative "gates/lib/phantom_foreign_keys_gate"

result = Deploy::PhantomForeignKeysGate.run
schemas = Dir.glob(File.join(Deploy::PhantomForeignKeysGate::ROOT, "RAILS", "*", "db", "schema.rb")).size
result.report!("phantom_foreign_keys: clean (#{schemas} schemas)")
