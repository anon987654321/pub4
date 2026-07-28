#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/surface_schema_gate"

result = Deploy::SurfaceSchemaGate.run
result.report!("surface_schema: ok")
