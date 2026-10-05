# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

class TestAxioms < Minitest::Test
  def test_foreign_root_uses_its_law_registry_and_voice
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "law"))
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(File.join(dir, "data", "voice.yml"), "voice:
  style: local-root-style
")
      File.write(File.join(dir, "data", "laws.yml"), "foreign:
  priority: 1
  principle: foreign
")
      File.write(File.join(dir, "law", "probe.rb"), <<~RUBY)
        Law.define(:FOREIGN_ROOT_RULE) do
          source "test"
          severity :info
          practice "foreign root"
          fix "keep it"
          bad "bad"
          good "good"
        end
      RUBY

      rules = Master::Ground::Rules.new(root: dir)

      assert_equal "local-root-style", rules.voice.fetch("style")
      assert_equal "foreign root", rules.rules.fetch("FOREIGN_ROOT_RULE")
    ensure
      Law.load_all(File.join(Master::ROOT, "law"))
    end
  end

  def test_rules_refresh_derived_views_when_laws_change
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "data"))
      path = File.join(dir, "data", "laws.yml")
      write = ->(name, tier) do
        File.write(path, "#{name}:
  priority: 1
  principle: #{name}
  tier: #{tier}
")
      end

      write.call("FIRST", "kernel")
      rules = Master::Ground::Rules.new(root: dir)

      assert rules.kernel.key?("FIRST")
      refute rules.philosophy.any? { |row| row["id"] == "FIRST" }

      write.call("SECOND", "design")

      refute rules.kernel.key?("FIRST")
      assert rules.philosophy.any? { |row| row["id"] == "SECOND" }
    end
  end

  def setup
    @rules = Master::Ground::Rules.new
  end

  def test_kernel_not_empty
    refute @rules.kernel.empty?, "kernel axioms must be present"
  end

  def test_kernel_has_preserve_first
    assert @rules.kernel.key?("PRESERVE_FIRST")
  end

  def test_philosophy_sorted_by_priority
    items = @rules.philosophy
    refute items.empty?
    priorities = items.map { |a| a["priority"].to_i }
    assert_equal priorities.sort, priorities
  end

  def test_kernel_block_formatted
    block = @rules.kernel_block
    assert block.include?("## Kernel Rules")
    assert block.include?("PRESERVE_FIRST")
  end

  def test_philosophy_block_limit
    block = @rules.philosophy_block(limit: 3)
    assert block.include?("(top 3)")
  end

  def test_lookup_kernel
    val = @rules.lookup("PRESERVE_FIRST")
    refute_nil val
    assert val.length > 5
  end
  # voice.yml carried a shadow copy of soul absolute.anti_simulation that the
  # accessor read only if soul lost the key — and it had drifted a word. The
  # shadow is deleted (2026-08-21); soul is the one source, and this holds it.
  def test_constitution_carries_anti_simulation_from_soul
    anti = @rules.constitution["anti_simulation"]
    refute_nil anti, "soul absolute.anti_simulation must reach the constitution accessor"
    assert_equal %w[will would could might], anti["forbidden"]
    assert anti.dig("require_evidence", "completion"), "evidence contract must survive"
  end

end
