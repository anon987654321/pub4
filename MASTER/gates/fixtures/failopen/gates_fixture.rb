# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  # Gates that exist only to be run by RAILS/test/gate_failopen_test.rb through
  # the real runner. Not registered in gates.yml; reachable only via GATES_FILE.
  module FailOpenFixtures
    class PassingGate
      def self.run
        GateResult.new.checked!
      end
    end

    # Raises the way a gate actually breaks here: not a deliberate `raise` in the
    # gate's own logic, but a method call on something that turned out to be nil
    # after a refactor elsewhere. NoMethodError is a StandardError; the
    # `missing_class` row in the fixture registry covers the NameError half, and
    # a moved `require` covers ScriptError.
    class RaisingGate
      def self.run
        nil.this_gate_was_refactored_out_from_under_me
      end
    end
  end
end
