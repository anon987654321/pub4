# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"
require "tmpdir"
require "fileutils"

class TestAgentMap < Minitest::Test
  def test_patch_brief_exact_file
    brief = Master::Ground::Map::Agent.patch_brief("data/soul.yml")
    assert_includes brief, "patch brief: data/soul.yml"
    assert_includes brief, "check: bin/check --profile=agent"
    assert_includes brief, "topic: law"
  end

  def test_patch_brief_directory_prefix
    brief = Master::Ground::Map::Agent.patch_brief("lib/cli/turn_router.rb")
    assert_includes brief, "patch brief: lib/cli/turn_router.rb"
    assert_includes brief, "check: bin/check --profile=agent"
  end

  def test_patch_brief_face_runtime_generated_note
    brief = Master::Ground::Map::Agent.patch_brief("RAILS/master/public/face.runtime.js")
    assert_includes brief, "generated"
  end

  def test_core_directory_patch_brief_uses_the_live_lib_core_path
    brief = Master::Ground::Map::Agent.patch_brief("lib/core/world.rb")
    assert_includes brief, "patch brief: lib/core/world.rb"
    assert_includes brief, "constitutional fold spine"
  end

  def test_live_agent_map_references_resolve
    assert_empty Master::Ground::Map::Agent.integrity
  end

  def test_integrity_rejects_missing_topic_and_patch_brief_paths
    Dir.mktmpdir("agent-map-integrity") do |root|
      FileUtils.mkdir_p(File.join(root, "data"))
      File.write(File.join(root, "data", "agent_map.yml"), <<~YAML)
        topics:
          example:
            files: [lib/missing.rb]
        patch_briefs:
          lib/missing_brief.rb:
            check: rake test
      YAML

      findings = Master::Ground::Map::Agent.integrity(root:)
      assert findings.any? { |finding| finding.include?("topics.example.files") && finding.include?("lib/missing.rb") }
      assert findings.any? { |finding| finding.include?("patch_briefs") && finding.include?("lib/missing_brief.rb") }
    end
  end

  def test_format_topics_includes_law
    topics = Master::Ground::Map::Agent.format_topics
    assert_includes topics, "law:"
    assert_includes topics, "face_boot:"
  end
end
