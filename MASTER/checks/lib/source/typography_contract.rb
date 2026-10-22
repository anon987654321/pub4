# frozen_string_literal: true

require_relative "../../support/check_result"
require_relative "../../../tools/typography_lint"

module Deploy
  # Source typography is a contract, not a mood board. The browser remains the
  # authority for geometry; this check catches the declarations that would make
  # the rendered surface unable to honor the declared typographic profile.
  class TypographyContractCheck
    def self.run
      root = File.expand_path("../../../..", __dir__)
      lint = Operator::TypographyLint.new(root:)
      result = CheckResult.new

      lint.findings.each do |finding|
        result.fail(
          "typography_contract: #{finding.file}:#{finding.line} #{finding.kind}: #{finding.message}",
          severity: :soft,
        )
      end

      if lint.stylesheets.empty?
        result.inconclusive!("typography_contract: no stylesheets reached")
      else
        result.checked!(lint.stylesheets.size)
        result.warn("typography_contract: #{lint.stylesheets.size} stylesheets, #{lint.findings.size} contract finding(s)")
      end

      result
    end
  end
end
