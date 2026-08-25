# frozen_string_literal: true

# law/ — the constitution as code.
#
# A law exists only as a triple: detector + a fixture it MUST flag + a fixture
# it MUST NOT flag. A law with no detector is documentation. A law with no bad
# fixture is unfalsifiable. A law with no good fixture has an unmeasured
# false-positive rate — the decorator-massacre failure mode. All three or it
# does not load. `rake dogfood` proves every law against its own fixtures and
# then runs every law over law/ itself; both must stay clean.
#
# Contract: `rake dogfood` is the archaeological audit. A capability that goes
# missing is a fixture that stops passing — nothing to compare by hand.
module Law
  Finding = Data.define(:id, :file, :line, :text)

  # A line-scoped detector reads code, and a comment naming a forbidden
  # construct is prose about it, not an instance of it — "# a bare rescue"
  # became an error-severity finding when FAIL_VISIBLY moved here from the
  # yaml bridge, which had learned this once already. Comment-leading lines
  # are skipped for the file's own comment syntax; a rule whose subject IS
  # comments (WHY_NOT_WHAT, TYPOGRAPHY_DISCIPLINE) declares `reads_comments
  # true`. Fixtures prove with file "-", which has no extension and so no
  # comment syntax — a fixture is always read whole.
  COMMENT_LEADERS = {
    ".rb" => ["#"], ".rake" => ["#"], ".gemspec" => ["#"],
    ".yml" => ["#"], ".yaml" => ["#"],
    ".zsh" => ["#"], ".sh" => ["#"], ".bash" => ["#"],
    ".js" => ["//", "/*"], ".ts" => ["//", "/*"], ".jsx" => ["//", "/*"], ".tsx" => ["//", "/*"],
    ".css" => ["/*"], ".scss" => ["//", "/*"], ".sass" => ["//", "/*"],
    ".html" => ["<!--"], ".htm" => ["<!--"], ".erb" => ["<!--"],
  }.freeze

  # `ask` is the semantic half: a rule whose subject cannot be matched by a
  # regex states the question instead, and the model answers it. It sits beside
  # `detect` rather than in a second file because a rule is one thing and its
  # detector kind is a property of it — the split across law/ and data/rules.yml
  # put 52 rules' detector in one file and their severity and fix text in
  # another, which is a shape no rename can make legible.
  #
  # bad/good stay required for both kinds. For `detect` they are proved by
  # running the regex at load. For `ask` they cannot be — no model call at boot —
  # so they are the prompt's own worked examples, carried into the question and
  # checkable offline by a task that has a model. A semantic rule with no
  # example of what it is looking for is the unfalsifiable shape this file
  # already refuses in the lexical case.
  # One real extension per language a law can declare, for proving a fixture the
  # way a subject is actually read. Ordered so the first match is the ordinary
  # case for that language rather than an alias of it.
  REALISTIC_EXTENSION = {
    ".rb" => "ruby", ".js" => "javascript", ".scss" => "scss", ".css" => "css",
    ".html" => "html", ".yml" => "yaml", ".sh" => "zsh", ".md" => "markdown", ".json" => "json"
  }.freeze

  MEMBERS = %i[id source severity languages scope path path_exclude absent detect ask practice fix bad good reads_comments].freeze
  Rule = Data.define(*MEMBERS) do
    # `path` takes a Regexp or a substring; `path_exclude` was already a Regexp,
    # and one member of a pair reading its argument the other way is a trap for
    # whoever writes the next law.
    def applies?(file, language)
      return false if path && !(path.is_a?(Regexp) ? file.match?(path) : file.include?(path))
      return false if path_exclude && file.match?(path_exclude)
      language.nil? || languages.empty? || languages.include?(language)
    end

    # A semantic rule has no detector to run here. It is carried to the model by
    # the semantic pass instead, so scanning it lexically must find nothing
    # rather than raise on a nil detect.
    def semantic? = !ask.nil?

    # Neither kind scans source: one is answered by a model, one binds behaviour.
    def scannable? = detect ? true : false

    def scan(text, file: "-")
      return [] unless scannable?

      scope == :file ? scan_file(text, file) : scan_lines(text, file)
    end

    # A rule proves itself before it may judge anything else.
    #
    # The reach half is proved too, because it was the half that broke:
    # NEVER_BATCH_DELETE declared `languages %i[ruby shell]` and no file can
    # carry the language "shell" — FILE_LANGUAGE_MAP emits "zsh" — so a law
    # written after a batch-delete incident could not read a single shell
    # script, and passed prove! every boot because prove! called scan directly
    # and never asked applies?. A declared language that nothing produces is a
    # rule aimed at nothing.
    def prove!
      # The reach check below applies to both kinds; only the detector half is
      # skipped for a semantic rule, because proving it needs a model and this
      # runs at boot. The fixtures are still required — Builder#build refuses
      # without them — they are simply proved by rake rather than by require.
      if scannable?
        raise ArgumentError, "#{id}: bad fixture not flagged" if scan(bad).empty?
        raise ArgumentError, "#{id}: good fixture flagged" unless scan(good).empty?

        prove_as_real_file!
      end

      unreachable = languages.map(&:to_s) - Master::FILE_LANGUAGE_MAP.values.uniq
      unless unreachable.empty?
        raise ArgumentError,
              "#{id}: declares language(s) #{unreachable.join(', ')} that FILE_LANGUAGE_MAP never produces"
      end
      self
    end

    private

    # The same two fixtures, read the way a real file is read.
    #
    # Above, they prove through file "-": no extension, so no comment syntax, so
    # the text is read whole. A real subject has an extension and its comment
    # lines are blanked before the detector sees them. Those are different
    # inputs, and a rule can be right about one and wrong about the other.
    #
    # FROZEN_STRING_LITERAL asks whether a file opens with the magic comment. It
    # proved clean on "-" at every boot and fired on 423 of 423 files under
    # MASTER/lib that carry the comment, because blanking line 1 leaves a file
    # that starts with a newline. SQUINT_TEST counts four consecutive newlines,
    # and four blanked comment lines are four newlines. Both were found by
    # measuring rather than by any proof, which is why the proof now measures.
    #
    # Costs nothing at boot and makes the whole defect class unreachable: a rule
    # that cannot see its own subject no longer loads.
    def prove_as_real_file!
      extension = REALISTIC_EXTENSION.find { |ext, lang| languages.empty? || languages.map(&:to_s).include?(lang) }&.first
      return self unless extension

      as_file = "fixture#{extension}"
      raise ArgumentError, "#{id}: bad fixture flagged on \"-\" but not on #{extension} — " \
                           "considered_text blanks its subject first (set reads_comments?)" if scan(bad, file: as_file).empty?
      raise ArgumentError, "#{id}: good fixture clean on \"-\" but flagged on #{extension}" unless scan(good, file: as_file).empty?

      self
    end

    # File-scope laws get the same two exemptions the line-scope ones have. All
    # eleven had neither, so they were blind to comment leaders and to the
    # `scan: intentional` opt-out this framework advertises — which is how
    # RATE_LIMITING_MISSING fired at :error on a sixteen-line controller with no
    # actions, on the word "login" inside a comment. At :error that also gates
    # the file out of the semantic pass entirely.
    def scan_file(text, file)
      return [] if absent && text.match?(absent)
      return [] unless detect.call(considered_text(text, file))

      [Finding.new(id, file, 1, text[/.*/])]
    end

    # Comments and intentional-marked lines blanked, newlines kept, so a
    # multi-line detector still sees the file's shape.
    def considered_text(text, file)
      leaders = reads_comments ? [] : COMMENT_LEADERS.fetch(File.extname(file), [])
      return text if leaders.empty? && !text.include?("scan:")

      text.each_line.with_index.map do |line, index|
        # A shebang is not a comment here: STRICT_MODE_ZSH asks whether a script
        # that declares an interpreter also sets strict mode, so blanking line 1
        # made it unable to see the script at all.
        next line if index.zero? && line.start_with?("#!")

        skip = leaders.any? { |leader| line.lstrip.start_with?(leader) } ||
               line.match?(/scan:\s*intentional\b/)
        skip ? "\n" : line
      end.join
    end

    def scan_lines(text, file)
      leaders = reads_comments ? [] : COMMENT_LEADERS.fetch(File.extname(file), [])
      text.each_line.with_index(1).filter_map do |line, n|
        next if leaders.any? { |leader| line.lstrip.start_with?(leader) }
        # The registry's one-line opt-out, honoured here too: a line that
        # declares itself intentional carries a reviewer's reason beside it.
        next if line.match?(/scan:\s*intentional\b/)
        Finding.new(id, file, n, line.chomp) if detect.call(line)
      end
    end
  end

  class Builder
    %i[source severity languages scope path path_exclude absent ask practice fix bad good reads_comments].each { |a| define_method(a) { |v| @h[a] = v } }

    def initialize(id) = @h = { id: id, severity: :warn, languages: [], scope: :line, path: nil, path_exclude: nil, absent: nil, detect: nil, ask: nil, practice: nil, reads_comments: false }
    def detect(&block) = @h[:detect] = block

    # Exactly one kind, and the fixtures whichever it is.
    #
    #   detect   a regex reads the source. Proved by running it at load.
    #   ask      a question a model answers about the source. Fixtures ride into
    #            the prompt as worked examples.
    #   practice a rule about how to work rather than about source text — sweep
    #            to convergence, one SSH session, restart after a deploy. No
    #            detector can exist for one, and that is a property of the
    #            subject, not a reason to keep them in a second file.
    #
    # The third kind is why every rule now lives here. They were in soul.yml
    # because this builder demanded a detector; a rule about conduct cannot have
    # one, so the requirement was excluding exactly the rules it could not
    # describe. Its fixtures are illustrative rather than executable — the
    # shortest example of following it and of not — and prove! does not scan them.
    #
    # Two kinds at once is two rules sharing an id, not a richer rule.
    def build
      kinds = %i[detect ask practice].select { |k| @h[k] }
      raise ArgumentError, "#{@h[:id]}: needs detect, ask or practice" if kinds.empty?
      raise ArgumentError, "#{@h[:id]}: has #{kinds.join(' and ')} — one rule, one kind" if kinds.size > 1

      # `fix` is in this list because Data requires it and Builder does not
      # default it, so a rule that omitted it died with "missing keyword: :fix"
      # from Data#initialize — a message about the implementation rather than
      # about the rule. Every existing law sets it; only the error changes.
      missing = %i[bad good fix].reject { |k| @h.key?(k) }
      raise ArgumentError, "#{@h[:id]}: missing #{missing.join(', ')}" unless missing.empty?

      Rule.new(**@h.slice(*MEMBERS)).prove!
    end
  end

  @rules = {}
  class << self
    attr_reader :rules

    def define(id, &block)
      b = Builder.new(id)
      b.instance_eval(&block)
      raise ArgumentError, "duplicate law #{id}" if @rules.key?(id)
      @rules[id] = b.build
    end

    def load_all(dir = __dir__)
      Dir.glob(File.join(dir, "*.rb")).sort.each { |f| require f unless f == __FILE__ }
      @rules
    end

    def scan(file, language: nil)
      text = File.read(file, encoding: "UTF-8")
      text = conduct(text) if file.start_with?(__dir__)
      @rules.values.select { |r| r.applies?(file, language) }.flat_map { |r| r.scan(text, file: file) }
    end

    # A law file necessarily contains the pattern it forbids: in its detector,
    # its fix text, and its bad fixture. Those lines declare evidence; they are
    # not conduct. Neutralize them (keeping line numbers) before a law judges law/.
    def conduct(text)
      fence = nil
      block_end = nil
      text.each_line.map do |line|
        if fence
          fence = nil if line.strip == fence
          next "#\n"
        end
        # A `detect do ... end` spanning lines declares evidence on every one of
        # them, not just the line that opens it. NULL_BLINDNESS carries `= NULL`
        # inside its own regex on a continuation line, and this method only ever
        # blanked the opening line, so the law read its own detector as a
        # violation of itself and dogfood could not go green.
        if block_end
          block_end = nil if line == block_end
          next "#\n"
        end
        if (indent = line[/^(\s*)(?:detect|scan_lines)\s+do\b/, 1])
          block_end = "#{indent}end\n"
          next "#\n"
        end

        fence = line[/^\s*(?:bad|good|ask|practice)\s+<<~(\w+)/, 1]
        line.match?(/^\s*(?:source|detect|ask|practice|fix|bad|good)\b/) ? "#\n" : line
      end.join
    end
  end
end
