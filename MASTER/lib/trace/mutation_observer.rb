# frozen_string_literal: true

require "securerandom"
require_relative "event_bus"
require_relative "log"

module Master
  module Trace
    # Durable before/after audit for mutations outside the Core Fold. Event
    # payloads carry identifiers and bounded metrics, never paths or contents.
    class MutationObserver
      Token = Data.define(:audit_id, :operation, :started_at)

      STATUSES = %w[ok failed blocked ambiguous].freeze
      LABEL = /\A[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,127}\z/

      def initialize(root:, namespace:, subject_type:, subject_id:, bus: nil)
        @root = File.expand_path(root)
        @namespace = validate_label(namespace, "namespace")
        @subject_type = validate_label(subject_type, "subject type")
        @subject_id = validate_label(subject_id, "subject id")
        @bus = bus.respond_to?(:publish_required) ? bus : fallback_bus
        @failed = false
      end

      def mutate(operation:, item_count: nil)
        raise ArgumentError, "a mutation block is required" unless block_given?

        token = before(operation:, item_count:)
        after_attempted = false
        begin
          result = yield
          status = result_status(result)
          after_attempted = true
          after(token, status:, item_count:)
          result
        rescue StandardError
          if token && !after_attempted && !@failed
            after_attempted = true
            after(token, status: "failed", item_count:)
          end
          raise
        end
      end

      def before(operation:, item_count: nil)
        ensure_healthy!
        operation = validate_label(operation, "operation")
        token = Token.new(SecureRandom.uuid, operation, monotonic_ms)
        @bus.publish_required(
          "#{@namespace}:before",
          payload(token, item_count:),
        )
        token
      rescue StandardError
        @failed = true
        raise
      end

      def after(token, status: "ok", item_count: nil)
        ensure_healthy!
        raise ArgumentError, "invalid mutation token" unless token.is_a?(Token)
        status = status.to_s
        raise ArgumentError, "invalid mutation status" unless STATUSES.include?(status)

        @bus.publish_required(
          "#{@namespace}:after",
          payload(token, status:, item_count:, elapsed_ms: monotonic_ms - token.started_at),
        )
        true
      rescue StandardError
        @failed = true
        raise
      end

      def failed? = @failed

      private

      def payload(token, status: nil, item_count: nil, elapsed_ms: nil)
        value = {
          audit_id: token.audit_id,
          subject_type: @subject_type,
          subject_id: @subject_id,
          operation: token.operation,
        }
        value[:status] = status if status
        value[:item_count] = Integer(item_count) unless item_count.nil?
        value[:elapsed_ms] = Integer(elapsed_ms) unless elapsed_ms.nil?
        value
      end

      def result_status(result)
        if result.is_a?(Array) && result.last.respond_to?(:success?)
          return result.last.success? ? "ok" : "failed"
        end
        return "ok" unless result.respond_to?(:ok?)
        return "ok" if result.ok?
        return "blocked" if result.respond_to?(:category) && result.category == :policy

        "failed"
      end

      def ensure_healthy!
        raise IOError, "mutation audit is halted after a lifecycle publication failure" if @failed
      end

      def validate_label(value, name)
        label = value.to_s
        raise ArgumentError, "invalid mutation audit #{name}" unless LABEL.match?(label)

        label
      end

      def monotonic_ms
        Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
      end

      def fallback_bus
        canonical_roots = []
        canonical_roots << File.expand_path(Master::ROOT) if defined?(Master::ROOT)
        canonical_roots << File.expand_path(Master::REPO_ROOT) if defined?(Master::REPO_ROOT)
        telemetry_root = canonical_roots.include?(@root) && defined?(Master::ROOT) ? Master::ROOT : @root
        event_log = Master::Trace::Log::Event.new(root: telemetry_root)
        Master::Trace::EventBus.new(event_log:)
      end
    end
  end
end
