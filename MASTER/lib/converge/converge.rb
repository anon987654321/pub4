# frozen_string_literal: true

require "json"
require "yaml"
require "tsort"

# Converge is a standalone convergence engine, separate from the main MASTER pipeline.
# It is not wired into Builder or the 11-stage pipeline — callers invoke it directly:
#
#   engine = Converge::Engine.new(canon_path)
#   engine.subscribe { |event, payload| ... }
#   engine.run(initial_context_hash)
#
# canon_path points to a YAML file of Rule definitions (see Converge::Canon).
module Converge
  autoload :Canon,       "converge/canon"
  autoload :Engine,      "converge/engine"
  autoload :EventStream, "converge/event_stream"
  autoload :Rule,        "converge/rule"
end
