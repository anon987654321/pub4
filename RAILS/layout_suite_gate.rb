#!/usr/bin/env ruby
# frozen_string_literal: true

# GATE_AUTOFIX on by default (fix + remeasure). Opt out: GATE_AUTOFIX=0
require_relative "gates/lib/layout_suite_gate"
Deploy::LayoutSuiteGate.run.report!("Layout suite passed (CSS + geometry + dialect + payment + flow + auditor).")
