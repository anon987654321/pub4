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

  def test_secret_proximity_rule_flags_hardcoded_secret
    assert_finding rule("SECRET_PROXIMITY"), 'api_key = "123456789"', "app.rb", "hardcoded secret"
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

  def test_strict_mode_zsh_rule_flags_missing_set_e
    assert_finding rule("STRICT_MODE_ZSH"), "#!/usr/bin/env zsh\necho ok\n", "script.zsh", "missing set"
  end

  def test_keyword_args_rule_flags_three_positionals
    assert_finding rule("KEYWORD_ARGS"), "def call(a, b, c)\nend\n", "args.rb", "positional args"
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
end
