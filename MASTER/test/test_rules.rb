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
  def test_root_specific_voice_data_does_not_leak_from_master
    Dir.mktmpdir("rules_root") do |root|
      data = File.join(root, "data")
      FileUtils.mkdir_p(data)
      File.write(File.join(data, "laws.yml"), "{}\n")
      File.write(
        File.join(data, "voice.yml"),
        "voice:\n  custom_marker: temporary-root\n"
      )

      rules = Master::Ground::Rules.new(root:)
      assert_equal "temporary-root", rules.data(:voice).fetch("custom_marker")
    end
  end

  def test_rules_refresh_laws_after_live_edit
    Dir.mktmpdir("rules_live_laws") do |root|
      data = File.join(root, "data")
      FileUtils.mkdir_p(data)
      write_laws = lambda do |name|
        File.write(File.join(data, "laws.yml"), {
          "TEMP_RULE" => {
            "priority" => 1,
            "principle" => "temporary",
            "tier" => "kernel",
            "name" => name,
          },
        }.to_yaml)
      end

      write_laws.call("first")
      rules = Master::Ground::Rules.new(root:)
      assert_equal "first", rules.lookup("TEMP_RULE")

      write_laws.call("second")
      assert_equal "second", rules.lookup("TEMP_RULE")
    end
  end

  def test_rules_refresh_voice_after_live_edit
    Dir.mktmpdir("rules_live_voice") do |root|
      data = File.join(root, "data")
      FileUtils.mkdir_p(data)
      path = File.join(data, "voice.yml")
      File.write(path, "voice:\n  custom_marker: first\n")

      rules = Master::Ground::Rules.new(root:)
      assert_equal "first", rules.voice.fetch("custom_marker")

      File.write(path, "voice:\n  custom_marker: second\n")
      assert_equal "second", rules.voice.fetch("custom_marker")
    end
  end

  def test_deleted_data_file_drops_cached_payload
    Dir.mktmpdir("rules_data_delete") do |root|
      data = File.join(root, "data")
      FileUtils.mkdir_p(data)
      laws = File.join(data, "laws.yml")
      File.write(laws, "voice:\n  marker: folded\n")
      voice = File.join(data, "voice.yml")
      File.write(voice, "voice:\n  marker: file\n")

      rules = Master::Ground::Rules.new(root:)
      assert_equal "file", rules.data(:voice).fetch("voice").fetch("marker")

      File.delete(voice)

      assert_equal "folded", rules.data(:voice).fetch("marker")
    end
  end

  def test_long_lived_rules_refresh_soul_data_after_edit
    Dir.mktmpdir("rules_soul_refresh") do |root|
      data = File.join(root, "data")
      FileUtils.mkdir_p(data)
      File.write(File.join(data, "laws.yml"), "{}\n")
      soul = File.join(data, "soul.yml")
      File.write(soul, "absolute:\n  golden_rule: first\n")

      rules = Master::Ground::Rules.new(root:)
      assert_equal "first", rules.soul_data.fetch("absolute").fetch("golden_rule")

      File.write(soul, "absolute:\n  golden_rule: second\n")

      assert_equal "second", rules.soul_data.fetch("absolute").fetch("golden_rule")
      assert_equal "second", rules.constitution.fetch("golden_rule")
    end
  end

  def test_constitution_carries_anti_simulation_from_soul
    anti = @rules.constitution["anti_simulation"]
    refute_nil anti, "soul absolute.anti_simulation must reach the constitution accessor"
    assert_equal %w[will would could might], anti["forbidden"]
    assert anti.dig("require_evidence", "completion"), "evidence contract must survive"
  end

end
