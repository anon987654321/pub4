# frozen_string_literal: true

module Master::Core::Execution
  # ExternalWorkMachine — a standardized harness for executing tasks outside
  # the core loop (e.g., cloud deployments, external API integrations).
  #
  # Flow: Preflight -> Auth -> Execute -> Verify
  class ExternalWorkMachine
    attr_reader :context, :status

    def initialize(context:)
      @context = context
      @status = :idle
    end

    # Executes the full work cycle
    def run(operation, params = {})
      @status = :preflight
      return Master::Result.err("preflight failed", category: :infrastructure) unless preflight(operation, params)

      @status = :auth
      return Master::Result.err("auth failed", category: :validation) unless authenticate(operation)

      @status = :execute
      result = execute(operation, params)
      # If execute returns a Result::Err, return it immediately
      return result if result.respond_to?(:ok?) && !result.ok?

      @status = :verify
      verification = verify(operation, result)
      return verification unless verification.ok?

      @status = :completed
      Master::Result.ok(result)
    rescue StandardError => e
      # Only mark as failed if it wasn't already handled by a Result::Err
      @status = :failed unless @status == :verify || @status == :execute
      Master::Result.err("external work failed: #{e.message}", category: :infrastructure)
    end

    private

    def preflight(_operation, _params)
      # Check if required tools/env are present
      # Implementation depends on the operation
      true
    end

    def authenticate(_operation)
      # Resolve credentials from container/vault
      true
    end

    def execute(operation, _params)
      # The actual external call (e.g., via Io::Exec or an API client)
      # For now, we return a success result
      Master::Result.ok("executed #{operation}")
    end

    def verify(_operation, _result)
      # Verify the side-effect of the execution
      Master::Result.ok(true)
    end
  end
end
