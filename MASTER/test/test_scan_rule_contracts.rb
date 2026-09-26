# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"
require "review/scan/rules/structural_rules"

class TestScanRuleContracts < Minitest::Test
  Rules = Master::Review::Scan::Rules

  def test_small_files_rule_flags_files_over_limit
    code = Array.new(Rules::SmallFilesRule::LIMIT + 1, "puts :x").join("\n")

    assert_finding Rules::SmallFilesRule.new, code, "large.rb", "file"
  end

  def test_small_files_rule_reads_code_with_modules_and_leaves_data_and_javascript
    long = Array.new(Rules::SmallFilesRule::LIMIT + 1, "x").join("\n")
    %w[bin/operator app.scss deploy.sh].each do |path|
      refute_empty Rules::SmallFilesRule.new.check(long, path:), path
    end
    %w[nb.yml snapshot.json TODO.md Gemfile.lock app.js face.part1.txt].each do |path|
      assert_empty Rules::SmallFilesRule.new.check(long, path:), path
    end
  end

  def test_small_functions_rule_flags_long_methods
    body = Array.new(Rules::SmallFunctionsRule::MAX + 1, "  puts :x").join("\n")
    code = "def oversized\n#{body}\nend\n"

    assert_finding Rules::SmallFunctionsRule.new, code, "large_method.rb", "method oversized"
  end

  def test_god_class_rule_flags_many_public_methods
    methods = (1..(Rules::GodClassRule::METHOD_LIMIT + 1)).map { |i| "  def m#{i}; end" }.join("\n")
    code = "class TooMuch\n#{methods}\nend\n"

    assert_finding Rules::GodClassRule.new, code, "god.rb", "god class TooMuch"
  end

  def test_cqs_rule_flags_mutation_plus_return
    code = <<~RUBY
      def update_and_read
        @value = 1
        return @value
      end
    RUBY

    assert_finding Rules::CqsRule.new, code, "cqs.rb", "mutates state and returns"
  end

  def test_cqs_rule_ignores_guarded_memoized_reader
    code = <<~RUBY
      def value
        return @value if @value
        @value = load_value
        return @value
      end
    RUBY

    assert_empty Rules::CqsRule.new.check(code, path: "memoized.rb")
  end

  def test_cqs_rule_ignores_or_equals_memoized_reader
    code = <<~RUBY
      def value
        @value ||= load_value
        return @value
      end
    RUBY

    assert_empty Rules::CqsRule.new.check(code, path: "memoized_equals.rb")
  end

  def test_cqs_rule_still_flags_a_write_without_a_memoization_guard
    code = <<~RUBY
      def update
        @value = load_value
        persist!
        return @value
      end
    RUBY

    assert_finding Rules::CqsRule.new, code, "non_memoized.rb", "mutates state and returns"
  end

  def test_secret_proximity_reaches_findings_through_the_bridge
    hits = Rules::LawBridgeRule.new.check(%q{api_key = "sk_live_123456789"}, path: "app.rb")

    assert hits.any? { |h| h[:rule] == "SECRET_PROXIMITY" }, "hardcoded secret must reach scanner findings"
  end

  def test_magic_color_rule_flags_raw_css_color
    assert_finding rule("MAGIC_COLOR", path: "app.css"), ".x { color: #ff00aa; }", "app.css", "raw hex color"
  end

  # FILE_SPRAWL judges the tree's shape: a one-file directory and a tiny file
  # are both mergeable sprawl (operator standing instruction). law/ and core/
  # are deliberately outside its reach — one is a per-rule-file design until
  # the domain-file decision, the other a ratcheted invariant.
  def test_file_sprawl_flags_lone_files_and_tiny_files_but_not_core_or_law
    Dir.mktmpdir do |root|
      lone = File.join(root, "lib", "widgets", "only.rb")
      FileUtils.mkdir_p(File.dirname(lone))
      File.write(lone, "module Only\nend\n" + ("x = 1\n" * 30))
      rule = Rules::FileSprawlRule.new(root:)

      hits = rule.check(File.read(lone), path: lone)
      assert_equal 1, hits.size
      assert_match(/only file in lib\/widgets/, hits.first[:message])

      tiny = File.join(root, "lib", "widgets", "tiny.rb")
      File.write(tiny, "module Tiny\nend\n")
      fresh = Rules::FileSprawlRule.new(root:)
      tiny_hits = fresh.check(File.read(tiny), path: tiny)
      assert_equal 1, tiny_hits.size
      assert_match(/2 code lines/, tiny_hits.first[:message])

      # a healthy file in a healthy dir is silent
      assert_empty fresh.check(File.read(lone), path: lone).select { |h| h[:message].include?("only file") }

      core = File.join(root, "lib", "core", "fold.rb")
      FileUtils.mkdir_p(File.dirname(core))
      File.write(core, "module Fold\nend\n")
      assert_empty Rules::FileSprawlRule.new(root:).check(File.read(core), path: core)

      # a lone directory whose owner file sits beside it is a nested constant
      nested = File.join(root, "lib", "cli", "propose", "candidate_sources.rb")
      FileUtils.mkdir_p(File.dirname(nested))
      File.write(nested, "module CandidateSources\nend\n" + ("x = 1\n" * 30))
      File.write(File.join(root, "lib", "cli", "propose.rb"), "class Propose\nend\n")
      assert_empty Rules::FileSprawlRule.new(root:).check(File.read(nested), path: nested)
    end
  end

  # Rails names these files itself, so their count is the framework's; the
  # same names in a tree that is not Rails are still judged.
  def test_file_sprawl_spares_what_rails_names_and_nothing_else
    Dir.mktmpdir do |root|
      write = lambda do |rel|
        path = File.join(root, rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "module Tiny\nend\n")
        path
      end
      sprawl = ->(path) { Rules::FileSprawlRule.new(root:).check(File.read(path), path:) }

      write.call("site/config/application.rb")
      %w[site/app/models/tag.rb site/app/models/city.rb site/config/initializers/a.rb site/config/initializers/b.rb
         site/db/seeds.rb site/db/cache_schema.rb].each { |rel| assert_empty sprawl.call(write.call(rel)), rel }

      write.call("site/engines/tv/lib/tv/engine.rb")
      assert_empty sprawl.call(write.call("site/engines/tv/lib/tv/version.rb"))

      write.call("plain/app/one.rb")
      refute_empty sprawl.call(write.call("plain/app/two.rb")), "an app/ outside Rails is still judged"
      write.call("site/lib/site/helper.rb")
      refute_empty sprawl.call(write.call("site/lib/site/other.rb")), "a Rails app's own lib/ is still judged"
    end
  end

  # UNBOUNDED_RETRY is the first retired law/registry twin: the registry block
  # is gone and law/ is the one implementation, so the
  # contract asserts through the bridge — the id must reach the scanner's
  # findings, unchanged, not just prove itself inside Law.
  def test_unbounded_retry_reaches_findings_through_the_bridge
    bridge = Rules::LawBridgeRule.new
    hits = bridge.check("begin\n  call\nrescue\n  retry\nend\n", path: "retry.rb")
    retry_hits = hits.select { |h| h[:rule] == "UNBOUNDED_RETRY" }

    refute_empty retry_hits, "uncapped retry must reach scanner findings via the bridge"
    assert_equal :error, retry_hits.first[:severity]
  end

  # The batch-retired twins: every id whose registry block was a regex-identical
  # duplicate of its law. Each law already proves itself against its own bad
  # fixture at load; this asserts the other half of the contract — that the id
  # still reaches scanner findings through the bridge, at a path its own
  # scoping (path prefix + language) accepts.
  RETIRED_TWINS = %w[
    ARIA_INTERACTIVE BUTTON_OVER_ANCHOR CLAMP_TYPOGRAPHY DOLLAR_PAREN
    I18N_COVERAGE MEANINGFUL_NAMES MEASURE_OPTIMUM
    MIGRATION_ADD_REFERENCE_NO_FK MIGRATION_FIND_OR_CREATE_BY
    MIGRATION_REMOVE_COLUMN MOBILE_FIRST NO_IMPORT_SCSS NO_INLINE_STYLES
    PERCENT_LITERAL RATE_LIMITING_MISSING
    STRICT_LOADING_MISSING TRANSFORM_KEYS WHY_NOT_WHAT
  ].freeze

  TWIN_EXT = {
    "ruby" => ".rb", "html" => ".html", "css" => ".css",
    "scss" => ".scss", "zsh" => ".zsh", "javascript" => ".js"
  }.freeze

  def test_every_retired_twin_reaches_findings_through_the_bridge
    bridge = Rules::LawBridgeRule.new
    RETIRED_TWINS.each do |id|
      law = Law.rules[id.to_sym]
      refute_nil law, "#{id} must exist in law/ — its registry twin is gone"
      ext = TWIN_EXT.fetch(law.languages.first&.to_s, ".rb")
      path = "#{law.path || "/lib/"}example#{ext}"
      hits = bridge.check(law.bad, path:)
      assert hits.any? { |h| h[:rule] == id }, "#{id} must reach scanner findings via the bridge"
    end
  end

  # NEVER_BATCH_DELETE's other three branches all ask whether the set of files
  # is known at read time — a glob, a bare $var, a Dir[] are each unbounded by
  # construction. The `.each { rm }` branch asked only whether there was a loop,
  # so it read a receiver spelled out in full as the same hazard. The bracket in
  # Dir[] follows a word character and is an index, not a literal.
  def test_never_batch_delete_spares_a_receiver_enumerated_in_the_source
    [
      %(%w[.mp3 .job].each { |ext| FileUtils.rm_f(base + ext) }\n),
      %([old, older].each { |f| File.delete(f) }\n),
    ].each do |source|
      assert_empty law_findings("NEVER_BATCH_DELETE", source, path: "cleanup.rb"),
                   "#{source.inspect} names how many files go and which"
    end
  end

  def test_never_batch_delete_still_fires_on_an_unknown_set
    [
      %(stale.each { |f| File.delete(f) }\n), # scan: intentional — the law fixture
      %(Dir["tmp/*.log"].each { |f| File.delete(f) }\n), # scan: intentional — the law fixture
      %(snapshots[0...-KEEP].to_a.each { |old| File.delete(old) }\n), # scan: intentional — the law fixture
      %(Array(old).each { |f| FileUtils.rm_f(f) }\n), # scan: intentional — the law fixture
    ].each do |source|
      refute_empty law_findings("NEVER_BATCH_DELETE", source, path: "cleanup.rb"),
                   "#{source.inspect} deletes a set nothing on the line bounds"
    end
  end

  def test_strict_mode_zsh_rule_flags_missing_set_e
    refute_empty law_findings("STRICT_MODE_ZSH", "#!/usr/bin/env zsh\necho ok\n", path: "script.zsh")
  end

  # A comment between the shebang and `set -euo pipefail` is the normal
  # shape; the pre-retirement law demanded set on the very next line.
  def test_strict_mode_zsh_accepts_set_e_after_a_comment
    assert_empty law_findings("STRICT_MODE_ZSH", "#!/usr/bin/env zsh\n# header\nset -euo pipefail\n", path: "script.zsh")
  end

  # Strict mode on the shebang, an rc.d script living on rc.subr, and a file
  # /etc/daily sources are all not missing it.
  def test_strict_mode_zsh_spares_shebang_flag_rc_subr_and_sourced_locals
    assert_empty law_findings("STRICT_MODE_ZSH", "#!/bin/bash -e\nexec \"$@\"\n", path: "docker-entrypoint.sh")
    assert_empty law_findings("STRICT_MODE_ZSH", "#!/bin/ksh\ndaemon=x\n. /etc/rc.d/rc.subr\nrc_cmd $1\n", path: "etc/rc.d/app.sh")
    assert_empty law_findings("STRICT_MODE_ZSH", "#!/bin/sh\nPATH=/bin\n", path: "OPENBSD/etc/daily.local")
    refute_empty law_findings("STRICT_MODE_ZSH", "#!/bin/ksh\n. /etc/app.env\nrun\n", path: "bin/tool.sh")
  end

  # KEYWORD_ARGS folded into FEW_ARGUMENTS (2026-08-21): one parameter
  # list, one id. The contract it pinned moves to the surviving rule.
  def test_few_arguments_rule_flags_three_positionals
    assert_finding rule("FEW_ARGUMENTS"), "def call(a, b, c)\nend\n", "args.rb", "positional args"
  end

  def test_few_arguments_rule_allows_keyword_arguments
    findings = rule("FEW_ARGUMENTS").check("def call(a, b:, c: nil)\nend\n", path: "args.rb")

    assert_empty findings
  end

  def test_dead_code_rule_flags_unreachable_statement
    assert_finding rule("DEAD_CODE"), "def call\n  return :ok\n  puts :never\nend\n", "dead.rb", "unreachable code"
  end

  def test_trailing_commas_rule_flags_missing_final_comma
    code = "ITEMS = [\n  \"one\",\n  \"two\"\n]\n"

    assert_finding rule("TRAILING_COMMAS"), code, "items.rb", "missing trailing comma"
  end

  # An app on rubocop-rails-omakase fails bin/ci on the comma; a tree that sets
  # the comma style is still asked for it.
  def test_trailing_commas_defers_to_the_rubocop_config_that_governs_the_file
    code = "ITEMS = [\n  \"one\",\n  \"two\"\n]\n"
    Dir.mktmpdir do |root|
      { "app" => "inherit_gem: { rubocop-rails-omakase: rubocop.yml }\n",
        "engine" => "inherit_gem: { rubocop-rails-omakase: rubocop.yml }\n" \
                    "Style/TrailingCommaInArrayLiteral:\n  EnforcedStyleForMultiline: comma\n" }.each do |name, config|
        FileUtils.mkdir_p(File.join(root, name, "lib"))
        File.write(File.join(root, name, ".rubocop.yml"), config)
      end
      assert_empty rule("TRAILING_COMMAS").check(code, path: File.join(root, "app", "lib", "items.rb"))
      refute_empty rule("TRAILING_COMMAS").check(code, path: File.join(root, "engine", "lib", "items.rb"))
    end
  end

  def test_config_hierarchy_rule_flags_deep_duplicate_yaml
    code = <<~YAML
      app:
        nested:
          deeper:
            too:
              far: true
      app:
        duplicate: true
    YAML

    assert_finding Rules::ConfigHierarchyRule.new, code, "config.yml", "configuration nesting depth"
    assert_finding Rules::ConfigHierarchyRule.new, code, "config.yml", "duplicate configuration key"
  end

  # Depth is a key path. A list of records and a block scalar's prose both
  # indent without nesting, and a locale's depth is Rails' lookup scheme.
  def test_config_hierarchy_measures_key_paths_not_indentation
    flows = <<~YAML
      flows:
        - id: maps
          steps:
            - name: root
              get: /
              forbid_body:
                - "Sign in to continue"
          prompt: |
            Review: boundaries
              Coupling: interface shapes
    YAML
    assert_empty Rules::ConfigHierarchyRule.new.check(flows, path: "gates/data/flows.yml")

    locale = "en:\n  brgen:\n    posts:\n      form:\n        title: Title\n"
    assert_empty Rules::ConfigHierarchyRule.new.check(locale, path: "brgen/config/locales/en.yml")
    refute_empty Rules::ConfigHierarchyRule.new.check(locale, path: "data/settings.yml")

    rows = "apps:\n  brgen:\n    features:\n      core:\n" + ("        - { name: a, status: done }\n" * 3)
    hits = Rules::ConfigHierarchyRule.new.check(rows, path: "apps.yml")
    assert_equal ["configuration nesting depth exceeds 4 below apps.brgen.features.core"], hits.map { |h| h[:message] }
  end

  def test_code_hierarchy_rule_flags_many_top_level_constants
    code = %w[Alpha Beta Gamma Delta Epsilon Zeta].map { |name| "class #{name}; end" }.join("\n")

    assert_finding Rules::CodeHierarchyRule.new, code, "many.rb", "top-level constants"
  end

  def test_long_parameter_list_rule_flags_large_api
    code = "def call(a, b, c, d, e)\nend\n"

    assert_finding Rules::LongParameterListRule.new, code, "params.rb", "parameters"
  end

  def test_primitive_obsession_rule_flags_traveling_primitives
    code = "def create_order(user_id, status, price, email)\nend\n"

    assert_finding Rules::PrimitiveObsessionRule.new, code, "primitive.rb", "primitive obsession"
  end

  # Chains are LAW_OF_DEMETER's; this rule is reflection, and a method that is
  # merely named send is not reflection.
  def test_coupler_rule_flags_reflective_access_only
    assert_finding Rules::CouplerRule.new, "def call\n  order.send(:recalculate)\nend\n", "reflect.rb", "reflective access"
    domain = "def call\n  client.send(body, token)\n  user.account.profile.address.city.name\nend\n"

    assert_empty Rules::CouplerRule.new.check(domain, path: "domain.rb")
  end

  def test_lazy_class_rule_flags_delegate_only_class
    code = <<~RUBY
      class Wrapper
        def call; target.call; end
      end
    RUBY

    assert_finding Rules::LazyClassRule.new, code, "lazy.rb", "lazy class"
  end

  def test_parameterized_slug_rule_flags_fold_suffix
    assert_finding rule("PARAMETERIZED_SLUG"), "# frozen_string_literal: true\n", "lib/foo_support.rb", "merge"
  end

  def test_parameterized_slug_rule_flags_filler_only_slug
    assert_finding rule("PARAMETERIZED_SLUG"), "# frozen_string_literal: true\n", "lib/misc_util_helper.rb", "filler-only"
  end

  def test_runtime_docs_yaml_forbids_stray_data_markdown
    bad = File.join(Master::ROOT, "data", "feedback_new.md")
    good = File.join(Master::ROOT, "data", "SOUL.md")

    assert_finding rule("RUNTIME_DOCS_YAML"), "# stray\n", bad, "delete data/feedback_new.md"
    assert_empty rule("RUNTIME_DOCS_YAML").check("# ok\n", path: good)
    # data/skills/README.md left the allowed list when the directory was
    # deleted (2026-08-19) — a reborn copy is a finding now, not an exemption.
    assert_finding rule("RUNTIME_DOCS_YAML"), "# reborn\n",
                   File.join(Master::ROOT, "data", "skills", "README.md"), "delete data/skills/README.md"

    # data/principles/*.md is what Ground::Constitution globs and parses. This
    # rule used to call each of those files a delete-me at error severity, and
    # send the operator to rules.yml#operator_principles, a section whose 47
    # entries went to law/practice.rb. Invisible only because the directory is
    # empty. A file one level deeper is not that location and still fires.
    assert_empty rule("RUNTIME_DOCS_YAML").check("# a principle\n",
                                                 path: File.join(Master::ROOT, "data", "principles", "no_secrets.md"))
    assert_finding rule("RUNTIME_DOCS_YAML"), "# nested\n",
                   File.join(Master::ROOT, "data", "principles", "drafts", "later.md"),
                   "delete data/principles/drafts/later.md"
  end
  # The 2026-08-19 twin-drift debt closed at zero on 2026-08-21: an id that
  # lives in law/ and the registry at once is two detectors free to disagree
  # about one rule — the exact drift UNBOUNDED_RETRY proved. Zero is held.
  #
  # Two detectors is the hazard, and a `practice` rule has none: it states a
  # principle for the prompt and checks nothing. FLAT_PIXELS is both — the
  # design rule that binds what gets built, in law/practice.rb, and a narrow
  # detector for imageSmoothingEnabled and bloom language, in the registry.
  # Comparing every law id caught that pair and would have kept the principle
  # out of the system prompt to protect against a disagreement neither half can
  # have.
  def test_no_id_lives_in_both_law_and_registry
    Rules::LawBridgeRule.new
    law_ids = Law.rules.values.select(&:scannable?).map { |rule| rule.id.to_s }
    registry_ids = Master::Review::Scan::Rule.registry.filter_map do |klass|
      Master::Review::Scan::RuleFactory.registry_id(klass, root: Master::ROOT)&.upcase
    end
    assert_empty law_ids & registry_ids
  end

  # Every registered rule over one planted source carrying what fools a line
  # scanner: a comment and a string naming what rules look for, a heredoc, a
  # regex literal, non-ASCII identifiers. Measured 2026-09-13 across 148 rules:
  # none raised, none answered differently twice, none reported one finding
  # twice, and CRLF moved no line number. This keeps it that way.
  PLANTED = <<~'RUBY'
    # frozen_string_literal: true

    # A comment naming system("rm -rf #{dir}") and eval and TODO.
    class Ærlig
      def søk(verdi, mønster = /eval|password/)
        tekst = "sudo password=#{verdi}"
        sql = <<~SQL
          SELECT * FROM users WHERE name = '#{verdi}'
        SQL
        [tekst, sql, mønster]
      end
    end
  RUBY

  def test_every_rule_is_stable_across_runs_line_endings_and_duplicates
    scanner = Master::Review::Scan::InfraHelpers.build_scanner(root: Master::ROOT)
    path = File.join(Master::ROOT, "lib", "example_input_shapes.rb")
    rules = scanner.rules.select { |rule| rule.respond_to?(:check) }
    defects = rules.flat_map { |rule| input_shape_defects(rule, path) }

    assert_operator rules.size, :>, 100, "the registry is not being read"
    assert_empty defects, defects.join("\n")
  end

  private

  def input_shape_defects(rule, path)
    first = Array(rule.check(PLANTED, path:))
    again = Array(rule.check(PLANTED, path:))
    windows = Array(rule.check(PLANTED.gsub("\n", "\r\n"), path:))
    problems = []
    problems << "answers differently on a second run" unless first == again
    problems << "reports a finding twice" unless first.size == first.uniq.size
    unless finding_lines(first) == finding_lines(windows)
      problems << "moves lines under CRLF: #{finding_lines(first)} vs #{finding_lines(windows)}"
    end
    problems.map { |problem| "#{rule.id}: #{problem}" }
  rescue StandardError => e
    ["#{rule.id}: raised #{e.class}: #{e.message.lines.first}"]
  end

  def finding_lines(findings) = findings.map { |finding| finding.line.to_i }.sort
end
