# frozen_string_literal: true

# MASTER — a constitutional coding agent.
#
# The whole thing is one sentence: fold proposed effects through a constitution
# that admits each one before it touches the world. Four concepts carry it —
# Kernel (the fold), Constitution (the gate), World (the effects), Memory (the
# record) — and this file holds the vocabulary they share.
module Master
  # An Effect is something the agent wants to do. Nothing reaches the world
  # except by proposing an Effect and having the Constitution admit it. The verb
  # set is closed and small; that closure is what makes the agent auditable.
  VERBS = %i[read write exec git ask note done].freeze

  Effect = Data.define(:verb, :args) do
    def self.done(summary = nil) = new(verb: :done, args: { summary: })
    def done? = verb == :done
    def to_s = "#{verb}(#{args.keys.join(', ')})"
  end

  # A Verdict is the Constitution's answer to an Effect. The Kernel sees two
  # shapes; the third is internal to a single rule:
  #   Allow(effect:)       perform this effect (possibly rewritten by a rule)
  #   Block(reason:, by:)  it must not happen; the agent observes and adapts
  # A rule may also return Revise to rewrite the effect for the rules after it.
  module Verdict
    Allow = Data.define(:effect)
    Revise = Data.define(:effect, :by)
    Block = Data.define(:reason, :by)
  end

  # What the World reports after performing an Effect. The agent reacts to this,
  # so a failure is data the model must handle — never a swallowed success.
  Observation = Data.define(:ok, :detail) do
    def self.ok(detail = nil) = new(ok: true, detail:)
    def self.no(detail) = new(ok: false, detail:)
    def to_s = "#{ok ? 'ok' : 'ERR'}#{detail ? ": #{detail}" : ''}"
  end

  # Secret — a value that cannot leak by accident. Every implicit stringify
  # redacts; only #expose, named loudly, reveals it. The one type-level
  # guarantee, orthogonal to the four concepts.
  class Secret
    def initialize(value) = (@value = value.to_str.dup).freeze
    def expose = @value
    def to_s = "[REDACTED]"
    def inspect = "[REDACTED]"
    def to_str = "[REDACTED]"
    def _dump(_) = raise(TypeError, "Secret cannot be Marshalled")
  end
end

require_relative "memory"
require_relative "world"
require_relative "constitution"
require_relative "kernel"
