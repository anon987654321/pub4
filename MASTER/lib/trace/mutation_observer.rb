# frozen_string_literal: true

require "securerandom"
require "json"
require "fileutils"
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

      def initialize(root:, namespace:, subject_type:, subject_id:, bus: nil, marker_root: nil)
        @root = File.expand_path(root)
        @namespace = validate_label(namespace, "namespace")
        @subject_type = validate_label(subject_type, "subject type")
        @subject_id = validate_label(subject_id, "subject id")
        @bus = bus.respond_to?(:publish_required) ? bus : fallback_bus
        @marker_root = File.expand_path(marker_root, @root) unless marker_root.nil?
        @failed = false
      end

      def mutate(operation:, item_count: nil)
        raise ArgumentError, "a mutation block is required" unless block_given?

        ensure_no_pending_mutation! if @marker_root
        token = before(operation:, item_count:)
        marker = nil
        after_attempted = false
        begin
          marker = create_pending_mutation!(token) if @marker_root
          result = yield
          status = result_status(result)
          after_attempted = true
          after(token, status:, item_count:)
          remove_pending_mutation!(marker) if marker
          result
        rescue StandardError
          if token && !after_attempted && !@failed
            after_attempted = true
            begin
              status = marker ? "ambiguous" : "failed"
              after(token, status:, item_count:)
              remove_pending_mutation!(marker) if marker
            rescue StandardError
              # A failed after-record must leave a durable marker for manual
              # reconciliation; never retry the side effect to repair tracing.
              raise
            end
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
          return result.last.success? ? "ok" : (@marker_root ? "ambiguous" : "failed")
        end
        return "ok" unless result.respond_to?(:ok?)
        return "ok" if result.ok?
        return "blocked" if result.respond_to?(:category) && result.category == :policy

        "failed"
      end

      def ensure_healthy!
        raise IOError, "mutation audit is halted after a lifecycle publication failure" if @failed
      end

      def ensure_no_pending_mutation!
        return unless File.exist?(@marker_root) || File.symlink?(@marker_root)
        raise IOError, "mutation recovery blocked: marker root is a symlink" if File.symlink?(@marker_root)

        pending = Dir.children(@marker_root).select { |name| name.start_with?(".pending-") }
        return if pending.empty?

        raise IOError, "mutation recovery blocked by incomplete Git audit; manual review required"
      rescue Errno::ENOENT
        nil
      rescue SystemCallError
        raise IOError, "mutation recovery blocked: cannot inspect pending Git audit markers"
      end

      def create_pending_mutation!(token)
        parent = File.dirname(@marker_root)
        raise IOError, "mutation marker parent is a symlink" if File.symlink?(parent)
        FileUtils.mkdir_p(@marker_root, mode: 0o700)
        raise IOError, "mutation marker root is a symlink" if File.symlink?(@marker_root)

        path = File.join(@marker_root, ".pending-#{token.audit_id}")
        File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |io|
          io.write(JSON.generate(audit_id: token.audit_id, operation: token.operation, started_at: token.started_at))
          io.write("\n")
          io.flush
          io.fsync
        end
        fsync_directory(@marker_root)
        path
      end

      def remove_pending_mutation!(path)
        File.delete(path) if File.exist?(path) || File.symlink?(path)
        fsync_directory(@marker_root)
        true
      end

      def fsync_directory(path)
        File.open(path, File::RDONLY) { |io| io.fsync }
      rescue Errno::EINVAL, Errno::EISDIR, NotImplementedError
        nil
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
        # Any other root is a tree /fix is repairing. Its receipts go under its
        # .master/, which every checkout ignores: a runtime/ dropped into that
        # tree reads as a new excluded file, changes the plan's exclusion digest
        # each pass and resets the loop's stagnation and cycle counters.
        telemetry_root = if canonical_roots.include?(@root) && defined?(Master::ROOT)
                           Master::ROOT
                         else
                           File.join(@root, ".master")
                         end
        event_log = Master::Trace::Log::Event.new(root: telemetry_root)
        Master::Trace::EventBus.new(event_log:)
      end
    end
  end
end
