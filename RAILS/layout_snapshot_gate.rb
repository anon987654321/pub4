#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/layout_snapshot_gate"

Deploy::LayoutSnapshotGate.run.report!("ok: layout snapshots match committed baselines")
