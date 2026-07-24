#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/visual_quality_gate"

result = Deploy::VisualQualityGate.run
result.report!("visual_quality: ok")
