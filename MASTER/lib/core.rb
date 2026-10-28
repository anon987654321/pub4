# frozen_string_literal: true

# MASTER — a constitutional coding agent.
#
# The whole thing is one sentence: fold proposed effects through a constitution
# that admits each one before it touches the world. Four concepts carry it —
# Fold, Constitution (the check), World (the effects), Memory (the record) — and
# this file holds the vocabulary they share.
#
# Until 2026-08-12 this was `core/master.rb`, the root of a second spine loaded
# on its own path. It is now `lib/core.rb`, autoloaded by the same Zeitwerk
# loader as the rest of `lib/`, which is what the path-to-constant mapping
# already wanted: `lib/core.rb` → `Master::Core`, `lib/core/fold.rb` →
# `Master::Core::Fold`. The fold still depends on nothing in `lib/` outside its
# own namespace — `test/test_core_no_lib_backedges.rb` is what holds that, and
# it is the part of the two-spine split that was carrying real weight.
module Master::Core
  # An Effect is something the agent wants to do. Nothing reaches the world
  # except by proposing an Effect and having the Constitution admit it. The verb
  # set is closed and small; that closure is what makes the agent auditable.
  VERBS = %i[read write exec git http ask note critique done].freeze

  # Cooperative cancellation shared by hosts and the Fold. A cancellation is
  # sticky: the first reason remains authoritative across racing callers.
  class CancellationToken
    def initialize
      @mutex = Mutex.new
      @reason = nil
      @active = false
    end

    def cancel!(reason: "operator requested cancellation")
      value = reason.to_s.strip
      raise ArgumentError, "cancellation reason cannot be empty" if value.empty?

      @mutex.synchronize { @reason ||= value[0, 240].freeze }
      self
    end

    # Mark that the consumer is honoring cancellation cooperatively. Hosts
    # can then avoid killing a running thread at an arbitrary point.
    def activate!
      @mutex.synchronize { @active = true }
      self
    end

    def active? = @mutex.synchronize { @active }
    def cancelled? = @mutex.synchronize { !@reason.nil? }
    def reason = @mutex.synchronize { @reason }
  end

  # A compensation is a proposed inverse command, not a promise that it works.
  # The Constitution must admit it and the operator must approve it after the
  # original effect fails. It is deliberately limited to argv, never shell text.
  CompensatingAction = Data.define(:argv, :reason) do
    def initialize(argv:, reason:)
      unless argv.is_a?(Array) && !argv.empty? && argv.all? { |arg| arg.is_a?(String) } && !argv.first.strip.empty?
        raise ArgumentError, "compensation argv must be a non-empty array of strings"
      end

      detail = reason.to_s.strip
      raise ArgumentError, "compensation needs a human-readable reason" if detail.empty?

      super(argv: argv.map { |arg| arg.dup.freeze }.freeze, reason: detail.freeze)
    end
  end

  # This classification is derived from the Effect, never chosen by the model.
  # A label is not proof of reversibility: only named, implemented compensation
  # mechanisms count, and unknown operations fail closed.
  Reversibility = Data.define(:kind, :scope, :compensation, :reason) do
    def initialize(kind:, scope: nil, compensation: nil, reason: nil)
      kind = kind.to_sym
      allowed = %i[non_mutating session_state reversible compensatable approval_required policy_gated unknown]
      raise ArgumentError, "unknown reversibility kind: #{kind}" unless allowed.include?(kind)

      super(kind:, scope: scope&.to_s&.freeze, compensation:, reason: reason.to_s.freeze)
    end

    def restorable? = kind == :reversible
    def compensatable? = kind == :compensatable
    def approval_required? = kind == :approval_required

    # The receipt's coarser vocabulary (Execution::Contract::REVERSIBILITY),
    # which decides whether a replay must reconcile first. Harmless or undoable
    # is reversible; an effect only a person or a policy can take back is not.
    def contract_kind
      case kind
      when :non_mutating, :session_state, :reversible then :reversible
      when :compensatable then :compensatable
      when :approval_required, :policy_gated then :irreversible
      else :unknown
      end
    end
  end

  Effect = Data.define(:verb, :args, :capability) do
    def self.read(path) = new(verb: :read, args: { path: })
    def self.write(path, content) = new(verb: :write, args: { path:, content: })
    def self.http(url) = new(verb: :http, args: { url: })
    def self.exec(argv, timeout: 60, evidence: nil, env: {}, compensation: nil)
      args = { argv:, timeout:, evidence:, env: }
      args[:compensation] = compensation unless compensation.nil?
      new(verb: :exec, args:)
    end
    def self.git(operation, **args)
      capability = operation.to_s.to_sym == :diff ? :read : :write
      new(verb: :git, args: { operation:, **args }, capability:)
    end
    def self.ask(prompt, options: nil) = new(verb: :ask, args: { prompt:, options: })
    def self.note(kind, text) = new(verb: :note, args: { kind:, text: })
    def self.critique(scope: "diff") = new(verb: :critique, args: { scope: })
    def self.done(summary = nil) = new(verb: :done, args: { summary: })

    CAPABILITIES = {
      read: :read,
      write: :write,
      exec: :execute,
      git: :write,
      ask: :stdio,
      note: :stdio,
      critique: :stdio,
      http: :network,
      done: :stdio,
    }.freeze

    def initialize(verb:, args:, capability: nil)
      verb = verb.to_sym
      raise ArgumentError, "unknown effect verb: #{verb}" unless VERBS.include?(verb)
      raise ArgumentError, "effect args must be a Hash" unless args.is_a?(Hash)

      args = freeze_payload(args)
      expected = if verb == :git && args[:operation].to_s.to_sym == :diff
                   :read
                 else
                   CAPABILITIES.fetch(verb)
                 end
      supplied = capability&.to_sym
      raise ArgumentError, "effect capability mismatch: #{verb} requires #{expected}, got #{supplied}" if supplied && supplied != expected

      super(verb:, args:, capability: expected)
      compensation_action if args.key?(:compensation) || args.key?("compensation")
    end

    # An admitted effect must not change underneath the Constitution or the
    # operator's approval prompt. Copy and freeze the JSON-shaped payload so
    # later code cannot mutate nested argv, paths, or write content in place.
    def freeze_payload(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, item), copy|
          copy[freeze_payload(key)] = freeze_payload(item)
        end.freeze
      when Array
        value.map { |item| freeze_payload(item) }.freeze
      when String
        value.dup.freeze
      else
        value
      end
    end
    private :freeze_payload

    # Policy derives from the operation's actual capabilities. policy_gated
    # means the existing command/network guard decides; it does NOT mean safe or
    # reversible. A failed arbitrary command has no generic rollback.
    def reversibility
      case verb
      when :read, :critique, :ask, :done
        Reversibility.new(kind: :non_mutating)
      when :note
        Reversibility.new(kind: :session_state, scope: "conversation memory",
                          reason: "session memory is not a repository side effect")
      when :write
        Reversibility.new(kind: :reversible, scope: args[:path], compensation: :scoped_checkpoint_restore,
                          reason: "a failed write can be restored at its own path from the pre-effect checkpoint")
      when :exec
        action = compensation_action
        if action
          Reversibility.new(kind: :compensatable, scope: Array(args[:argv]).join(" "), compensation: action,
                            reason: action.reason)
        else
          Reversibility.new(kind: :policy_gated, scope: Array(args[:argv]).join(" "),
                            reason: "the command policy must classify this command; no generic inverse exists")
        end
      when :http
        Reversibility.new(kind: :policy_gated, scope: args[:url],
                          reason: "network policy owns authorization; the remote effect has no generic inverse")
      when :git
        case args[:operation].to_s.to_sym
        when :diff
          Reversibility.new(kind: :non_mutating)
        when :stage
          paths = Array(args[:paths]).map(&:to_s).reject { |path| path.strip.empty? }
          if paths.empty?
            Reversibility.new(kind: :unknown, scope: :stage,
                              reason: "git stage requires explicit paths; unscoped index changes are refused")
          else
            Reversibility.new(kind: :approval_required, scope: paths.join(", "),
                              reason: "git stage mutates the shared index and MASTER has no scoped index rollback")
          end
        when :commit
          paths = Array(args[:paths]).map(&:to_s).reject { |path| path.strip.empty? }
          if paths.empty?
            Reversibility.new(kind: :unknown, scope: :commit,
                              reason: "git commit requires explicit paths; the shared index is never an implicit scope")
          else
            Reversibility.new(kind: :approval_required, scope: paths.join(", "),
                              reason: "git commit creates durable repository history and is not automatically undone")
          end
        else
          Reversibility.new(kind: :unknown, scope: args[:operation],
                            reason: "no reversibility contract or World handler exists for this git operation")
        end
      else
        Reversibility.new(kind: :unknown, scope: verb, reason: "no reversibility contract exists for this effect")
      end
    end

    # A compensation is structured data that will be re-admitted as a new exec
    # and explicitly approved only if the original command fails. It cannot
    # contain another compensation, and its human-readable reason is mandatory.
    def compensation_action
      raw = args.key?(:compensation) ? args[:compensation] : args["compensation"]
      return if raw.nil?
      raise ArgumentError, "compensation is valid only for exec effects" unless verb == :exec
      raise ArgumentError, "compensation must be an object with argv and reason" unless raw.is_a?(Hash)

      data = raw.to_h { |key, value| [key.to_sym, value] }
      extra = data.keys - %i[argv reason]
      raise ArgumentError, "unknown compensation fields: #{extra.join(", ")}" unless extra.empty?

      CompensatingAction.new(argv: data[:argv], reason: data[:reason])
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

  # Monotonic authority for one cognitive context.
  #
  # A context starts from an explicit profile. Capabilities may be removed,
  # never acquired. Locking freezes the decision so authority cannot widen
  # halfway through a task.
  class Capabilities
    PROFILES = {
      boot: %i[stdio read execute],
      model: %i[stdio read model],
      # Reading the web is observing: the http verb is a guarded GET, so a
      # question about a page runs in observe or plan mode and must be able to
      # fetch it. Writing and executing stay out.
      observe: %i[stdio read network],
      plan: %i[stdio read model network],
      fix: %i[stdio read write create execute network],
      repair: %i[stdio read write create execute network],
      deploy: %i[stdio read write create execute network deploy],
      device: %i[stdio read device],
      world: %i[stdio read world],
    }.freeze

    def self.for(name)
      values = PROFILES.fetch(name.to_sym)
      new(name:, capabilities: values)
    end

    def self.read_only
      new(name: :read_only, capabilities: %i[stdio read])
    end

    def initialize(name:, capabilities:)
      @name = name.to_sym
      @allowed = capabilities.map(&:to_sym).uniq.freeze
      @locked = false
    end

    attr_reader :name
    def capabilities = @allowed
    def allows?(capability) = @allowed.include?(capability.to_sym)
    alias allow? allows?

    def require!(capability)
      return true if allows?(capability)
      raise SecurityError, "capability refused: #{capability}"
    end

    def drop(*capabilities)
      raise SecurityError, "capability table is locked" if @locked
      @allowed = (@allowed - capabilities.map(&:to_sym)).freeze
      self
    end

    def lock!
      @locked = true
      freeze
    end

    def locked? = @locked

    def acquire(_capability)
      raise SecurityError, "capability acquisition is forbidden; create a new trusted context"
    end

    def to_h
      { name: @name, capabilities: @allowed, locked: @locked }
    end
  end
end
