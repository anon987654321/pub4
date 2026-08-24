# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

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
    brief = Master::Ground::Map::Agent.patch_brief("web/public/face.runtime.js")
    assert_includes brief, "generated"
  end

  def test_format_topics_includes_law
    topics = Master::Ground::Map::Agent.format_topics
    assert_includes topics, "law:"
    assert_includes topics, "face_boot:"
  end
end
