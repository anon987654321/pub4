# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/law_map_repair"

class TestLawMapRepair < Minitest::Test
  FIXTURE = <<~YAML
    law_map:
      schema: 1
      laws:
        accessibility:
          meaning: usable by people with diverse abilities
          detects: accessibility_violation
          severity: critical
          confidence: 0.9
          operation: fix_accessibility
          law_ids:
          - ARIA_INTERACTIVE
          - FAKE_DANGLING_LAW
          - IMG_ALT
          status: covered
          tags:
          - ui
        other_law:
          meaning: something else
          detects: other_thing
          severity: high
          confidence: 0.8
          operation: fix_other
          law_ids:
          - ANOTHER_FAKE_LAW
          status: covered
          tags:
          - code
  YAML

  def test_fix_removes_only_genuinely_dangling_law_ids
    with_fixture do |root|
      fixed = Master::Fix::LawMapRepair.fix!(root:)

      assert_equal [%w[accessibility FAKE_DANGLING_LAW], %w[other_law ANOTHER_FAKE_LAW]], fixed

      rewritten = Master::Ground::Map::LawMap.load(root:)
      assert_equal %w[ARIA_INTERACTIVE IMG_ALT], rewritten.laws["accessibility"].law_ids
      assert_equal [], rewritten.laws["other_law"].law_ids
    end
  end

  def test_fix_removes_a_dangling_id_from_a_one_line_row
    with_fixture do |root|
      row = '    flow_law: {"law_ids": ["IMG_ALT", "FLOW_DANGLING"], "status": "covered"}'
      File.write(File.join(root, "data", "laws.yml"), "#{FIXTURE}#{row}\n")

      assert_includes Master::Fix::LawMapRepair.fix!(root:), %w[flow_law FLOW_DANGLING]
      assert_equal %w[IMG_ALT], Master::Ground::Map::LawMap.load(root:).laws["flow_law"].law_ids
    end
  end

  def test_fix_is_a_noop_on_a_clean_file
    with_fixture do |root|
      fixture = FIXTURE.sub("\n      - FAKE_DANGLING_LAW", "").sub("ANOTHER_FAKE_LAW", "IMG_ALT")
      File.write(File.join(root, "data", "laws.yml"), fixture)
      assert_equal [], Master::Fix::LawMapRepair.fix!(root:)
      refute File.exist?(File.join(root, "data", "laws.yml.bak"))
    end
  end

  def test_refuses_to_touch_anything_if_registry_looks_unpopulated
    with_fixture do |root|
      Master::Review::Scan::LawTree.stub(:ids, []) do
        assert_equal [], Master::Fix::LawMapRepair.fix!(root:)
      end

      refute File.exist?(File.join(root, "data", "laws.yml.bak"))
      assert_includes File.read(File.join(root, "data", "laws.yml")), "ARIA_INTERACTIVE"
    end
  end

  private

  def with_fixture
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "data"))
      File.write(File.join(root, "data", "laws.yml"), FIXTURE)
      yield root
    end
  end
end
