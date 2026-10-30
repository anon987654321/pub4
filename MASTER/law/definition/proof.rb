# frozen_string_literal: true

module Law
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
end
