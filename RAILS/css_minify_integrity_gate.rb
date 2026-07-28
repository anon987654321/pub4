#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/css_minify_integrity_gate"

result = Deploy::CssMinifyIntegrityGate.run
result.report!("css_minify_integrity: ok")
