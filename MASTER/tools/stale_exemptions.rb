# frozen_string_literal: true

# Which `scan: intentional` markers still excuse a finding, and which excuse
# nothing.
#
# `law/practice.rb` declares EXEMPTIONS_EXPIRE — an allowlist entry, baseline row
# or opt-out that outlives its subject is a hole in a gate nobody can see,
# because the thing it excuses is invisible. The tree carries 143 of these
# markers across 89 files and nothing checked a single one. Declared conduct with
# no detector is the defect this repo names most often, and this is the detector.
#
# The method is the marker's own definition. Rule#scan_lines skips a line
# carrying the marker; so strip every marker from a file, run the rules over what
# is left, and see whether anything now lands on the marked line. A marker with a
# finding under it is doing its job. A marker with nothing under it excuses
# nothing.
#
#   ruby MASTER/tools/stale_exemptions.rb
#   ruby MASTER/tools/stale_exemptions.rb --json
#   ruby MASTER/tools/stale_exemptions.rb --all   # list the live ones too
#
# Two limits, both measured rather than assumed.
#
# A marker can be *named* rather than used: this repo's own documentation, rule
# fixtures and false-positive tests all contain the string, and a census that
# counts those reports thirteen stale exemptions that are prose. `quoted?`
# separates them — backticked, inside a string literal, or nested inside another
# comment of the same language — and every candidate of the first run was read by
# hand against it.
#
# It leaves exactly one through, and the rule that would catch it is not worth
# having: web_rules.rb:77 writes `/* scan: intentional */` inside a `#` comment,
# and a filter for a foreign opener after the line's own one re-read every ERB
# `<%#` as nesting and silently dropped twenty-six live markers. A disclosed
# false positive beats a filter that loses what it was built to count.
#
# And a law that fires on what is MISSING honours the marker by a different
# mechanism, which the strip method cannot see. Law#scan checks `absent` against
# the raw text before anything is stripped, because blanking a line cannot make
# an absent `set -euo pipefail` present. Three laws declare one —
# STRICT_MODE_ZSH, STRICT_LOADING_MISSING, RATE_LIMITING_MISSING — and the first
# run called dilla's two shell markers stale when STRICT_MODE_ZSH's own comment
# names one of them as the reason `absent` exists. A marker in a file an
# absence-based law applies to is live, and the census asks that question
# separately rather than inferring it from a line.

require "English"
require "json"

module Operator
  module StaleExemptions
    MASTER_DIR = File.expand_path("..", __dir__)
    ROOT = File.expand_path("..", MASTER_DIR)
    TREES = %w[MASTER RAILS OPENBSD STUDIO].freeze

    # The bare form only. `scan: intentional-colors` and `scan: intentional-important`
    # are file-head directives to one rule each, with their own semantics and
    # their own scope, and they are not what Rule#scan_lines reads.
    MARKER = /scan:\s*intentional\b(?!-)/

    # Per language, because `#` opens a comment in Ruby and is a hex colour in
    # SCSS. One flat list of every opener read
    # `background: #131921; // scan: intentional` as a marker nested inside a `#`
    # comment and dropped thirty live exemptions in brgen's stylesheets alone,
    # along with every Ruby line carrying a `#{}` interpolation before its marker.
    COMMENT_OPENERS = {
      ruby: ["#"], yaml: ["#"], zsh: ["#"], json: ["#"],
      javascript: ["//", "/*"], css: ["//", "/*"], scss: ["//", "/*"],
      html: ["<%#", "<!--"], markdown: ["<!--"],
    }.freeze
    CLOSERS = { "/*" => "*/", "<!--" => "-->", "<%#" => "%>" }.freeze # scan: intentional — a census of comment markers has to quote every language it reads
    # Only `unmarked` needs every opener at once: it strips markers from a file
    # whose language it has already decided is irrelevant to the strip.
    ANY_OPENER = COMMENT_OPENERS.values.flatten.uniq.freeze

    Exemption = Struct.new(:path, :line, :reason, :rules, :code, keyword_init: true) do
      def relative = path.delete_prefix("#{ROOT}/")
      def live? = !rules.empty?

      # A marker on a line with no code of its own cannot work at all: scan_lines
      # skips the line the marker is on, and the line it was written about is the
      # next one. Both cases in the tree are the tail of a multi-line comment.
      def misplaced? = !live? && code.empty?
      def shape = misplaced? ? "on a comment line, so no code line is skipped" : "excuses nothing"
      def to_s = "#{relative}:#{line}#{live? ? " #{rules.uniq.sort.join(",")}" : ""}"
    end

    module_function

    def master
      return if defined?(::Master::Review::Scan::InfraHelpers)

      require File.join(MASTER_DIR, "lib", "master")
      require File.join(MASTER_DIR, "lib", "review", "scan", "scanner")
    end

    def law
      unless defined?(::Law)
        master
        require File.join(MASTER_DIR, "law", "law")
      end
      ::Law.load_all(File.join(MASTER_DIR, "law")) if ::Law.rules.empty?
      ::Law.rules
    end

    # Asked of git for the same reason self_findings asks: the corpus is what the
    # repo tracks, and git prunes an ignored directory instead of descending it.
    def files
      master
      @files ||= begin
        listing = IO.popen(["git", "-C", ROOT, "ls-files", "-z", "--cached", "--others",
                            "--exclude-standard", "--", *TREES], &:read)
        raise "stale_exemptions: git ls-files failed in #{ROOT}" unless $CHILD_STATUS.success?

        extensions = Master::FILE_LANGUAGE_MAP.keys
        listing.split("\0").filter_map do |relative|
          next unless extensions.include?(File.extname(relative))

          path = File.join(ROOT, relative)
          path if File.file?(path)
        end.sort
      end
    end

    # Every marker in force, by file. A marker that is quoted rather than used is
    # not an exemption and is not counted.
    def marked
      @marked ||= files.each_with_object({}) do |path, found|
        lines = begin
          File.readlines(path, encoding: "UTF-8")
        rescue StandardError
          next
        end
        openers = openers_for(path)
        hits = lines.each_with_index.filter_map do |line, index|
          next unless MARKER.match?(line)
          next if quoted?(line, openers)

          [index + 1, reason_in(line), code_in(line, openers)]
        end
        found[path] = hits unless hits.empty?
      end
    end

    def openers_for(path)
      COMMENT_OPENERS.fetch(Master::FILE_LANGUAGE_MAP[File.extname(path)]&.to_sym, ["#"])
    end

    # The marker named rather than used. Backticks are how this repo writes it in
    # prose; an odd quote before it means a fixture string; an opener before the
    # marker's own opener means the marker sits inside somebody else's comment.
    def quoted?(line, openers)
      at = line.index(MARKER) or return false

      head = line[0, at]
      return true if head.include?("`")
      return true if head.count('"').odd? || head.count("'").odd?
      # Ruby's other string literals, which a quote count cannot see. This file's
      # own test fixtures are written in them.
      return true if head.match?(/%[qQwWi]?[({\[<]/)

      spots = opener_positions(head, openers)
      !spots.empty? && spots.min < spots.max
    end

    # Two `#` that are not comment openers: the one inside `<%#`, which is that
    # opener rather than a second within it, and the one in Ruby's `#{}`, which
    # opens an interpolation. Reading the first as nesting called every ERB marker
    # in RAILS prose; reading the second did the same to every Ruby line that
    # interpolates before its marker, Ground::Swallow's log rotation among them.
    def opener_positions(head, openers)
      openers.flat_map do |token|
        at = -1
        spots = []
        spots << at while (at = head.index(token, at + 1))
        next spots unless token == "#"

        spots.reject { |i| head[i - 2, 3] == "<%#" || head[i + 1] == "{" }
      end
    end

    # What the marker sits beside: the line with the marker's whole comment cut
    # out, head and tail both. Empty means the line is comment all the way
    # through, which is what makes such a marker unable to excuse anything —
    # scan_lines skips the line the marker is on, and the code it was written
    # about is the next one. The tail half matters: amber's logo closes its ERB
    # comment and then carries markup on the same line.
    def code_in(line, openers)
      at = line.index(MARKER)
      spots = opener_positions(line[0, at], openers)
      # No opener on this line means the marker continues a block comment opened
      # above it — a comment line, whatever the language.
      return "" if spots.empty?

      opener = spots.max
      token = openers.find { |candidate| line[opener, candidate.length] == candidate }
      closer = CLOSERS[token] && line.index(CLOSERS[token], at)
      tail = closer ? line[(closer + CLOSERS[token].length)..] : ""
      "#{line[0, opener]}#{tail}".strip
    end

    def reason_in(line)
      line[/#{MARKER}\s*[—-]\s*(.+?)\s*(?:\*\/|%>|-->|\z)/, 1].to_s
    end

    # The marker removed and the line kept, so every line number still points
    # where it did. This is Rule#without_scan_marker, which cannot be called from
    # here — it is a private instance method on a rule.
    def unmarked(text)
      text.each_line.map do |line|
        at = line.index(MARKER)
        next line unless at

        opener = ANY_OPENER.filter_map { |token| line.rindex(token, at) }.max
        opener ? "#{line[0, opener].rstrip}\n" : line
      end.join
    end

    def mechanical_rules
      @mechanical_rules ||= begin
        master
        # A rule that takes an agent is a semantic rule, and one model call per
        # file is not what a census of 97 files should cost.
        Master::Review::Scan::InfraHelpers.build_scanner(root: MASTER_DIR)
              .rules.reject { |rule| rule.respond_to?(:set_agent) }
      end
    end

    def exemptions
      @exemptions ||= marked.flat_map do |path, hits|
        by_line = findings_without_markers(path)
        absent = absence_laws_for(path)
        hits.map { |line, reason, code| Exemption.new(path:, line:, reason:, code:, rules: by_line[line] + absent) }
      end
    end

    # A law whose subject is an absence reads the marker off the raw text, so
    # stripping it proves nothing about whether the exemption is doing work. Any
    # such law that applies to this file is honouring the marker, file-wide.
    def absence_laws_for(path)
      language = Master::FILE_LANGUAGE_MAP[File.extname(path)]&.to_sym
      raw = File.read(path, encoding: "UTF-8").scrub
      law.each_value.select do |rule|
        rule.absent && rule.applies?(path, language) && raw.match?(rule.absent)
      end.map { |rule| "#{rule.id}(absent)" }
    end

    def findings_without_markers(path)
      text = unmarked(File.read(path, encoding: "UTF-8").scrub)
      language = Master::FILE_LANGUAGE_MAP[File.extname(path)]&.to_sym
      by_line = Hash.new { |hash, key| hash[key] = [] }
      mechanical_rules.each do |rule|
        Array(rule.check(text, path:)).each { |finding| by_line[finding[:line].to_i] << finding[:rule].to_s }
      rescue StandardError
        next
      end
      law.each_value do |rule|
        next if rule.semantic? || !rule.applies?(path, language)

        rule.scan(text, file: path).each { |hit| by_line[hit.line.to_i] << rule.id.to_s }
      rescue StandardError
        next
      end
      by_line
    end

    def report(argv)
      stale, live = exemptions.partition { |exemption| !exemption.live? }
      return puts(JSON.pretty_generate(json(stale, live))) if argv.include?("--json")

      puts "stale_exemptions: #{exemptions.size} markers in #{marked.size} files — #{live.size} live, #{stale.size} excusing nothing"
      stale.sort_by(&:to_s).each do |exemption|
        puts "  #{exemption.relative}:#{exemption.line}  #{exemption.shape}"
        puts "    #{exemption.reason}" unless exemption.reason.empty?
      end
      return unless argv.include?("--all")

      puts "stale_exemptions: live"
      live.sort_by(&:to_s).each { |exemption| puts "  #{exemption}" }
    end

    def json(stale, live)
      {
        "markers" => exemptions.size,
        "files" => marked.size,
        "live" => live.size,
        "stale" => stale.map { |e| { "path" => e.relative, "line" => e.line, "reason" => e.reason, "shape" => e.shape } },
      }
    end
  end
end

Operator::StaleExemptions.report(ARGV) if $PROGRAM_NAME == __FILE__
