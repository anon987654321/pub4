# frozen_string_literal: true

# Autonomous control plane for MASTER.
#
# This is deliberately above Core::Fold. Core remains the trusted execution
# spine:
#
#   Effect -> Constitution -> World -> Memory
#
# Autonomy owns everything that makes that spine persistent and goal-seeking:
# goals, task graphs, planning, recovery, checkpoints, events and context.
#
# MASTER does not delegate coding to another agent. The same Core::Model is the
# intelligence used for planning and for proposing Effects.
# Six files, not twelve. The proposal this came from also carried a repo
# inspector, a context compiler, a snapshot store, model extensions, a planner
# and a runner. Each of those already exists here under another name —
# tools/repo_inventory.rb, eight files answering to context, Core::World's
# checkpoint and rollback, lib/core/model.rb, and thirty-two under lib/fix — and
# a second implementation of a thing that works is the twin this tree has spent
# a campaign retiring.
#
# What is genuinely absent is the durable half: a dependency graph that can say
# what is blocked on what, a store that survives a crash, and a way back into an
# interrupted run. That is what these six are.
require_relative "autonomy/schema"
require_relative "autonomy/event_store"
require_relative "autonomy/goal"
require_relative "autonomy/task"
require_relative "autonomy/task_graph"
require_relative "autonomy/recovery"

module Master
  module Autonomy
    VERSION = "1.0.0"
  end
end
