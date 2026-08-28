# frozen_string_literal: true

# MASTER — a constitutional coding agent.
#
# The whole thing is one sentence: fold proposed effects through a constitution
# that admits each one before it touches the world. Four concepts carry it —
# Fold, Constitution (the gate), World (the effects), Memory (the record) — and
# this file holds the vocabulary they share.
#
# Until 2026-08-12 this was `core/master.rb`, the root of a second spine loaded
# on its own path. It is now `lib/core.rb`, autoloaded by the same Zeitwerk
# loader as the rest of `lib/`, which is what the path-to-constant mapping
# already wanted: `lib/core.rb` → `Master::Core`, `lib/core/fold.rb` →
# `Master::Core::Fold`. The fold still depends on nothing in `lib/` outside its
# own namespace — `test/core/test_no_lib_backedges.rb` is what holds that, and
# it is the part of the two-spine split that was carrying real weight.
module Master::Core
  # An Effect is something the agent wants to do. Nothing reaches the world
  # except by proposing an Effect and having the Constitution admit it. The verb
  # set is closed and small; that closure is what makes the agent auditable.
  VERBS = %i[read write exec git ask note critique done].freeze

  Effect = Data.define(:verb, :args) do
    def self.read(path) = new(verb: :read, args: { path: })
    def self.write(path, content) = new(verb: :write, args: { path:, content: })
    def self.exec(argv, timeout: 60, evidence: nil, env: {}) =
      new(verb: :exec, args: { argv:, timeout:, evidence:, env: })
    def self.git(operation, **args) = new(verb: :git, args: { operation:, **args })
    def self.ask(prompt, options: nil) = new(verb: :ask, args: { prompt:, options: })
    def self.note(kind, text) = new(verb: :note, args: { kind:, text: })
    def self.critique(scope: "diff") = new(verb: :critique, args: { scope: })
    def self.done(summary = nil) = new(verb: :done, args: { summary: })

    def initialize(verb:, args:)
      verb = verb.to_sym
      raise ArgumentError, "unknown effect verb: #{verb}" unless VERBS.include?(verb)

      super(verb:, args:)
    end

    def done? = verb == :done
    def to_s = "#{verb}(#{args.keys.join(', ')})"
  end

  # generation: which state of the tree this was earned against. Evidence proved
  # something about the code as it stood; a write after it makes it a statement
  # about a tree that no longer exists. Proof counts only the current generation.
  Evidence = Data.define(:kind, :ok, :score, :detail, :at, :generation)

  # A Verdict is the Constitution's answer to an Effect. The Core sees three
  # shapes; the fourth is internal to a single rule:
  #   Allow(effect:)         perform this effect (possibly rewritten by a rule)
  #   Block(reason:, by:)    it must not happen; the agent observes and adapts
  #   Request(effect:, ...)  a person decides, and the fold waits for them
  # A rule may also return Revise to rewrite the effect for the rules after it.
  #
  # Request exists because allow-or-refuse is not the whole of policy. The
  # World has been able to ask a person a question since it gained do_ask, and
  # no rule could produce a verdict that reached it -- so a rule facing an
  # effect that is dangerous in one context and routine in another had to
  # guess, permanently, on the agent's behalf. The sandbox rule is the case in
  # point: it can deny a command or stay silent, and has nowhere to put "this
  # one needs a human".
  #
  # `by` names the rule, as it does on Block, so an approval prompt can say
  # what is asking.
  module Verdict
    Allow = Data.define(:effect)
    Revise = Data.define(:effect, :by)
    Block = Data.define(:reason, :by)
    Request = Data.define(:effect, :prompt, :reason, :by) do
      def initialize(effect:, prompt:, by:, reason: nil) = super
    end
  end

  # What the World reports after performing an Effect. The agent reacts to this,
  # so a failure is data the model must handle — never a swallowed success.
  Observation = Data.define(:ok, :detail) do
    def self.ok(detail = nil) = new(ok: true, detail:)
    def self.no(detail) = new(ok: false, detail:)
    def ok? = ok
    def err? = !ok
    def value! = detail
    def message = detail.to_s
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
