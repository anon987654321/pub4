#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/journey_invariant_gate"

Deploy::JourneyInvariantGate.run.report!("ok: journey invariants hold")
