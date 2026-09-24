# frozen_string_literal: true

module Master
  module TestSupport
    # The config object ModelRouter and Review::Agent read, with nothing on it
    # but the two fields they ask for. Four routing tests each carried their own
    # copy — two byte-identical, two variants that differed only in whether they
    # exposed task_type and whether model had a default — so a router that grew
    # a third accessor would have needed the same edit four times.
    #
    # Usage:
    #   FakeConfig = Master::TestSupport::FakeConfig
    #   FakeConfig.new                      # free-tier chitchat model, :general
    #   FakeConfig.new(model: "web-chat:grok")
    class FakeConfig
      DEFAULT_MODEL = "z-ai/glm-4.5-air:free"

      attr_reader :model, :task_type

      def initialize(model: DEFAULT_MODEL, task_type: :general)
        @model = model
        @task_type = task_type
      end
    end

    # Routing tests grade the policy that builds a chain: which lanes, in which
    # order, under which switches. Two inputs to it are this machine's history
    # rather than policy: the OpenRouter catalog cached under the state dir
    # (live_free_models), and ComputePool's measured outcomes under runtime/,
    # which reorder the chain by what this Mac has seen. With both in play the
    # same test passed on one machine and failed on the next. The pool keeps its
    # own test; here it leaves the order as the policy made it, and the live
    # catalog is empty. Returns a lambda that restores both.
    module RoutingIsolation
      def self.install
        pool = Master::Core::Routing::ComputePool
        router = Master::CLI::Routing::ModelRouter
        saved = [[pool, :rank, pool.instance_method(:rank)],
                 [router, :live_free_models, router.instance_method(:live_free_models)]]
        pool.define_method(:rank) { |ids, **| Array(ids) }
        router.define_method(:live_free_models) { [] }
        lambda do
          saved.each do |klass, name, method|
            method.owner == klass ? klass.define_method(name, method) : klass.remove_method(name)
          end
        end
      end
    end
  end
end
