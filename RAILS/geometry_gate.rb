#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/geometry_gate"

Deploy::GeometryGate.run.report!("ok: geometry contracts satisfied (rendered)")
