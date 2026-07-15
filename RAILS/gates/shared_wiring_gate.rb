#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/shared_wiring_gate"

Deploy::SharedWiringGate.run.report!("Shared wiring gate passed (routes, importmap, public assets, Stimulus).")