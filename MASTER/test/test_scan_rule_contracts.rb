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
    "scss" => ".scss", "zsh" => ".zsh", "javascript" => ".js",
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

  def test_strict_mode_zsh_rule_flags_missing_set_e
    refute_empty law_findings("STRICT_MODE_ZSH", "#!/usr/bin/env zsh\necho ok\n", path: "script.zsh")
  end

  # A comment between the shebang and `set -euo pipefail` is the normal
  # shape; the pre-retirement law demanded set on the very next line.
  def test_strict_mode_zsh_accepts_set_e_after_a_comment
    assert_empty law_findings("STRICT_MODE_ZSH", "#!/usr/bin/env zsh\n# header\nset -euo pipefail\n", path: "script.zsh")
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

  def test_coupler_rule_flags_message_chains
    code = "def call\n  user.account.profile.address.city.name\nend\n"

    assert_finding Rules::CouplerRule.new, code, "chain.rb", "message chain"
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
    bad = File.join(Master::ROOT, "data", "principles", "feedback_new.md")
    good = File.join(Master::ROOT, "data", "SOUL.md")

    assert_finding rule("RUNTIME_DOCS_YAML"), "# stray\n", bad, "rules.yml#operator_principles"
    assert_empty rule("RUNTIME_DOCS_YAML").check("# ok\n", path: good)
    # data/skills/README.md left the allowed list when the directory was
    # deleted (2026-08-19) — a reborn copy is a finding now, not an exemption.
    assert_finding rule("RUNTIME_DOCS_YAML"), "# reborn\n",
                   File.join(Master::ROOT, "data", "skills", "README.md"), "delete data/skills/README.md"
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

end
