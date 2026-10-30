# frozen_string_literal: true

require "digest"
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

  require_relative "definition/subject"
  require_relative "definition/proof"
  require_relative "definition/reading"

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

  require_relative "definition/builder"
  require_relative "definition/contract"
  require_relative "definition/index"

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

    # law/detectors/ holds the Laws whose detector is a lexer, an AST walk or a
    # class, beside the helpers they share; they are Laws like any other and load here.
    def law_files(dir)
      files = (Dir.glob(File.join(dir, "*.rb")).sort + Dir.glob(File.join(dir, "detectors", "*.rb")).sort)
      files.map { |file| File.expand_path(file) } - [File.expand_path(__FILE__)]
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
