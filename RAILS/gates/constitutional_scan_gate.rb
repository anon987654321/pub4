#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/constitutional_scan_gate"

result = Deploy::ConstitutionalScanGate.run
result.report!("Constitutional scan preflight completed.")
