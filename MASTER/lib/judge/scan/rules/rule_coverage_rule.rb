# frozen_string_literal: true

module Master
  module Judge
  module Scan
    module Rules
      # Every Rule subclass must have a matching test file; gaps mean untested enforcement.
      class RuleCoverageRule < Rule
        def self.auto_build? = false

        def initialize(root:)
          super()
          @id = "rule_coverage"
          @description = "Rule subclass has no corresponding test file"
          @severity = :warning
          @auto_fix = false
          @rule_tags = %i[TEST_COVERAGE]
          @root = root
          @test_dir = File.join(root, "test")
        end

        def check(code, path:)
          return [] unless path.include?("/judge/scan/rules/") && path.end_with?("_rule.rb")

          base = File.basename(path, ".rb")
          test_glob = File.join(@test_dir, "**", "#{base}_test.rb")
          return [] if Dir.glob(test_glob).any?

          [finding(line: 1, message: "rule_coverage: no test file found for #{base}")]
        end
      end
    end
  end
  end
end
