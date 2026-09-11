# frozen_string_literal: true

# Which `scan: intentional` markers still excuse a finding, and which excuse
# nothing.
#
# `law/practice.rb` declares EXEMPTIONS_EXPIRE — an allowlist entry, baseline row
# or opt-out that outlives its subject is a hole in a gate nobody can see,
# because the thing it excuses is invisible. The tree carries 143 of these
# markers across 90 files and nothing checked a single one. Declared conduct with
# no detector is the defect this repo names most often, and this is the detector.
#
# The method is a difference rather than a lookup: run every mechanical and
# lexical rule over a file as it stands, run them again with its markers blanked,
# and the findings that appear are what the markers hold back. A marker with
# something behind it is doing its job; a marker with nothing behind it excuses
# nothing.
#
#   ruby MASTER/tools/stale_exemptions.rb
#   ruby MASTER/tools/stale_exemptions.rb --json
#   ruby MASTER/tools/stale_exemptions.rb --all   # list the live ones too
#
# The first version asked the narrower question — is there a finding *under the
# marked line* — and answered it wrongly twice, in opposite ways. A law whose
# subject is an absence reads the marker off the raw text through `absent`,
# because blanking a line cannot make a missing `set -euo pipefail` present; that
# called dilla's two shell markers stale while STRICT_MODE_ZSH's own comment
# names one of them as the reason `absent` exists. And a registry rule can grep
# the whole file and report at line 1 — ERB_HTML_SAFE does — so the 2FA QR code's
# exemption works file-wide from line 4. The difference sees both.
#
# One limit stands, and the rule that would close it is not worth having. A
# marker can be *named* rather than used: this repo's documentation, rule
# fixtures and false-positive tests all contain the string. `quoted?` separates
# them — backticked, inside a string literal, or nested inside another comment of
# the same language — and lets exactly one through, web_rules.rb:77, which writes
# `/* scan: intentional */` inside a `#` comment. A filter for a foreign opener
# after the line's own one caught it and re-read every ERB `<%#` as nesting,
# dropping twenty-six live markers. A disclosed false positive beats a filter
# that loses what it was built to count.

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
    # The default for a caller that has no path to read a language from.
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

    # What the marker sits beside. Empty means the line is comment all the way
    # through, which is what makes such a marker unable to excuse anything —
    # scan_lines skips the line the marker is on, and the code it was written
    # about is the next one. A line with no opener at all is inside a block
    # comment opened above it, which is the same answer.
    def code_in(line, openers) = without_marker_comment(line, openers).strip

    def reason_in(line)
      line[/#{MARKER}\s*[—-]\s*(.+?)\s*(?:\*\/|%>|-->|\z)/, 1].to_s
    end

    # The marker removed and the line kept, so every line number still points
    # where it did. This is Rule#without_scan_marker, which cannot be called from
    # here — it is a private instance method on a rule.
    #
    # Through the same language-aware openers the rest of this reads, because the
    # naive `rindex` over every opener cut `  <%# scan: … ` at the `#` and left a
    # bare `<%` behind. That opened an ERB tag over the rest of the comment, and
    # ERB_HTML_SAFE's guard — which looks for a sanitizing call inside a tag —
    # then matched the word "sanitize" in the comment's second line. The 2FA
    # exemption read as stale because the strip built the thing that silenced it.
    def unmarked(text, openers = ANY_OPENER)
      text.each_line.map { |line| MARKER.match?(line) ? "#{without_marker_comment(line, openers)}\n" : line }.join
    end

    # The marker's comment cut out and the rest of the line kept, head and tail
    # both. The tail is the half that matters and the half this first got wrong:
    # amber's logo closes its ERB comment and carries a `<textPath>` on the same
    # line, so cutting from the opener to end-of-line deleted the markup three
    # rules were about to flag — and the marker read as stale because the strip
    # removed its subject along with it.
    def without_marker_comment(line, openers)
      at = line.index(MARKER)
      spots = opener_positions(line[0, at], openers)
      return "" if spots.empty?

      opener = spots.max
      token = openers.find { |candidate| line[opener, candidate.length] == candidate }
      closer = CLOSERS[token] && line.index(CLOSERS[token], at)
      tail = closer ? line[(closer + CLOSERS[token].length)..] : ""
      "#{line[0, opener]}#{tail}".rstrip
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
        held = suppressed(path)
        hits.map do |line, reason, code|
          Exemption.new(path:, line:, reason:, code:, rules: held[line] + held[:file])
        end
      end
    end

    # What this file's markers hold back: every rule run over the file as it
    # stands and again with the markers blanked, and the difference.
    #
    # Asking only "is there a finding under the marked line" answered the wrong
    # question twice. A law whose subject is an absence reads the marker off the
    # raw text through `absent`, because blanking a line cannot make a missing
    # `set -euo pipefail` present. And a registry rule can grep the whole file
    # for the marker and report at line 1 — ERB_HTML_SAFE does, so the 2FA QR
    # code's exemption is file-wide and sits on line 4. Both were called stale.
    #
    # A difference at a marked line belongs to that marker. A difference
    # anywhere else is file-scope: the rule read the whole file, so which of its
    # markers did the work cannot be told apart, and every marker in the file
    # carries it. That over-reports live and never over-reports stale, which is
    # the safe direction for a list a person has to read.
    def suppressed(path)
      raw = File.read(path, encoding: "UTF-8").scrub
      openers = openers_for(path)
      before = findings_by_line(path, raw)
      after = findings_by_line(path, unmarked(raw, openers))
      held = Hash.new { |hash, key| hash[key] = [] }
      marked_lines = marked.fetch(path, []).map(&:first)
      after.each do |line, rules|
        gained = rules - before.fetch(line, [])
        next if gained.empty?

        key = marked_lines.include?(line) ? line : :file
        held[key].concat(key == :file ? gained.map { |rule| "#{rule}(file)" } : gained)
      end
      held
    end

    def findings_by_line(path, text)
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
