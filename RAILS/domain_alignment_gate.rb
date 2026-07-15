#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../OPENBSD/lib/utf8"
require_relative "gates/lib/domain_alignment_gate_logic"

Deploy::DomainAlignmentGate.run.report!(
  "Domain alignment gate passed (city domains + master.json/relayd checks)."
)