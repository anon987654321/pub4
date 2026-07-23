# frozen_string_literal: true

module Master
  module Review
    module Scan
      module Rules
        # Enforces "core stays lean" as a live check, not just an aspiration --
        # matches OpenClaw's explicit policy (VISION.md: "we are generally
        # slimming down core... bar for adding optional plugins to core is
        # intentionally high"). MASTER's own lib/-vs-core/ split has been an
        # ongoing, unresolved tension; this at least stops lib/ root itself
        # from silently accumulating new files with no deliberate decision.
        class LibRootDisciplineRule < Rule
          ALLOWED_ROOT_FILES = %w[
            builder.rb master.rb memory.rb pressure_engine.rb
            result.rb security_error.rb unwrap_error.rb
          ].freeze

          def self.auto_build? = false

          def initialize(root: Master::ROOT)
            super()
            @id = "LIB_ROOT_DISCIPLINE"
            @description = "new files shouldn't land directly in lib/ root"
            @severity = :warning
            @rule_tags = %i[ABSTRACTION ARCHITECTURE]
            @auto_fix = false
            @lib_root = File.join(root, "lib")
          end

          def check(_code, path:)
            return [] unless in_lib_root?(path)
            return [] if ALLOWED_ROOT_FILES.include?(File.basename(path))

            [finding(
              line: 1,
              message: "#{File.basename(path)} added directly to lib/ root — move it into a " \
                "subsystem folder, or add it to LibRootDisciplineRule::ALLOWED_ROOT_FILES if it's genuinely core",
            )]
          end

          private

          def in_lib_root?(path)
            path.to_s.end_with?(".rb") && File.dirname(File.expand_path(path)) == @lib_root
          end
        end
      end
    end
  end
end
