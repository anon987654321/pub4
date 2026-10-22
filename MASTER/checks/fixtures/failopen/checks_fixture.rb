# frozen_string_literal: true

require_relative "../../support/check_result"

module Deploy
  # Checks that exist only to be run by RAILS/test/check_failopen_test.rb through
  # the real runner. Not registered in checks.yml; reachable only via CHECKS_FILE.
  module FailOpenFixtures
    class PassingCheck
      def self.run
        CheckResult.new.checked!
      end
    end

    # Raises the way a check actually breaks here: not a deliberate `raise` in the
    # check's own logic, but a method call on something that turned out to be nil
    # after a refactor elsewhere. NoMethodError is a StandardError; the
    # `missing_class` row in the fixture registry covers the NameError half, and
    # a moved `require` covers ScriptError.
    class RaisingCheck
      def self.run
        nil.this_check_was_refactored_out_from_under_me
      end
    end
  end
end
