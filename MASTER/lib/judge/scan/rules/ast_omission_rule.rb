# frozen_string_literal: true

module Master
  module Judge
  module Scan
  module Rules
  # Detects methods/classes/modules present in recent git history but absent now.
  # Wraps CommitGuard as a standard scan Rule so it runs in the scanner pipeline.
  class AstOmissionRule < Rule
    def self.auto_build? = false

    def initialize(root: Dir.pwd, depth: CommitGuard::DEFAULT_DEPTH)
      super()
      @id = "ast_omission"; @description = "symbol dropped vs recent commits"
      @severity = :warning; @rule_tags = %i[COMPLETENESS]; @auto_fix = false
      @guard = CommitGuard.new(root:, depth:)
    end

    def check(code, path:)
      return [] unless path.to_s.end_with?(".rb")
      omissions = @guard.check(paths: [File.basename(path)])
      omissions.map { |o| finding(line: 1, message: "#{o.type} #{o.name} dropped (last seen #{o.last_seen_at})") }
    rescue StandardError => _e
      []
    end
  end
  end
  end
  end
end
