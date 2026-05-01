# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class ThreadSafetyRule < Rule
        # Dir.chdir is process-wide; breaks concurrent threads using different roots.
        DIR_CHDIR     = /\bDir\.chdir\b/
        # String-interpolated shell calls risk injection and hide argument boundaries.
        SHELL_INTERP  = /(?:system|`|IO\.popen|Open3\.\w+)\s*\(?\s*["'][^"']*#\{/
        # Prism.parse freeze: kwarg dropped in Ruby 3.4.
        PRISM_FREEZE  = /Prism\.parse\([^)]*freeze:\s*(?:true|false)/

        def initialize
          super
          @id          = "thread_safety"
          @description = "Detect thread-unsafe patterns: Dir.chdir, shell interpolation, dropped kwargs"
          @severity    = :error
          @axiom_tags  = %i[FAIL_VISIBLY EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          scan_lines(code, DIR_CHDIR,
            message: "Dir.chdir is process-wide and thread-unsafe; use -C flag or File.expand_path") +
          scan_lines(code, SHELL_INTERP,
            message: "shell interpolation risks injection; use Open3.capture2e with arg array") +
          scan_lines(code, PRISM_FREEZE,
            message: "Prism.parse freeze: kwarg removed in Ruby 3.4; drop it")
        end
      end
    end
  end
end
