# frozen_string_literal: true

require_relative "test_helper"

class TestAxioms < Minitest::Test
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
  def test_removed_standalone_data_file_falls_back_to_consolidated_laws
    Dir.mktmpdir do |dir|
      data = File.join(dir, "data")
      Dir.mkdir(data)
      File.write(File.join(data, "laws.yml"), "style:\n  source: consolidated\n")
      standalone = File.join(data, "style.yml")
      File.write(standalone, "source: standalone\n")

      rules = Master::Ground::Rules.new(root: dir)
      assert_equal "standalone", rules.data(:style).fetch("source")

      File.delete(standalone)

      assert_equal "consolidated", rules.data(:style).fetch("source")
    end
  end

  def test_rules_uses_the_foreign_root_law_registry
    Dir.mktmpdir do |dir|
      law_dir = File.join(dir, "law")
      data_dir = File.join(dir, "data")
      FileUtils.mkdir_p(law_dir)
      FileUtils.mkdir_p(data_dir)
      File.write(File.join(data_dir, "laws.yml"), "foreign: \n  priority: 1\n  principle: foreign\n")
      File.write(File.join(law_dir, "probe.rb"), <<~RUBY)
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

      assert_equal "foreign root", rules.rules.fetch("FOREIGN_ROOT_RULE")
    ensure
      Law.load_all(File.join(Master::ROOT, "law"))
    end
  end

  def test_rules_refresh_folded_law_data_and_derived_views
    Dir.mktmpdir do |dir|
      data_dir = File.join(dir, "data")
      FileUtils.mkdir_p(data_dir)
      path = File.join(data_dir, "laws.yml")
      write_law_data = lambda do |name, tier|
        File.write(path, <<~YAML)
          #{name}:
            priority: 1
            principle: "#{name}"
            tier: #{tier}
        YAML
      end

      write_law_data.call("FIRST", "kernel")
      rules = Master::Ground::Rules.new(root: dir)

      assert rules.kernel.key?("FIRST")
      assert_equal "FIRST", rules.philosophy.find { |row| row["id"] == "FIRST" }&.fetch("id")

      write_law_data.call("SECOND", "design")

      refute rules.kernel.key?("FIRST")
      assert rules.philosophy.any? { |row| row["id"] == "SECOND" }
    end
  end

  def test_foreign_root_uses_that_tree_voice_configuration
    Dir.mktmpdir do |dir|
      Dir.mkdir(File.join(dir, "data"))
      File.write(File.join(dir, "data", "voice.yml"), "voice:\n  style: local-root-style\n")

      rules = Master::Ground::Rules.new(root: dir)

      assert_equal "local-root-style", rules.voice.fetch("style")
    end
  end

  def test_constitution_carries_anti_simulation_from_soul
    anti = @rules.constitution["anti_simulation"]
    refute_nil anti, "soul absolute.anti_simulation must reach the constitution accessor"
    assert_equal %w[will would could might], anti["forbidden"]
    assert anti.dig("require_evidence", "completion"), "evidence contract must survive"
  end

end
