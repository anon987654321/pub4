# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/ground/principle_map_repair"

class TestPrincipleMapRepair < Minitest::Test
  FIXTURE = <<~YAML
    schema: 1
    principles:
      accessibility:
        meaning: usable by people with diverse abilities
        detects: accessibility_violation
        severity: critical
        confidence: 0.9
        operation: fix_accessibility
        rule_ids:
        - ARIA_INTERACTIVE
        - FAKE_DANGLING_RULE
        - IMG_ALT
        status: covered
        tags:
        - ui
      other_principle:
        meaning: something else
        detects: other_thing
        severity: high
        confidence: 0.8
        operation: fix_other
        rule_ids:
        - ANOTHER_FAKE_RULE
        status: covered
        tags:
        - code
  YAML

  # bin/doctor --fix's config self-repair: dangling rule_ids (pointing at
  # a RuleDSL id that no longer exists) are broken pointers, safe to
  # auto-remove -- found and fixed by hand twice this session before this
  # existed. ARIA_INTERACTIVE/IMG_ALT are real, currently-registered rule
  # ids and must survive; only the two made-up ones should go.
  def test_fix_removes_only_genuinely_dangling_rule_ids
    with_fixture do |root|
      fixed = Master::Ground::PrincipleMapRepair.fix!(root:)

      assert_equal [%w[accessibility FAKE_DANGLING_RULE], %w[other_principle ANOTHER_FAKE_RULE]], fixed

      rewritten = Master::Ground::Map::Principle.load(root:)
      assert_equal %w[ARIA_INTERACTIVE IMG_ALT], rewritten.principles["accessibility"].rule_ids
      assert_equal [], rewritten.principles["other_principle"].rule_ids
    end
  end

  def test_fix_backs_up_the_original_file
    with_fixture do |root|
      Master::Ground::PrincipleMapRepair.fix!(root:)

      backup = File.join(root, "data", "principle_map.yml.bak")
      assert File.exist?(backup)
      assert_includes File.read(backup), "FAKE_DANGLING_RULE"
    end
  end

  def test_fix_is_a_noop_on_a_clean_file
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "data"))
      File.write(File.join(root, "data", "principle_map.yml"), <<~YAML)
        schema: 1
        principles:
          accessibility:
            meaning: usable by people with diverse abilities
            rule_ids:
            - ARIA_INTERACTIVE
            status: covered
            tags: []
      YAML

      assert_equal [], Master::Ground::PrincipleMapRepair.fix!(root:)
      refute File.exist?(File.join(root, "data", "principle_map.yml.bak"))
    end
  end

  # The whole reason MIN_REGISTRY_SIZE exists: proven live while building
  # this that an unpopulated registry makes every rule_id look dangling.
  def test_refuses_to_touch_anything_if_registry_looks_unpopulated
    with_fixture do |root|
      Master::Review::Scan::Rule.stub(:registry, []) do
        assert_equal [], Master::Ground::PrincipleMapRepair.fix!(root:)
      end

      refute File.exist?(File.join(root, "data", "principle_map.yml.bak"))
      assert_includes File.read(File.join(root, "data", "principle_map.yml")), "ARIA_INTERACTIVE"
    end
  end

  private

  def with_fixture
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "data"))
      File.write(File.join(root, "data", "principle_map.yml"), FIXTURE)
      yield root
    end
  end
end
