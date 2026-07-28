#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/cross_app_equivalence_gate"

Deploy::CrossAppEquivalenceGate.run.report!("ok: shared chrome agrees across apps")
