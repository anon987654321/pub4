# frozen_string_literal: true

require "digest"
require "set"
require_relative "../lib/law_vocabulary"

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
  # laws.yml owns the catalogue, each Law's policy and the surface contract; Ruby
  # implements detectors and creates no second identity, policy or surface list.
  require_relative "../lib/master" unless defined?(Master::ROOT)
  require_relative "../lib/law_catalogue_preflight"
  LAW_CATALOGUE = Master.load_laws.fetch("law_catalogue").freeze
  ASSESSMENT_SURFACES = Array(LAW_CATALOGUE.fetch("surfaces")).map(&:to_sym).freeze

  def self.catalogue_entry(id)
    key = id.to_s
    entries = LAW_CATALOGUE.fetch("entries")
    entry = entries[key] || entries.find { |name, _value| name.to_s.casecmp?(key) }&.last
    raise KeyError, "Law #{key} is absent from MASTER/data/laws.yml law_catalogue.entries" unless entry

    raise ArgumentError, "Law #{key} is not marked universal in laws.yml" unless entry["universal"] == true
    modalities = Array(entry["modalities"]).map(&:to_s).sort
    expected = Master::LawVocabulary::MODALITIES
    raise ArgumentError, "Law #{key} modalities must be #{expected.join(', ')}" unless modalities == expected

    entry
  end

  # A Law's enforcement policy is its catalogue entry over the catalogue's
  # defaults; Ruby carries only the detector. `path` is a substring and
  # `path_pattern` a regexp; `path_exclude` is a regexp or a list of alternatives.
  def self.catalogue_policy(id, entry = catalogue_entry(id))
    policy = LAW_CATALOGUE.fetch("defaults", {}).merge(entry)
    raise ArgumentError, "Law #{id} has no severity in laws.yml law_catalogue" if policy["severity"].to_s.empty?

    named = policy.slice("severity", "mode", "lifecycle", "autofix").to_h { |key, value| [key.to_sym, value.to_sym] }
    named.merge(reach(policy))
  end

  def self.reach(policy)
    { languages: Array(policy["languages"]).map(&:to_s), surfaces: policy["surfaces"]&.map(&:to_sym),
      path: policy["path_pattern"] ? Regexp.new(policy["path_pattern"]) : policy["path"],
      path_exclude: pattern(policy["path_exclude"]) }
  end

  def self.pattern(source) = source && Regexp.union(Array(source).map { |part| Regexp.new(part) })

  # A `detect` regex reports a line and the Law's fix text; it has no account of
  # its own, so `message` and `detail` are nil.
  Finding = Data.define(:id, :file, :line, :text) do
    def message = nil
    def detail = nil
  end

  # A `check` or detector class reports the scanner finding it built (`detail`),
  # whose line and message are its own account of what it saw.
  CheckFinding = Data.define(:id, :file, :text, :detail) do
    def line = Master::Review::Scan::Finding.read(detail, :line).to_i
    def message = Master::Review::Scan::Finding.read(detail, :message)
  end

  # What every law asks of one subject, worked out once. The bridge hands the
  # same text to each of a hundred laws in turn, and each re-split it into
  # lines, re-found its comment spans and tested every line for the intentional
  # marker; on a large stylesheet that was most of a scan. The view is held per
  # thread for the text it was built from, so a different text or file rebuilds
  # it and no law sees another subject's lines.
  class SubjectView
    INTENTIONAL = /scan:\s*intentional\b/

    attr_reader :lines, :skipped, :intentional

    def initialize(text:, file:, leaders:, continued:)
      @text = text
      @file = file
      @size = text.bytesize
      @lines = text.each_line.to_a
      @intentional = Set.new
      @skipped = Set.new(continued)
      @lines.each_with_index do |line, index|
        @intentional << index if line.match?(INTENTIONAL)
        @skipped << index if @intentional.include?(index) || leaders.any? { |leader| line.lstrip.start_with?(leader) }
      end
      @continued = continued
      @considered = {}
    end

    def fresh?(text, file) = @text.equal?(text) && @file == file && @size == text.bytesize

    def continued?(index) = @continued.include?(index)

    def considered(reads_comments) = @considered.fetch(reads_comments) { @considered[reads_comments] = yield }
  end

  # A line-scoped detector reads code, and a comment naming a forbidden
  # construct is prose about it, not an instance of it — "# a bare rescue"
  # became an error-severity finding when FAIL_VISIBLY moved here from the
  # yaml bridge, which had learned this once already. Comment-leading lines
  # are skipped for the file's own comment syntax; a rule whose subject IS
  # comments (WHY_NOT_WHAT, TYPOGRAPHY_DISCIPLINE) declares `reads_comments
  # true`. Fixtures prove with file "-", which has no extension and so no
  # comment syntax — a fixture is always read whole.
  # Keyed by language rather than by extension, because an extension table here
  # is a second copy of FILE_LANGUAGE_MAP that has to agree with it and does
  # not. Adding .ksh, .ru and .mjs to that map made three more file types
  # readable and left their comments unblanked, so DOLLAR_PAREN read the prose
  # backticks in a ksh comment — `keepenv`, `sysctl | awk` — as command
  # substitution. One table, and a new extension inherits its language's
  # comment syntax for free.
  LANGUAGE_COMMENT_LEADERS = {
    "ruby" => ["#"], "yaml" => ["#"], "zsh" => ["#"],
    "javascript" => ["//", "/*"],
    "css" => ["/*"], "scss" => ["//", "/*"],
    "html" => ["<!--"]
  }.freeze

  # ERB is html by language and carries Ruby's comment tag as well, which is the
  # one case the language alone does not answer.
  EXTENSION_COMMENT_LEADERS = { ".erb" => ["<%#"] }.freeze

  def self.comment_leaders(file)
    language = Master.language_for(file)
    LANGUAGE_COMMENT_LEADERS.fetch(language, []) +
      EXTENSION_COMMENT_LEADERS.fetch(File.extname(file).downcase, [])
  end

  # One real extension per language a law can declare, for proving a fixture the
  # way a subject is actually read. Ordered so the first match is the ordinary
  # case for that language rather than an alias of it.
  REALISTIC_EXTENSION = {
    ".rb" => "ruby", ".js" => "javascript", ".scss" => "scss", ".css" => "css",
    ".html" => "html", ".yml" => "yaml", ".sh" => "zsh", ".md" => "markdown", ".json" => "json"
  }.freeze

  # One realistic path per language, for a check that reads where a file lives.
  # These were test/test_law_fixtures.rb's, which proved the LawDSL detectors.
  PROOF_PATHS = {
    "ruby" => "/repo/app/models/example.rb", "zsh" => "/repo/bin/example.sh",
    "scss" => "/repo/app/assets/stylesheets/_example.scss", "css" => "/repo/app/assets/stylesheets/example.css",
    "html" => "/repo/app/views/example.html.erb",
    "javascript" => "/repo/app/javascript/controllers/example_controller.js"
  }.freeze

  # How a Definition proves itself at load: its fixtures, its policy and its reach.
  module Proof
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
      if proved_by then prove_named_test!
      elsif scannable? then prove_fixtures!
      end
      prove_policy!
      prove_reach!
      self
    end

    # Where a check's fixtures are proved: its example_path, else a realistic
    # path for its first language. A check reads the path as well as the text
    # (`path.include?("/app/views/")`), so "-" proved nothing for most of them.
    def proof_path
      example_path || PROOF_PATHS.fetch(languages.first.to_s, PROOF_PATHS.fetch("ruby"))
    end

    # The file a Law's own fixtures are proved as: "-" (the text whole, no
    # comment syntax) for a `detect` regex, a realistic path for anything that
    # reads where the file lives. prove! and the dogfood suite both ask here.
    def proof_file = example_path || check || detector ? proof_path : "-"

    private

    # A detector that reads a repository, a linter or git cannot prove itself
    # at boot; it names the test that does, and that test must exist.
    def prove_named_test!
      return if File.file?(File.join(Master::ROOT, proved_by))

      raise ArgumentError, "#{id}: proved_by #{proved_by} does not exist"
    end

    def prove_fixtures!
      at = proof_file == "-" ? "" : " at #{proof_file}"
      raise ArgumentError, "#{id}: bad fixture not flagged#{at}" if scan(bad, file: proof_file).empty?
      raise ArgumentError, "#{id}: good fixture flagged#{at}" unless scan(good, file: proof_file).empty?

      prove_as_real_file! if proof_file == "-"
    end

    def prove_policy!
      known = ::Law::Definition::LIFECYCLE_TRANSITIONS.key?(lifecycle)
      raise ArgumentError, "#{id}: unknown lifecycle #{lifecycle.inspect}" unless known
      raise ArgumentError, "#{id}: unknown autofix policy #{autofix.inspect}" unless AUTOFIX_POLICIES.include?(autofix)
      return unless autofix == :automatic && !scannable?

      raise ArgumentError, "#{id}: automatic autofix requires a deterministic detector"
    end

    def prove_reach!
      unreachable = languages.map(&:to_s) - Master::FILE_LANGUAGE_MAP.values.uniq
      return if unreachable.empty?

      raise ArgumentError, "#{id}: declares language(s) #{unreachable.join(', ')} that FILE_LANGUAGE_MAP never produces"
    end

    # The same two fixtures, read the way each declared language is read.
    # Multi-language deterministic laws need one representative file per language;
    # proving only the first extension left the other adapters unmeasured.
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
      declared = languages.map(&:to_s)
      extensions = if declared.empty?
        [REALISTIC_EXTENSION.keys.first]
      else
        REALISTIC_EXTENSION.filter_map { |ext, lang| ext if declared.include?(lang) }
      end
      return self if extensions.empty?

      extensions.each do |extension|
        as_file = "fixture#{extension}"
        if scan(bad, file: as_file).empty?
          raise ArgumentError, "#{id}: bad fixture flagged on \"-\" but not on #{extension} — " \
                               "considered_text blanks its subject first (set reads_comments?)"
        end
        next if scan(good, file: as_file).empty?

        raise ArgumentError, "#{id}: good fixture clean on \"-\" but flagged on #{extension}"
      end

      self
    end
  end

  # How a Definition reads a subject: the text it considers, by line or whole,
  # and what a check or detector class reports.
  module Reading
    private

    # File-scope laws get the same two exemptions the line-scope ones have. All
    # eleven had neither, so they were blind to comment leaders and to the
    # `scan: intentional` opt-out this framework advertises — which is how
    # RATE_LIMITING_MISSING fired at :error on a sixteen-line controller with no
    # actions, on the word "login" inside a comment. At :error that also checks
    # the file out of the semantic pass entirely.
    def scan_file(text, file)
      return [] if absent && text.match?(absent)
      return [] unless detect.call(considered_text(text, file))

      [Finding.new(id, file, 1, text[/.*/])]
    end

    # A check reads the raw text and runs on a Scan::Detector, whose helpers it
    # shares with every detector class: `finding`, the AST walks, source
    # masking. Raw, because a check decides what a comment or a `scan:
    # intentional` marker means for it — LONG_LINE measures a marked line with
    # the marker removed — so blanking either first would change what it judges.
    def scan_check(text, file)
      return [] if absent && text.match?(absent)

      runner = Master::Review::Scan::Detector.new.bind(self)
      law_findings(runner.instance_exec(text, file, &check), lines: text.lines, file:)
    end

    # A detector class runs as the scanner runs it, built for this Law.
    def scan_detector(text, file)
      law_findings(detector.build(self).check(text, path: file), lines: text.lines, file:)
    end

    def law_findings(hits, lines:, file:)
      Array(hits).map do |hit|
        line = Master::Review::Scan::Finding.read(hit, :line).to_i
        CheckFinding.new(id:, file:, text: lines[line - 1].to_s.chomp, detail: hit)
      end
    end

    # Comments and intentional-marked lines blanked, newlines kept, so a
    # multi-line detector still sees the file's shape.
    def considered_text(text, file)
      subject_view(text, file).considered(reads_comments) { compute_considered_text(text, file) }
    end

    # Held for the text it was built from; see SubjectView.
    def subject_view(text, file)
      view = Thread.current[:law_subject_view]
      return view if view&.fresh?(text, file)

      Thread.current[:law_subject_view] = SubjectView.new(
        text:, file:, leaders: Law.comment_leaders(file), continued: continued_comment_lines(text, file),
      )
    end

    def compute_considered_text(text, file)
      leaders = reads_comments ? [] : Law.comment_leaders(file)
      continued = reads_comments ? [] : continued_comment_lines(text, file)
      return text if leaders.empty? && continued.empty? && !text.include?("scan:")

      text.each_line.with_index.map do |line, index|
        next "\n" if continued.include?(index)

        # A shebang is not a comment here: STRICT_MODE_ZSH asks whether a script
        # that declares an interpreter also sets strict mode, so blanking line 1
        # made it unable to see the script at all.
        next line if index.zero? && line.start_with?("#!")

        skip = leaders.any? { |leader| line.lstrip.start_with?(leader) } ||
               line.match?(/scan:\s*intentional\b/)
        skip ? "\n" : line
      end.join
    end

    # Line indices, zero-based, that sit inside a comment which opened on an
    # earlier line.
    #
    # A leader test reads one line, so it sees where a comment starts and never
    # where it continues. An ERB comment is routinely six lines of prose about
    # the markup below it, and every line after the first was being read as
    # markup: I18N_COVERAGE fired on a comment explaining that a page carried no
    # <h1>, because "<h1> at all — two <h2>s" is a `>`, English, and a `<`. The
    # rule already refused the opening line; there was no way for it to refuse
    # the rest.
    #
    # ERB, and a stylesheet's /* */, whose prose names declarations as often as
    # an ERB comment names tags: _composer.scss explains a fix "(measured at
    # left: 0)" on a comment's second line, and _shell.scss quotes `left: 50%`
    # on another. JavaScript and <!-- --> stay on the leader test, because a
    # glob or a regex in a script can spell /* without opening anything, and a
    # span reader that is wrong is worse than a leader test that is narrow.
    COMMENT_SPANS = {
      ".erb" => ["<%#", "%" + ">"],
      ".css" => ["/*", "*/"],
      ".scss" => ["/*", "*/"],
    }.freeze

    def continued_comment_lines(text, file)
      opener, closer = COMMENT_SPANS[File.extname(file)]
      return [] unless opener && text.include?(opener)

      inside = false
      text.each_line.with_index.filter_map do |line, index|
        opened = inside
        unless inside
          open_at = line.rindex(opener)
          inside = true if open_at && !line[open_at..].include?(closer)
        end
        if inside && line.include?(closer)
          inside = false
          next opened ? index : nil
        end
        index if inside && opened
      end
    end

    def scan_lines(text, file)
      view = subject_view(text, file)
      # A rule that reads comments still honours the registry's one-line
      # opt-out: a line that declares itself intentional carries a reviewer's
      # reason beside it.
      skip = reads_comments ? view.intentional : view.skipped
      view.lines.each_with_index.filter_map do |line, index|
        next if skip.include?(index)

        Finding.new(id, file, index + 1, line.chomp) if detect.call(line)
      end
    end
  end

  AUTOFIX_POLICIES = %i[never review automatic].freeze

  # `ask` is the semantic half: a rule whose subject cannot be matched by a
  # regex states the question instead, and the model answers it. It sits beside
  # `detect` rather than in a second file because a rule is one thing and its
  # detector kind is a property of it — the split between executable law and the policy catalogue in data/laws.yml
  # put 52 laws' detector in one file and their severity and fix text in
  # another, which is a shape no rename can make legible.
  #
  # bad/good stay required for both kinds. For `detect` they are proved by
  # running the regex at load. For `ask` they cannot be — no model call at boot —
  # so they are the prompt's own worked examples, carried into the question and
  # checkable offline by a task that has a model. A semantic rule with no
  # example of what it is looking for is the unfalsifiable shape this file
  # already refuses in the lexical case.
  MEMBERS = %i[
    id source severity mode languages scope surfaces law_scope lifecycle autofix
    path path_exclude absent detect check detector ask practice fix bad good reads_comments tags example_path
    reads_beyond_file transform proved_by
  ].freeze

  Definition = Data.define(*MEMBERS) do
    include Proof
    include Reading

    # `path` is a substring (catalogue `path`) or a Regexp (catalogue
    # `path_pattern`); `path_exclude` is always a Regexp.
    # A law that names no language applies everywhere. A law that names one
    # applies to a file resolved to that language, and to nothing else.
    #
    # This read `language.nil? || languages.empty? || ...`, so an unresolved
    # file satisfied every language-scoped law — the opposite of what the
    # registry's Law#applies_to? has always answered for the same question.
    # 396 tracked files resolve to nil, and 302 of them are not source in any
    # language: .gitignore, .svg, .toml, .env, Gemfile.lock. Each was measured
    # against all 65 language-scoped laws, which is how FROZEN_STRING_LITERAL
    # came to ask 172 non-Ruby files for a Ruby magic comment against 4 real
    # ones.
    #
    # The clause was protecting the other 94 — Gemfile, Rakefile, and the
    # executables under bin/ whose language is in their shebang. Those are
    # resolved now rather than excused, by Master.language_for.
    def applies?(file, language)
      return false if path && !(path.is_a?(Regexp) ? file.match?(path) : file.include?(path))
      return false if path_exclude && file.match?(path_exclude)

      languages.empty? || (language && languages.include?(language.to_s))
    end

    # A semantic rule has no detector to run here. It is carried to the model by
    # the semantic pass instead, so scanning it lexically must find nothing
    # rather than raise on a nil detect.
    def semantic? = !ask.nil?

    # A Law is assessed on every canonical surface unless its catalogue entry
    # declares `surfaces:`, which narrows it to the ones named. A surface the
    # Law reaches but no adapter measures stays INCONCLUSIVE, never exempt.
    def assessment_surfaces = surfaces || ::Law::ASSESSMENT_SURFACES

    # Universal describes the invariant, not the detector syntax. A universal
    # principle may have Ruby, zsh, Rails or another domain adapter.
    def universal? = ::Law.catalogue_entry(id).fetch("universal")

    # Lifecycle controls whether a law may affect enforcement. Existing laws
    # default to active for compatibility; candidates can enter proposed/proven
    # without silently becoming merge blockers.
    def enforceable? = %i[active trusted].include?(lifecycle)

    def can_transition_to?(state)
      ::Law::Definition::LIFECYCLE_TRANSITIONS.fetch(lifecycle).include?(state.to_sym)
    end

    def proof_kind
      return :deterministic if scannable?
      return :semantic if ask || model_detector?
      :practice
    end

    # A detector class that takes a model (it defines set_agent, as
    # Laws::NeedsModel does) is a semantic evaluator, however it is wired.
    def model_detector? = detector ? detector.method_defined?(:set_agent) : false

    # Neither kind scans source: one is answered by a model, one binds behaviour.
    def scannable? = detect || check || (detector && !model_detector?) ? true : false

    def scan(text, file: "-")
      return [] unless scannable?
      return scan_check(text, file) if check
      return scan_detector(text, file) if detector

      scope == :file ? scan_file(text, file) : scan_lines(text, file)
    end

    # The rule's published shape for Contract. Key order and the empty filter
    # feed law_digest, so any change here changes the digest every external
    # model hands back at the handshake.
    def contract_entry
      {
        "id" => id.to_s,
        "severity" => severity.to_s,
        "mode" => mode.to_s,
        "languages" => languages.map(&:to_s),
        "surfaces" => assessment_surfaces.map(&:to_s),
        "law_scope" => law_scope.to_s,
        "lifecycle" => lifecycle.to_s,
        "autofix" => autofix.to_s,
        "proof" => proof_kind.to_s,
        "question" => ask.to_s,
        "practice" => practice.to_s,
        "fix" => fix.to_s,
        "bad" => bad.to_s,
        "good" => good.to_s,
      }.reject { |_, value| value.respond_to?(:empty?) && value.empty? }
    end

  end

  # Data.define's block is lexical; publish this graph on the generated Law
  # definition explicitly because Contract, Index and callers use it as Law API.
  Definition.const_set(:LIFECYCLE_TRANSITIONS, {
    proposed: %i[proven retired],
    proven: %i[active advisory retired],
    active: %i[observed advisory retired],
    observed: %i[trusted active advisory retired],
    trusted: %i[active observed advisory retired],
    advisory: %i[proven active retired],
    retired: %i[proposed],
  }.freeze)

  # Ruby declares what a Law detects and how it reads; its policy comes from
  # the catalogue entry, so the block has no method to declare severity,
  # languages, paths, lifecycle or autofix a second time.
  class Builder
    %i[source scope absent ask practice fix bad good reads_comments].each { |a| define_method(a) { |v| @h[a] = v } }

    def initialize(id)
      @h = {
        id:, scope: :line, law_scope: nil, absent: nil, detect: nil, check: nil, ask: nil, practice: nil,
        reads_comments: false, tags: [], example_path: nil, reads_beyond_file: false, transform: nil,
        detector: nil, proved_by: nil, source: nil, **::Law.catalogue_policy(id)
      }
    end

    # A detector class (a Review::Scan::Detector) for a Law whose detection needs
    # state, a whole walk or a model: the AST and graph laws, the linters, the
    # semantic evaluators. It is this Law's detector and nothing else's.
    def detector(klass) = @h[:detector] = klass

    # The test that proves this Law's detector, for one that cannot prove itself
    # on two fixtures at boot (it reads a repository, runs a linter or asks a model).
    def proved_by(path) = @h[:proved_by] = path

    # The AstFixer transform that repairs this Law's findings, when one does. A
    # transform in AstFixer::DELETING_TRANSFORMS waits for a person (Scanner#deleting_law?).
    def transform(name) = @h[:transform] = name.to_s

    # A check whose findings depend on more than the file's text and path (git
    # history, sibling files) says so, and Scan::FindingCache never replays it.
    def reads_beyond_file(value) = @h[:reads_beyond_file] = value
    def detect(&block) = @h[:detect] = block

    # `check { |text, file| ... }` answers findings, each built by `finding(line:, message:)`.
    def check(&block) = @h[:check] = block

    # The concern a Law belongs to (DESIGN, TYPOGRAPHY, ...): carried on its findings.
    def tags(*names) = @h[:tags] = names.flatten.map(&:to_sym)

    # The path its fixtures are proved at, for a detector that judges only some paths.
    def example_path(path) = @h[:example_path] = path

    # A law can carry more than one enforcement surface without becoming more
    # than one rule. detect is deterministic evidence, ask is semantic evidence,
    # and practice is conduct guidance. Their combination is useful: one law may
    # be cheap to detect mechanically, expensive to understand semantically, and
    # still impose a working discipline on the operator.
    def build
      refuse_shape!
      refuse_missing!
      @h[:bad] = nil unless @h.key?(:bad)
      @h[:good] = nil unless @h.key?(:good)
      @h[:law_scope] = ::Law.catalogue_entry(@h.fetch(:id)).fetch("universal") ? :universal : :domain

      Definition.new(**@h.slice(*MEMBERS)).prove!
    end

    private

    def refuse(reason) = raise(ArgumentError, "#{@h[:id]}: #{reason}")

    def refuse_shape!
      detectors = %i[detect check detector].count { |k| @h[k] }
      refuse "needs detect, check, detector, ask or practice" if detectors.zero? && !@h[:ask] && !@h[:practice]
      refuse "detect, check and detector are three detectors; keep one" if detectors > 1

      unknown_surfaces = Array(@h[:surfaces]) - ASSESSMENT_SURFACES
      refuse "unknown assessment surfaces #{unknown_surfaces.join(', ')}" if unknown_surfaces.any?
    end

    # Named here so a law missing one hears about the law, not Data#initialize.
    # A Law proved by a named test may carry its fixtures there instead.
    def refuse_missing!
      missing = (@h[:proved_by] ? %i[fix] : %i[bad good fix]).reject { |k| @h.key?(k) }
      refuse "missing #{missing.join(', ')}" unless missing.empty?
    end
  end

  # Generated projection of the executable constitution. The laws remain
  # ONE_SOURCE; this contract gives external models the same procedure and a
  # portable law identity without maintaining a second rule catalogue.
  module Contract
    module_function

    VERSION = 2
    PROTOCOL = [
      "IDENTIFY: state the task and intended effects before acting.",
      "READ: load the applicable constitution/laws before deciding.",
      "EVIDENCE: distinguish observed facts, inference, and proposal.",
      "CHECK: apply every applicable law; do not stop at the first convenient rule.",
      "PREFER: resolve conflicts by declared priority and safety constraints.",
      "SIMULATE: inspect edge cases, security, scope, reversibility, and side effects.",
      "ADMIT: only execute effects that pass the constitutional check.",
      "VERIFY: inspect the actual result; never claim completion without evidence.",
      "REPAIR: if a law is violated, correct the artifact and re-check from the start.",
      "REPORT: state what happened, what was verified, and what remains unresolved.",
    ].freeze

    POLICY = {
      "lifecycle" => {
        "states" => Definition::LIFECYCLE_TRANSITIONS.keys.map(&:to_s),
        "transitions" => Definition::LIFECYCLE_TRANSITIONS
          .transform_keys(&:to_s)
          .transform_values { |states| states.map(&:to_s) },
      },
      "autofix" => {
        "policies" => AUTOFIX_POLICIES.map(&:to_s),
        "automatic_requires_deterministic_detector" => true,
      },
      "universality" => {
        "law_is_universal" => true,
        "detectors_may_be_domain_specific" => true,
      },
      "vocabulary" => Master::LawVocabulary::TERMS,
      "proof" => {
        "deterministic" => "bad and good fixtures prove detector polarity.",
        "semantic" => "bad and good examples accompany the question; model evaluation is required.",
        "practice" => "the law is conduct guidance and has no source detector.",
      },
    }.freeze

    def render(full: false)
      entries = Law.definitions.values.sort_by { |law| law.id.to_s }.map(&:contract_entry)
      transformation_policy = Master.law("transformation_policy")
      laws = full ? entries : entries.map { |entry| entry.slice("id", "severity", "mode", "languages", "question") }
      source = canonical_source
      JSON.pretty_generate(
        "contract_version" => VERSION,
        "law_digest" => contract_digest(entries, transformation_policy, source),
        "protocol" => PROTOCOL,
        "law_policy" => POLICY,
        "transformation_policy" => transformation_policy,
        "law_source" => source.slice("governing_laws", "law_map_digest"),
        "laws" => laws,
      )
    end

    def digest
      entries = Law.definitions.values.sort_by { |law| law.id.to_s }.map(&:contract_entry)
      contract_digest(entries, Master.law("transformation_policy"), canonical_source)
    end

    def canonical_source
      roots = Master.law_entries.sort_by { |entry| [entry["priority"].to_i, entry["id"].to_s] }.map do |entry|
        {
          "id" => entry["id"].to_s,
          "priority" => entry["priority"].to_i,
          "statement" => entry["statement"].to_s,
          "applies_to" => Array(entry["applies_to"]).map(&:to_s),
        }
      end
      law_map = Master.law("law_map")
      {
        "governing_laws" => roots,
        "law_map_digest" => Digest::SHA256.hexdigest(JSON.generate(law_map)),
      }
    end

    def contract_digest(entries, transformation_policy, source)
      Digest::SHA256.hexdigest(
        JSON.generate(
          "contract_version" => VERSION,
          "protocol" => PROTOCOL,
          "law_policy" => POLICY,
          "transformation_policy" => transformation_policy,
          "law_source" => source,
          "laws" => entries,
        ),
      )
    end
  end

  # Derived law index. Identity, enforcement surface, lifecycle, proof and
  # universality stay on Law::Definition; this index is generated and never authoritative.
  module Index
    module_function

    VERSION = 1

    def rows(definitions = Law.definitions.values)
      definitions.sort_by { |law| law.id.to_s }.map do |law|
        {
          "id" => law.id.to_s,
          "scope" => law.scope.to_s,
          "surfaces" => law.assessment_surfaces.map(&:to_s),
          "law_scope" => law.law_scope.to_s,
          "languages" => law.languages.map(&:to_s),
          "lifecycle" => law.lifecycle.to_s,
          "autofix" => law.autofix.to_s,
          "proof" => law.proof_kind.to_s,
          "deterministic" => law.scannable?,
          "semantic" => law.semantic?,
          "practice" => !law.practice.nil?,
        }
      end
    end

    def validate!(definitions = Law.definitions.values)
      raise ArgumentError, "law index is empty" if definitions.empty?

      ids = definitions.map { |law| law.id.to_s }
      duplicate = ids.tally.select { |_id, count| count > 1 }.keys
      raise ArgumentError, "duplicate executable law ids: #{duplicate.join(', ')}" unless duplicate.empty?

      invalid = definitions.reject { |law| Definition::LIFECYCLE_TRANSITIONS.key?(law.lifecycle) }
      raise ArgumentError, "invalid law lifecycle: #{invalid.map(&:id).join(', ')}" unless invalid.empty?

      invalid = definitions.reject { |law| AUTOFIX_POLICIES.include?(law.autofix) }
      raise ArgumentError, "invalid law autofix policy: #{invalid.map(&:id).join(', ')}" unless invalid.empty?

      automatic = definitions.select { |law| law.autofix == :automatic && !law.scannable? }
      unless automatic.empty?
        raise ArgumentError, "automatic autofix without deterministic detector: #{automatic.map(&:id).join(', ')}"
      end

      rows(definitions)
    end

    def render(definitions = Law.definitions.values)
      entries = validate!(definitions)
      JSON.pretty_generate(
        "index_version" => VERSION,
        "law_count" => entries.length,
        "universal_count" => entries.count { |entry| entry["law_scope"] == "universal" },
        "laws" => entries,
      )
    end
  end

  LOAD_MUTEX = Mutex.new

  @definitions = {}
  @law_sources = {}
  @law_stamps = {}
  class << self
    attr_reader :definitions

    def define(id, &block)
      b = Builder.new(id)
      b.instance_eval(&block)
      # A reload in progress defines into its own copy, so no reader sees the old registry half replaced.
      registry = Thread.current[:law_staging] || @definitions
      raise ArgumentError, "duplicate law #{id}" if registry.key?(id)

      registry[id] = b.build
    end

    # Loads every law file in dir and publishes the result in one assignment. The live registry
    # is never edited in place: a reader during the reload sees the complete old set, and a
    # reload that raises leaves it untouched.
    def load_all(dir = __dir__)
      LOAD_MUTEX.synchronize { reload(dir) }
    end

    def reload(dir)
      preflight!(dir) if File.expand_path(dir) == File.expand_path(__dir__)
      files = law_files(dir)

      staged = @definitions.dup
      sources = @law_sources.dup
      stamps = @law_stamps.dup

      changed = false
      (sources.keys - files).each do |source|
        changed = true
        sources.delete(source).each { |id| staged.delete(id) }
        stamps.delete(source)
      end

      Thread.current[:law_staging] = staged
      files.each do |source|
        stat = File.stat(source)
        stamp = [stat.size, stat.ino, stat.mtime.to_r]
        # A stamp says the file is unchanged, not that its laws are still registered:
        # a cleared registry must reload them, or every caller after the clear sees none.
        next if stamps[source] == stamp && sources[source].to_a.all? { |id| staged.key?(id) }

        changed = true
        sources[source].to_a.each { |id| staged.delete(id) }
        before_ids = staged.keys
        load source
        sources[source] = staged.keys - before_ids
        stamps[source] = stamp
      end

      return @definitions unless changed

      @definitions = staged
      @law_sources = sources
      @law_stamps = stamps
      staged
    ensure
      Thread.current[:law_staging] = nil
    end

    # One flat law/: every file but this one holds Laws.
    def law_files(dir)
      Dir.glob(File.join(dir, "*.rb")).sort.map { |file| File.expand_path(file) } - [File.expand_path(__FILE__)]
    end

    def preflight!(dir)
      generated = Master.load_laws(root: Master::ROOT).fetch("prose").values.flat_map do |language|
        language.fetch("ids", {}).values.map { |id| { id: id.to_s, source: "MASTER/law/prose.rb", line: 1 } }
      end

      Master::LawCataloguePreflight.validate!(
        law_dir: dir,
        catalogue: LAW_CATALOGUE,
        repo_root: File.dirname(Master::ROOT),
        generated_declarations: generated.uniq { |row| row[:id] },
      )
    end

    def scan(file, language: nil)
      text = File.read(file, encoding: "UTF-8")
      text = conduct(text) if file.start_with?(__dir__)
      @definitions.values.select { |law| law.applies?(file, language) }.flat_map { |law| law.scan(text, file:) }
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
        if (indent = line[/^(\s*)(?:detect|check|scan_lines)\s+do\b/, 1])
          block_end = "#{indent}end\n"
          next "#\n"
        end

        fence = line[/^\s*(?:bad|good|ask|practice)\s+<<~["']?(\w+)["']?/, 1]
        line.match?(/^\s*(?:source|detect|check|ask|practice|fix|bad|good)\b/) ? "#\n" : line
      end.join
    end
  end
end
