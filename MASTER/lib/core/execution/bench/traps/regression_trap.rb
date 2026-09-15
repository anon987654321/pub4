# frozen_string_literal: true

module Master::Core::Execution
  # RegressionTrap — a controlled failure scenario used to test the 
  # AdversarialRegressionCorpus.
  #
  # It simulates a specific failure mode (e.g., a "False Completion")
  # to ensure the system detects it as a regression.
  class RegressionTrap
    attr_reader :id, :signature, :payload

    def initialize(id:, signature:, payload:)
      @id = id
      @signature = signature
      @payload = payload
    end

    # Simulates the output of a model that is regressing.
    def execute
      # Returns a result that matches the failure signature
      @payload
    end
  end
end
