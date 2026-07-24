#!/usr/bin/env ruby
# frozen_string_literal: true

# GATE_AUTOFIX on by default (mechanical fix + remeasure). Opt out: GATE_AUTOFIX=0
# GATE_AUTOFIX_ROUNDS=3   max fix rounds
# GATE_AUTOFIX_DRY=1      print patches only
require_relative "gates/lib/css_constitution_gate"
Deploy::CssConstitutionGate.run.report!("CSS constitution gate passed (all stylesheets).")
