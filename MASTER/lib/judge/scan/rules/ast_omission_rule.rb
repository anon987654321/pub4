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
            @root = File.expand_path(root)
            @guard = CommitGuard.new(root: @root, depth:)
          end

          def check(_code, path:)
            return [] unless path.to_s.end_with?(".rb")

            rel = relativize(path)
            return [] unless rel

            omissions = @guard.check(paths: [rel])
            omissions.map { |o| finding(line: 1, message: "#{o.type} #{o.name} dropped (last seen #{o.last_seen_at})") }
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "ast_omission_rule.check", event_bus: nil)
            []
          end

          private

          def relativize(path)
            full = File.expand_path(path)
            prefix = @root + File::SEPARATOR
            full.start_with?(prefix) ? full.delete_prefix(prefix) : File.basename(full)
          end
        end
      end
    end
  end
end
