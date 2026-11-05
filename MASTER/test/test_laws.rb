# frozen_string_literal: true

require_relative "test_helper"

class TestAxioms < Minitest::Test
  def setup
    @laws = Master::Ground::Laws.new
  end

  def test_kernel_not_empty
    refute @laws.kernel.empty?, "kernel axioms must be present"
  end

  def test_kernel_has_preserve_first
    assert @laws.kernel.key?("PRESERVE_FIRST")
  end

  def test_philosophy_preserves_canonical_document_order_without_priority_fields
    items = @laws.philosophy
    refute_empty items

    ids = items.map { |law| law.fetch("id") }
    expected = Master.law_entries(root: Master::ROOT).map { |law| law.fetch("id") }
    assert_equal expected, ids
    refute items.any? { |law| law.key?("priority") }
  end

  def test_kernel_block_formatted
    block = @laws.kernel_block
    assert block.include?("## Kernel Laws")
    assert block.include?("PRESERVE_FIRST")
  end

  def test_philosophy_block_limit
    block = @laws.philosophy_block(limit: 3)
    assert block.include?("(top 3)")
  end

  def test_lookup_kernel
    val = @laws.lookup("PRESERVE_FIRST")
    refute_nil val
    assert val.length > 5
  end

  def test_root_specific_voice_data_does_not_leak_from_master
    Dir.mktmpdir("rules_root") do |root|
      data = File.join(root, "data")
      FileUtils.mkdir_p(data)
      File.write(File.join(data, "laws.yml"), "{}\n")
      File.write(
        File.join(data, "voice.yml"),
        "voice:\n  custom_marker: temporary-root\n",
      )

      laws = Master::Ground::Laws.new(root:)
      assert_equal "temporary-root", laws.data(:voice).fetch("voice").fetch("custom_marker")
    end
  end

  def test_rules_refresh_laws_after_live_edit
    Dir.mktmpdir("rules_live_laws") do |root|
      data = File.join(root, "data")
      FileUtils.mkdir_p(data)
      write_laws = lambda do |name|
        File.write(File.join(data, "laws.yml"), {
          "TEMP_RULE" => {
            "root" => "no_surplus",
            "statement" => name,
          },
        }.to_yaml)
      end

      write_laws.call("first")
      laws = Master::Ground::Laws.new(root:)
      assert_equal "first", laws.lookup("TEMP_RULE")

      write_laws.call("second")
      assert_equal "second", laws.lookup("TEMP_RULE")
    end
  end

  def test_rules_refresh_voice_after_live_edit
    Dir.mktmpdir("rules_live_voice") do |root|
      data = File.join(root, "data")
      FileUtils.mkdir_p(data)
      path = File.join(data, "voice.yml")
      File.write(path, "voice:\n  custom_marker: first\n")

      laws = Master::Ground::Laws.new(root:)
      assert_equal "first", laws.voice.fetch("custom_marker")

      File.write(path, "voice:\n  custom_marker: second\n")
      assert_equal "second", laws.voice.fetch("custom_marker")
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

      laws = Master::Ground::Laws.new(root:)
      assert_equal "file", laws.data(:voice).fetch("voice").fetch("marker")

      File.delete(voice)

      assert_equal "folded", laws.data(:voice).fetch("marker")
    end
  end

  def test_long_lived_rules_refresh_soul_data_after_edit
    Dir.mktmpdir("rules_soul_refresh") do |root|
      data = File.join(root, "data")
      FileUtils.mkdir_p(data)
      File.write(File.join(data, "laws.yml"), {
        "PRESERVE_FIRST" => { "parent" => "STEWARDSHIP", "statement" => "first preservation contract" },
        "SECOND_PRESERVE" => { "parent" => "STEWARDSHIP", "statement" => "second preservation contract" },
        "STEWARDSHIP" => { "root" => "stewardship", "statement" => "preserve what works" },
        "TRUTHFUL_STATUS" => { "node" => "truthful_status", "statement" => "report evidence" },
        "SACRED_AUTHORSHIP" => { "root" => "least_authority", "statement" => "protect paths" },
      }.to_yaml)
      soul = File.join(data, "soul.yml")
      # Protected paths live in soul.yml; laws.yml carries no path list.
      sacred = "absolute:\n  sacred_paths:\n    - data/laws.yml\n"
      File.write(soul, "references:\n  golden_law: PRESERVE_FIRST\n#{sacred}")

      laws = Master::Ground::Laws.new(root:)
      assert_equal "PRESERVE_FIRST", laws.soul_data.fetch("references").fetch("golden_law")

      File.write(soul, "references:\n  golden_law: SECOND_PRESERVE\n#{sacred}")

      assert_equal "SECOND_PRESERVE", laws.soul_data.fetch("references").fetch("golden_law")
      assert_equal "SECOND_PRESERVE: second preservation contract", laws.constitution.fetch("golden_law")
    end
  end

  # TRUTHFUL_STATUS owns the repository-work scope and evidence requirements;
  # Soul owns the global forbidden-word list.
  def test_constitution_composes_anti_simulation_from_law_and_soul
    anti = @laws.constitution["anti_simulation"]
    refute_nil anti, "TRUTHFUL_STATUS must own its anti-simulation evidence contract"
    assert_equal "repository_work_claims", anti["scope"]
    assert_equal %w[will would could might], anti["forbidden"]
    assert anti.dig("require_evidence", "completion"), "evidence contract must survive"
    assert_equal anti["forbidden"], @laws.soul_data.dig("absolute", "anti_simulation", "forbidden")
  end
end
