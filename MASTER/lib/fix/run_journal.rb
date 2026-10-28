# frozen_string_literal: true

# Compatibility constant. The journal's implementation is owned by Fix::Kernel;
# callers can migrate from RunJournal to Kernel#lifecycle_journal independently.
require_relative "kernel/lifecycle_journal"

module Master
  module Fix
    RunJournal = Kernel::LifecycleJournal unless const_defined?(:RunJournal, false)
  end
end
