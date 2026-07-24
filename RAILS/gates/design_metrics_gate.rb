#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/design_metrics_gate"

result = Deploy::DesignMetricsGate.run
result.report!("design_metrics: ok")
