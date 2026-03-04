# frozen_string_literal: true

module Bridges
  module Repligen
    class Pipelines
      DEFAULT_BATCH_SIZE = 500
      PRELOAD_ASSOCIATIONS = %i[steps latest_run].freeze

      def initialize(scope: ::Pipeline.all, batch_size: DEFAULT_BATCH_SIZE, logger: ::Rails.logger)
        @scope = scope
        @batch_size = batch_size
        @logger = logger
      end

      def scan(&block)
        return enum_for(:scan) unless block

        each_pipeline do |pipeline|
          enforce_constraints!(pipeline)
          yield build_payload(pipeline)
        end
      end

      def build
        scan.to_a
      end

      private

      attr_reader :scope, :batch_size, :logger

      def each_pipeline(&block)
        return enum_for(:each_pipeline) unless block

        base_scope.find_in_batches(batch_size: batch_size) do |batch|
          batch.each(&block)
        end
      end

      def base_scope
        scope.includes(*PRELOAD_ASSOCIATIONS)
      end

      def enforce_constraints!(pipeline)
        return if pipeline.enabled?

        raise ArgumentError, "Pipeline #{pipeline.id} is disabled"
      end

      def build_payload(pipeline)
        {
          id: pipeline.id,
          name: pipeline.name,
          enabled: pipeline.enabled?,
          latest_run: build_latest_run(pipeline.latest_run),
          steps: build_steps(pipeline.steps)
        }
      end

      def build_latest_run(latest_run)
        return nil unless latest_run

        {
          id: latest_run.id,
          status: latest_run.status,
          started_at: latest_run.started_at,
          finished_at: latest_run.finished_at
        }
      end

      def build_steps(steps)
        steps.map do |step|
          {
            id: step.id,
            name: step.name,
            position: step.position
          }
        end
      end
    end
  end
end