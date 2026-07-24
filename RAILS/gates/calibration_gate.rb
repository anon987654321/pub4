#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/calibration_gate"

result = Deploy::CalibrationGate.run
result.report!("calibration: ok")
