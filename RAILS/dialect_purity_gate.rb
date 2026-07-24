#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/dialect_purity_gate"
Deploy::DialectPurityGate.run.report!("Dialect purity gate passed.")
