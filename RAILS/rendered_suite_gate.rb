#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/rendered_suite_gate"

Deploy::RenderedSuiteGate.run.report!("ok: rendered browser suite clean")
