#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/reflow_gate"

Deploy::ReflowGate.run.report!("ok: no overflow across the width sweep")
