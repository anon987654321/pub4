# frozen_string_literal: true

# Compatibility constant for legacy callers. The implementation lives under
# Kernel so the production repair policy has one canonical namespace.
require_relative "kernel"
require_relative "kernel/repair_adapter"

module Master
  module Fix
    RepairLoop = Kernel::RepairAdapter unless const_defined?(:RepairLoop, false)
  end
end
