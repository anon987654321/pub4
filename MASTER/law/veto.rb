# frozen_string_literal: true

module Master
  module Review
    module Scan
      module Laws
        # Executes veto-pattern declarations owned by data/laws.yml; this is an enforcement adapter, not another Law catalogue.
        #
        # A veto is the severity above error, and this was the one rule in the
        # population with no exemption of any kind — so it read the scanner's own
        # rule sources as conduct where every registered twin of these patterns
        # skips that directory by name. All four of its findings under lib/ and
        # law/ were worked examples: the work marker TODO_FIXME and
        # NO_TODO_IN_VIEWS each carry, SQL_INJECTION's interpolated query and the
        # quoted fix beside it. Only the `fires:`/`does_not_fire:` lines are
        # blanked, not the directory, so a real secret or shell interpolation in
        # a rule file still vetoes.
        class VetoPatternLaw < Detector


          def initialize(root: Master::ROOT)
            super()
            @patterns = load_patterns(root)
          end

          def check(code, path:)
            return [] if @patterns.empty?

            @patterns.flat_map do |name, spec|
              detect = spec["detect"]
              next [] unless detect

              regex = detect.is_a?(String) ? Regexp.new(detect) : detect
              # unfinished is the one pattern that means to read comments, because
              # that is where a work marker lives. Every other veto is about code,
              # and a comment describing a shell interpolation is documentation.
              # (Written without naming the markers, since this rule reads it.)
              source = spec["reads_comments"] ? code : without_comment_lines(code)
              source = without_law_fixtures(source) if path.to_s.match?(%r{/law/[^/]+\.rb\z})
              scan_lines(source, regex, message: "veto: #{name} — #{spec["apply"] || "blocked"}")
            end
          end

          private

          # #check returns [] for every file when the pattern set is empty,
          # which reads as a tree with no veto violations. An unreadable
          # laws.yml retires every veto at once, so say so.
          def load_patterns(root)
            (Master.load_laws(root:) || {}).fetch("veto_patterns", {})
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "VetoPatternLaw.load_patterns", severity: :load_bearing)
            raise
          end
        end

        ::Law.define(:veto_patterns) do
          detector VetoPatternLaw
          fix "Unconditional merge blockers from laws.yml veto_patterns"
          proved_by "test/test_veto_pattern_law.rb"
        end

      end
    end
  end
end
