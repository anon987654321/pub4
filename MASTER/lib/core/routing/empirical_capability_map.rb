# frozen_string_literal: true

module Master::Core::Routing
  # EmpiricalCapabilityMap — the verified profile of model behavior. Named for
  # its file, in the namespace its file sits in, so the autoloader finds it.
  #
  # It extends the basic CapabilityMap by adding "Failure Mode" tracking
  # (e.g., false-completion rate, tool-error rate).
  class EmpiricalCapabilityMap < CapabilityMap
    attr_reader :failure_modes

    def initialize
      super
      @failure_modes = Hash.new { |h, k| h[k] = Hash.new(0) }
    end

    def record_failure(model_id, mode)
      @failure_modes[model_id][mode] += 1
    end

    def failure_rate(model_id, mode)
      total = @failure_modes[model_id].values.sum
      return 0.0 if total == 0
      @failure_modes[model_id][mode].to_f / total
    end
  end
end
