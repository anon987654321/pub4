#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/frontend_auditor_gate_logic"

result = Deploy::FrontendAuditorGate.run
result.report!("auditor: 0 warnings")