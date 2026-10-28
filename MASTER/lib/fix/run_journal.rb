# frozen_string_literal: true

# Compatibility entry point. The implementation and persisted schema are
# owned by Fix::Kernel::LifecycleJournal.
require_relative "kernel"

module Master
  module Fix
    remove_const(:RunJournal) if autoload?(:RunJournal, false)
    const_set(:RunJournal, Kernel::LifecycleJournal) unless const_defined?(:RunJournal, false)
  end
end
