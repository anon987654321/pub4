# frozen_string_literal: true

# Compatibility entry point. The implementation and coordinator identity live
# under Fix::Kernel; legacy callers keep the historical require path and constant.
require_relative "kernel"
require_relative "kernel/convergence_adapter"

module Master
  module Fix
    remove_const(:FixLoop) if autoload?(:FixLoop, false)
    const_set(:FixLoop, Kernel::ConvergenceAdapter) unless const_defined?(:FixLoop, false)
  end
end
