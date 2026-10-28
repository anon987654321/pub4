# frozen_string_literal: true

module Master
  module Fix
    # The style stage of the /fix pass — the typographic law's audit half.
    #
    # laws.yml#typography sets the marks; Renderer#beautify sets them on the
    # way out; this audit reads the operator-facing strings that produce the
    # rest. It scans the trees that speak to a person (cli, voice, trace) for
    # the mechanical lapses: three ASCII dots where one true ellipsis belongs,
    # and the double-hyphen dash that stands in for an em dash in prose. Flags
    # ("--dry-run"), globs and paths are exempt by shape, so a finding is a
    # sentence that reached a person wearing the wrong mark.
    class TypographyAudit
      SCOPE = %w[lib/cli lib/voice lib/trace].freeze
      # A word may stand directly before the dots — "waiting..." is the case
      # that matters — but a digit, a slash or a dot on either side marks a
      # range ("0...6"), a path or a glob ("lib/..."), and those keep their
      # dots. Git's own range syntax ("HEAD...@{u}") keeps its dots the same way.
      ASCII_ELLIPSIS = /(?<![.\d\/])\.{3}(?![.\d\/@])/.freeze
      PROSE_DOUBLE_DASH = /(?<=\s)--(?=\s)/.freeze
      STRING_LITERAL = /"([^"\n]{6,300})"/.freeze
      # Where a machine reads the line, the marks stay literal: fixtures that
      # demonstrate the wrong mark, and usage notation ("<path>...") that
      # follows the man-page convention.
      EXEMPT_MARKERS = %w[bad: fixtures example: usage <path>].freeze
      MAX_FINDINGS = 40

      Finding = Data.define(:file, :line, :kind, :snippet)

      attr_reader :root

      def initialize(root:)
        @root = root.to_s
      end

      def call
        findings = SCOPE.flat_map { |dir| audit_dir(File.join(@root, dir)) }
        report(findings)
      rescue StandardError => e
        "style0: audit unavailable, #{e.class}: #{e.message}"
      end

      private

      def audit_dir(dir)
        return [] unless File.directory?(dir)

        Dir.glob(File.join(dir, "**", "*.rb")).sort.flat_map { |file| audit_file(file) }
      end

      def audit_file(file)
        relative = file.delete_prefix("#{@root}/")
        File.readlines(file, chomp: true).each_with_index.filter_map do |line, index|
          next if line.strip.start_with?("#")
          next if EXEMPT_MARKERS.any? { |marker| line.include?(marker) }

          text = line.scan(STRING_LITERAL).map(&:first).join(" ")
          next if text.empty?

          kind = violation_kind(text)
          next unless kind

          Finding.new(file: relative, line: index + 1, kind:, snippet: text[0, 80])
        end
      rescue StandardError
        []
      end

      def violation_kind(text)
        return "ascii_ellipsis" if text.match?(ASCII_ELLIPSIS)
        return "prose_double_dash" if text.match?(PROSE_DOUBLE_DASH)

        nil
      end

      def report(findings)
        return "style0: clean, #{scoped_line}" if findings.empty?

        counted = findings.group_by(&:kind).transform_values(&:size)
          .map { |kind, count| "#{count} #{kind.tr('_', ' ')}" }
          .join(", ")
        head = "style0: #{findings.size} findings, #{counted}"
        listed = findings.first(MAX_FINDINGS).map { |f| "#{f.file}:#{f.line} #{f.kind} — #{f.snippet}" }
        ([head] + listed + (findings.size > MAX_FINDINGS ? ["style0: #{findings.size - MAX_FINDINGS} more"] : [])).join("\n")
      end

      def scoped_line
        SCOPE.join(" ")
      end
    end
  end
end
