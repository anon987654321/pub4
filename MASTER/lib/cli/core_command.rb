# frozen_string_literal: true

require "optparse"
require_relative "../trace/dmesg"
require_relative "../trace/event_bus"
require_relative "../trace/effect_observer"

module Master
  module CLI
    # `bin/master core`: the fold spine only. The rest of bin/master boots the full
    # runtime (soul, scan, voice); this drives lib/core.rb with a scripted model
    # unless --real. A missing goal exits 64 with the usage.
    module CoreCommand
      USAGE = "usage: bin/master core [--root PATH] [--max-turns N] [--real [--model ID]] GOAL"
      REAL = "drive a live LLM (needs a provider key); default is the scripted constitution check"

      # Three self-labelled evidence claims, then done.
      class NullModel
        def initialize(goal)
          @goal = goal

          @script = [
            Master::Core::Effect.exec(["true"], evidence: :test_pass),
            Master::Core::Effect.exec(["true"], evidence: :scan_clean),
            Master::Core::Effect.exec(["true"], evidence: :code_review),
            Master::Core::Effect.done("noop complete: #{@goal}"),
          ]
        end

        def turns = @script.size

        def propose(_context, verbs:, **)
          unsupported = @script.map(&:verb).uniq - verbs
          raise "kernel verbs unavailable: #{unsupported.join(", ")}" unless unsupported.empty?

          @script.shift || Master::Core::Effect.done("noop complete: #{@goal}")
        end
      end

      module_function

      def parser(options)
        OptionParser.new do |opts|
          opts.banner = USAGE
          opts.on("--root PATH") { |path| options[:root] = path }
          opts.on("--max-turns N", Integer) { |n| options[:max_turns] = n }
          opts.on("--real", REAL) { options[:real] = true }
          opts.on("--model ID") { |id| options[:model] = id }
        end
      end

      def run(argv, master_root: Master::ROOT)
        options = { root: Dir.pwd, max_turns: 40, real: false, model: nil }
        opts = parser(options)
        opts.parse!(argv)
        goal = argv.join(" ").strip

        if goal.empty?
          Master::Trace::Dmesg::Report.print("/help", opts.to_s, io: $stderr)
          return 64
        end

        fold(goal, options, master_root:)
      end

      def fold(goal, options, master_root:)
        root = File.expand_path(options.fetch(:root))
        model = model_for(goal, options)
        refusals = []

        result = Master::Core::Fold.new(
          model:, constitution: constitution(root, master_root), world: Master::Core::World.new(root:),
          memory: Master::Core::Memory.new, max_turns: turn_budget(model, options),
          observer: refusal_recorder(refusals),
          effect_observer: Master::Trace::EffectObserver.new(bus: event_bus(root))
        ).run(goal)
        verdict(result, refusals, real: options[:real])
      end

      # Each refused `done` leaves its reason, which the verdict reads.
      def refusal_recorder(refusals)
        lambda do |turn:, effect:, observation:|
          refusals << observation.detail if effect.done? && !observation.ok?
        end
      end

      # The scripted run ends when its script does; a real model gets --max-turns.
      def turn_budget(model, options) = options[:real] ? options.fetch(:max_turns) : model.turns

      def model_for(goal, options)
        return NullModel.new(goal) unless options[:real]

        Master::Core::Model.new(**{ model_id: options[:model] }.compact)
      end

      # The same guards CoreBridge gives the Fold: without them this entrypoint admitted writes no
      # scan verified and execs no sandbox scoped, the path that runs unattended.
      def constitution(root, master_root)
        bridge = Master::CLI::CoreBridge
        hooks = Master::CLI::ToolHooks

        Master::Core::Constitution.load(
          data_dir: File.join(master_root, "data"), workspace_root: root,
          capabilities: Master::Core::Capabilities.for(:fix),
          verify: hooks.wrap_verifier(bridge.scan_verifier(root:), root:),
          sandbox: hooks.wrap_sandbox(bridge.shell_sandbox(root:), root:)
        )
      end

      # A run against the checkout itself records into MASTER's own event log.
      def event_bus(root)
        own = [Master::ROOT, Master::REPO_ROOT].map { |path| File.expand_path(path) }.include?(root)
        Master::Trace::EventBus.new(event_log: Master::Trace::Log::Event.new(root: own ? Master::ROOT : root))
      end

      # The scripted run is a check of the constitution, not a completed goal. It
      # execs true(1) three times, each labelled as evidence it cannot produce, then
      # declares done; true, because the sandbox refuses an inline interpreter such
      # as ruby -e before it runs. Core::Proof scores evidence only from a command
      # that can produce it, so `done` must be refused: exit 0 says the fold held,
      # and exit 1 says it admitted done on self-graded evidence. With --real, exit
      # 0 means the model's goal completed.
      def verdict(result, refusals, real:)
        reason = result.reason

        if real
          Master::Trace::Dmesg.attach("core0", "master0", "#{reason}, #{result.turns} turns")
          Master::Trace::Dmesg.status("core0", result.summary)
          return reason == :complete ? 0 : 1
        end

        if reason != :complete && refusals.any? { |detail| detail.include?("evidence_for_done") }
          Master::Trace::Dmesg.attach("core0", "master0", "held, done refused without passing evidence")
          Master::Trace::Dmesg.status("core0", refusals.last)
          return 0
        end

        Master::Trace::Dmesg.status("core0", "#{reason}, scripted done was not refused for evidence: #{result.summary}")
        1
      end
    end
  end
end
