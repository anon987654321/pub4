#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/keyboard_flow_gate"

Deploy::KeyboardFlowGate.run.report!("ok: keyboard tab order is sound")
