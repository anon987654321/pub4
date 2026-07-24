#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/user_flow_gate"

Deploy::UserFlowGate.run.report!(
  "User flow + MASTER design-principle gate passed."
)
