# frozen_string_literal: true

require "digest"
require "json"
require "securerandom"
require_relative "../execution/contract"

module Master
  module Trace
    # A strict, argument-private receipt around a tool invocation. The before
    # receipt must be durable before the caller invokes the tool. An unknown or
    # unrecorded after receipt quarantines the same tool/arguments until an
    # operator records a reconciliation outcome.
    class ToolObserver
      BEFORE_EVENT = "tool:execution:before".freeze
      AFTER_EVENT = "tool:execution:after".freeze
      RECONCILED_EVENT = "tool:execution:reconciled".freeze

      STATUSES = %w[success error blocked unknown_outcome].freeze
      RECONCILIATIONS = %w[confirmed_success confirmed_failure safe_to_retry still_unknown].freeze
      MAX_ARGUMENT_BYTES = 16 * 1024 * 1024
      MAX_ARGUMENT_NODES = 100_000
      MAX_ARGUMENT_DEPTH = 64
      MAX_PENDING = 256
      MAX_COMPLETED = 4_096

      Invocation = Data.define(:invocation_id, :tool, :tier, :arguments_digest, :arguments_bytes) do
        def to_h
          {
            schema_version: 1,
            invocation_id:,
            tool:,
            tier:,
            arguments_digest:,
            arguments_bytes:
          }
        end
      end

      class UnknownOutcome < StandardError
        attr_reader :invocation_id

        def initialize(invocation_id:, message:)
          @invocation_id = invocation_id
          super(message)
        end
      end

      def initialize(bus:)
        unless bus.respond_to?(:publish_required)
          raise ArgumentError, "ToolObserver requires a bus with publish_required"
        end

        @bus = bus
        @mutex = Mutex.new
        @pending = {}
        @unresolved = {}
        @completed = {}
      end

      # A failure to persist this event means the external operation must not
      # begin. IDs and argument fingerprints are reserved before publishing so
      # concurrent duplicate IDs cannot pass the gate.
      def before(tool:, tier:, args:, invocation_id: SecureRandom.uuid)
        identity = build_identity(tool:, tier:, args:, invocation_id:)
        key = identity.invocation_id
        sig = signature(identity)

        @mutex.synchronize do
          if (unknown = @unresolved[sig])
            raise UnknownOutcome.new(
              invocation_id: unknown.invocation_id,
              message: "previous tool outcome is unresolved; verify state and reconcile before retrying"
            )
          end
          raise ArgumentError, "duplicate tool invocation identity" if @pending.key?(key) || @completed.key?(key)
          raise IOError, "too many active tool invocations" if @pending.size >= MAX_PENDING

          @pending[key] = identity
        end

        begin
          @bus.publish_required(BEFORE_EVENT, identity.to_h)
        rescue StandardError
          @mutex.synchronize { @pending.delete(key) if @pending[key] == identity }
          raise
        end

        identity
      end

      # Every after attempt is tied to exactly the original before envelope.
      # If validation or persistence fails after the tool may have run, preserve
      # the pending receipt and block a new invocation with the same arguments.
      def after(identity: nil, invocation_id: nil, tool:, tier:, args:, status:,
                elapsed_ms:, result_bytes: nil, error: nil)
        id = identity ? identity.invocation_id : Master::Execution::Contract.token!(invocation_id, "invocation id")
        expected = @mutex.synchronize { @pending[id] }
        raise ArgumentError, "tool after-event requires a matching before-event" unless expected

        begin
          candidate = build_identity(tool:, tier:, args:, invocation_id: id)
          raise ArgumentError, "tool after-event identity differs from before-event" unless candidate == expected

          outcome = status.to_s
          raise ArgumentError, "unknown tool outcome status" unless STATUSES.include?(outcome)

          elapsed = non_negative_integer(elapsed_ms, "elapsed_ms")
          bytes = result_bytes.nil? ? nil : non_negative_integer(result_bytes, "result_bytes")
          @mutex.synchronize { @unresolved[signature(expected)] = expected } if outcome == "unknown_outcome"
          payload = expected.to_h.merge(
            status: outcome,
            elapsed_ms: elapsed,
            result_bytes: bytes,
            retry_requires_reconciliation: outcome == "unknown_outcome"
          ).compact
          payload.merge!(Master::Execution::Contract.diagnostic_fields(error)) unless error.nil?
          @bus.publish_required(AFTER_EVENT, payload)
        rescue StandardError => e
          mark_unresolved(expected)
          raise UnknownOutcome.new(
            invocation_id: id,
            message: "tool after-receipt unavailable; verify current state and reconcile before retrying (#{e.class})"
          )
        end

        @mutex.synchronize do
          @pending.delete(id)
          remember_completed(id)
          sig = signature(expected)
          if outcome == "unknown_outcome"
            @unresolved[sig] = expected
          elsif @unresolved[sig]&.invocation_id == id
            @unresolved.delete(sig)
          end
        end

        expected
      end

      # Explicitly clears the in-process quarantine only after a durable
      # reconciliation record has been written. This is not automatic proof:
      # evidence_ref must point to the operator's actual verification.
      def reconcile!(tool:, args:, evidence_ref:, outcome:, invocation_id: nil)
        name = safe_name(tool, "tool name")
        args_json = canonical_arguments(args)
        sig = [name, Digest::SHA256.hexdigest(args_json)].freeze
        expected = @mutex.synchronize { @unresolved[sig] }
        raise ArgumentError, "no unresolved invocation matches these arguments" unless expected
        if invocation_id && expected.invocation_id != Master::Execution::Contract.token!(invocation_id, "invocation id")
          raise ArgumentError, "reconciliation invocation identity mismatch"
        end

        decision = outcome.to_s
        raise ArgumentError, "unknown reconciliation outcome" unless RECONCILIATIONS.include?(decision)
        reference = evidence_ref.to_s
        unless Master::Execution::Contract::REFERENCE.match?(reference)
          raise ArgumentError, "reconciliation evidence_ref must be a bounded evidence reference"
        end

        @bus.publish_required(
          RECONCILED_EVENT,
          expected.to_h.merge(reconciliation: decision, evidence_ref: reference)
        )

        unless decision == "still_unknown"
          @mutex.synchronize do
            @unresolved.delete(sig) if @unresolved[sig]&.invocation_id == expected.invocation_id
            @pending.delete(expected.invocation_id)
            remember_completed(expected.invocation_id)
          end
        end

        expected
      end

      private

      def build_identity(tool:, tier:, args:, invocation_id:)
        id = Master::Execution::Contract.token!(invocation_id, "invocation id")
        name = safe_name(tool, "tool name")
        level = safe_name(tier, "tool tier")
        document = canonical_arguments(args)
        Invocation.new(
          invocation_id: id,
          tool: name,
          tier: level,
          arguments_digest: Digest::SHA256.hexdigest(document),
          arguments_bytes: document.bytesize
        )
      end

      def safe_name(value, field)
        raw = value.to_s
        raise ArgumentError, "#{field} cannot be empty" if raw.empty?
        raise ArgumentError, "#{field} is too long" if raw.bytesize > 1_024

        normalized = raw.gsub(/[^a-zA-Z0-9._:-]/, "_")
        normalized = "tool.#{normalized}" unless normalized.match?(/\A[a-zA-Z0-9]/)
        if normalized != raw || normalized.bytesize > 160
          normalized = "#{normalized.byteslice(0, 120)}.#{Digest::SHA256.hexdigest(raw)[0, 32]}"
        end
        Master::Execution::Contract.token!(normalized, field)
      end

      def canonical_arguments(args)
        normalized = normalize_json(args, depth: 0, nodes: [0])
        document = JSON.generate(normalized)
        raise ArgumentError, "tool arguments exceed the audit byte limit" if document.bytesize > MAX_ARGUMENT_BYTES

        document
      rescue JSON::GeneratorError, EncodingError => e
        raise ArgumentError, "tool arguments cannot be represented safely: #{e.class}"
      end

      def normalize_json(value, depth:, nodes:)
        raise ArgumentError, "tool arguments exceed the audit nesting limit" if depth > MAX_ARGUMENT_DEPTH
        nodes[0] += 1
        raise ArgumentError, "tool arguments exceed the audit node limit" if nodes[0] > MAX_ARGUMENT_NODES

        case value
        when Hash
          normalized = {}
          value.each do |key, child|
            field = case key
                    when String then key
                    when Symbol then key.to_s
                    else raise ArgumentError, "tool argument keys must be strings or symbols"
                    end
            raise ArgumentError, "duplicate normalized tool argument key" if normalized.key?(field)

            normalized[field] = normalize_json(child, depth: depth + 1, nodes:)
          end
          normalized.sort_by { |key, _| key }.to_h
        when Array
          value.map { |child| normalize_json(child, depth: depth + 1, nodes:) }
        when String, Integer, TrueClass, FalseClass, NilClass
          value
        when Symbol
          value.to_s
        when Float
          raise ArgumentError, "non-finite tool argument number" unless value.finite?

          value
        else
          raise ArgumentError, "unsupported tool argument value: #{value.class}"
        end
      end

      def non_negative_integer(value, field)
        unless value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A\d+\z/))
          raise ArgumentError, "#{field} must be a non-negative integer"
        end

        number = value.is_a?(Integer) ? value : value.to_i
        raise ArgumentError, "#{field} must be non-negative" if number.negative?

        number
      end

      def signature(identity)
        [identity.tool, identity.arguments_digest].freeze
      end

      def mark_unresolved(identity)
        @mutex.synchronize { @unresolved[signature(identity)] = identity }
      end

      def remember_completed(id)
        @completed[id] = true
        @completed.shift while @completed.size > MAX_COMPLETED
      end
    end
  end
end
