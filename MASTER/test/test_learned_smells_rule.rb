# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "master"
require "review/scan/rules/meta_rules"

class LearnedSmellsRuleSpec < Minitest::Test
  def test_learned_smell_rules_are_loaded_from_rules_yml
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(
        File.join(dir, "data", "rules.yml"),
        <<~YAML,
          learned_smells:
            - id: SESSION_GUARD_CLAUSE
              pattern: 'guard clause'
              message: 'guard clauses should be named explicitly'
              severity: warning
              tags: [SESSION, LEARNED]
              mediums: [ruby]
        YAML
      )

      rule = Master::Review::Scan::Rules::LearnedSmellsRule.new(root: dir)
      findings = rule.check("guard clause\n", path: File.join(dir, "app", "demo.rb"))

      assert_equal 1, findings.size
      assert_equal "SESSION_GUARD_CLAUSE", findings.first.rule_id
      assert_equal "guard clauses should be named explicitly", findings.first.message
      assert_equal :warning, findings.first.severity
    end
  end

  def test_learned_smell_rules_ignore_other_languages
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(
        File.join(dir, "data", "rules.yml"),
        <<~YAML,
          learned_smells:
            - id: RUBY_ONLY
              pattern: 'needle'
              message: 'ruby only smell'
              mediums: [ruby]
        YAML
      )

      rule = Master::Review::Scan::Rules::LearnedSmellsRule.new(root: dir)
      findings = rule.check("needle\n", path: File.join(dir, "app", "demo.js"))

      assert_equal [], findings
    end
  end
end
