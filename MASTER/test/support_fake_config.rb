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
  end
end
