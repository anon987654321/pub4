# frozen_string_literal: true

module Executor
  class Plan
    Step = Struct.new(:name, :callable, :args, :kwargs, :block, keyword_init: true)

    DEFAULT_OPTIONS = {
      halt_on_error: true
    }.freeze

    attr_reader :steps, :results, :errors

    def initialize(**options)
      @options = DEFAULT_OPTIONS.merge(options)
      @steps = []
      @results = {}
      @errors = {}
    end

    def add_step(name, callable = nil, *args, **kwargs, &block)
      callable ||= block
      raise ArgumentError, "step #{name.inspect} requires a callable" unless callable

      @steps << Step.new(name: name, callable: callable, args: args, kwargs: kwargs, block: block)
      self
    end

    def run(context = nil)
      @steps.each do |step|
        begin
          @results[step.name] = execute_step(step, context)
        rescue StandardError => e
          @errors[step.name] = e
          raise if @options[:halt_on_error]
        end
      end
      self
    end

    def success?
      @errors.empty?
    end

    def failed?
      !success?
    end

    def result(name = nil)
      name ? @results[name] : @results
    end

    def error(name = nil)
      name ? @errors[name] : @errors
    end

    private

    def execute_step(step, context)
      if step.kwargs && !step.kwargs.empty?
        step.callable.call(context, *step.args, **step.kwargs)
      else
        step.callable.call(context, *step.args)
      end
    end
  end
end