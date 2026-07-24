#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/layout_search_gate"
Deploy::LayoutSearchGate.run.report!("Layout search (least-resistance) gate passed.")
