#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/layout_geometry_gate"
Deploy::LayoutGeometryGate.run.report!("Layout geometry / first-screen gate passed.")
