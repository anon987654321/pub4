#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/flow_journey_gate"

Deploy::FlowJourneyGate.run.report!("ok: user journeys pass with postconditions")
