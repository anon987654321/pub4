#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/gate_mutation_gate"

Deploy::GateMutationGate.run.report!("ok: gates detect the defects they exist to prevent")
