# frozen_string_literal: true

require_relative "transforms"
require_relative "search"
require_relative "novelty"
require_relative "optimizer"

module Master
  module Review
    module Inference
      class Runner
        BudgetExceeded = Class.new(StandardError)

        class BudgetedAgent
          attr_reader :calls

          def initialize(agent, max_calls:)
            @agent = agent
            @max_calls = [max_calls.to_i, 1].max
            @calls = 0
            @mutex = Mutex.new
          end

          def ask_once(prompt, **options)
            @mutex.synchronize do
              raise BudgetExceeded, "inference call budget exhausted (#{@max_calls})" if @calls >= @max_calls

              @calls += 1
            end
            @agent.ask_once(prompt, **options)
          end
        end

        DEFAULTS = {
          max_calls: 8,
          samples: 5,
          branches: 3,
          beam: 2,
          depth: 2,
          temperature: 0.7
        }.freeze

        def initialize(agent:, event_bus: nil, root: Master::ROOT)
          @agent = agent
          @bus = event_bus
          @root = root
        end

        def run(prompt:, task_type: :exploration, strategy: nil, **options)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          config = options.fetch(:config, inference_config)
          selected = (strategy || config.fetch("tasks", {})[task_type.to_s] || :direct).to_sym
          defaults = config.fetch("defaults", {}).transform_keys(&:to_sym)
          settings = DEFAULTS.merge(defaults).merge(options)
          worker = BudgetedAgent.new(@agent, max_calls: settings.fetch(:max_calls))

          result = dispatch(selected, prompt.to_s, settings, worker)
          emit(selected, task_type, result, started, calls: worker.calls)
          result
        rescue StandardError => e
          result = Master::Result.err("inference: #{e.class}: #{e.message}", category: :handler_exception)
          emit(selected || :unknown, task_type, result, started, calls: worker&.calls.to_i)
          result
        end

        private

        def dispatch(strategy, prompt, settings, agent)
          temperature = settings.fetch(:temperature).to_f
          max_calls = [settings.fetch(:max_calls).to_i, 1].max
          case strategy
          when :direct
            Master::Result.ok(strategy: :direct, answer: agent.ask_once(prompt, temperature:))
          when :repeat
            Master::Result.ok(strategy: :repeat, answer: agent.ask_once(Transforms.repeat(prompt), temperature:))
          when :self_aware
            Master::Result.ok(strategy: :self_aware, answer: agent.ask_once(Transforms.self_aware(prompt), temperature:))
          when :style
            name = settings.fetch(:style, :senior_engineer)
            Master::Result.ok(strategy: :style, answer: agent.ask_once(Transforms.style(prompt, name), temperature:))
          when :rival
            phase = settings.fetch(:phase, :review)
            Master::Result.ok(strategy: :rival, answer: agent.ask_once(Transforms.rival(prompt, phase:), temperature:))
          when :self_consistency
            Search.self_consistency(
              agent:,
              prompt:,
              samples: bounded(settings.fetch(:samples), max_calls),
              temperature:,
              extractor: settings[:extractor] || method(:default_extractor)
            )
          when :skeleton
            Search.skeleton(agent:, prompt:, points: bounded(settings.fetch(:points, 5), [max_calls - 2, 1].max), temperature:)
          when :tree, :tree_of_thoughts
            Search.tree(
              agent:,
              prompt:,
              branches: [bounded(settings.fetch(:branches), 2), 1].max,
              beam: [bounded(settings.fetch(:beam), 2), 1].max,
              depth: [bounded(settings.fetch(:depth), max_calls >= 9 ? 2 : 1), 1].max,
              temperature:
            )
          when :denial
            Novelty.denial(agent:, prompt:, constraints: Array(settings.fetch(:constraints, default_constraints)),
              rounds: bounded(settings.fetch(:rounds, 3), max_calls), temperature:)
          when :quadrant_vacancy, :qvp
            samples = [bounded(settings.fetch(:samples), [max_calls - 3, 1].max), 1].max
            fill_limit = [max_calls - samples - 2, 0].max
            Novelty.quadrant_vacancy(agent:, theme: prompt, samples:, fill_limit:, temperature:)
          when :strange_world, :orthogonal
            Novelty.strange_world(agent:, problem: prompt,
              seeds: Array(settings.fetch(:seeds, default_seeds)), temperature:)
          when :perspective, :perspective_transition
            Novelty.perspective(agent:, prompt:, temperature:)
          when :debate
            Novelty.debate(agent:, prompt:, rounds: bounded(settings.fetch(:rounds, 2), 3), temperature:)
          when :critique_revision, :revise
            Novelty.critique_revision(agent:, prompt:, rounds: bounded(settings.fetch(:rounds, 3), max_calls), temperature:)
          when :novelty
            Novelty.novelty(agent:, prompt:, constraints: Array(settings.fetch(:constraints, default_constraints)),
              seeds: Array(settings.fetch(:seeds, default_seeds)), temperature:)
          when :gepa
            Optimizer.gepa(
              agent:,
              prompt:,
              dataset: settings.fetch(:dataset),
              metric: settings.fetch(:metric),
              generations: settings.fetch(:generations, 2),
              population: settings.fetch(:population, 3),
              temperature:
            )
          else
            Master::Result.err("inference: unsupported strategy #{strategy}", category: :validation)
          end
        end

        def inference_config
          data = Master.load_yaml(File.join(@root, "data", "prompts.yml"), default: {}) || {}
          data.fetch("inference", {})
        end

        def default_constraints
          Array(inference_config.dig("strategies", "denial", "constraints"))
        end

        def default_seeds
          Array(inference_config.dig("strategies", "strange_world", "seeds"))
        end

        def bounded(value, limit)
          [value.to_i, 1].max.then { |n| [n, limit.to_i].min }
        end

        def default_extractor(text)
          text.to_s.lines.reverse_each.find { |line| !line.strip.empty? }.to_s.strip
        end

        def emit(strategy, task_type, result, started, calls:)
          ok = result.respond_to?(:ok?) && result.ok?
          ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
          @bus&.publish(
            "inference:#{strategy}",
            task_type: task_type.to_s,
            ok:,
            latency_ms: ms,
            calls:,
            strategy:
          )
        end
      end
    end
  end
end
