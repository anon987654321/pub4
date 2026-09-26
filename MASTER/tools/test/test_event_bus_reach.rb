# frozen_string_literal: true

require "minitest/autorun"
require_relative "../event_bus_reach"

class TestEventBusReach < Minitest::Test
  def test_ruby_extracts_only_literal_publishers_and_subscribers
    source = <<~RUBY
      # bus.publish("comment:fake")
      bus.publish("pipeline:start")
      @bus.subscribe("agent:mood") { |event| event }
      bus.publish(topic)
      subscribe("dynamic:" + suffix)
    RUBY

    assert_equal [
      { topic: "pipeline:start", role: :publisher },
      { topic: "agent:mood", role: :subscriber },
    ], Operator::EventBusReach.ruby_events(source)
  end

  def test_javascript_ignores_comments_and_finds_regex_references
    source = <<~JS
      // window.addEventListener("comment:fake", handler)
      window.addEventListener("pipeline:stage_start", handler)
      emitTtsEvent("tts:started")
      const classify = /phantom:retry|pipeline:start/i;
      const url = "https://example.test/path";
    JS

    rows = Operator::EventBusReach.js_events(source)
    listeners = rows.select { |row| row[:role] == :listener }.map { |row| row[:topic] }
    publishers = rows.select { |row| row[:role] == :publisher }.map { |row| row[:topic] }
    refs = rows.select { |row| row[:role] == :reference }.map { |row| row[:topic] }

    assert_equal ["pipeline:stage_start"], listeners
    assert_equal ["tts:started"], publishers
    assert_includes refs, "phantom:retry"
    assert_includes refs, "pipeline:start"
    refute_includes refs, "comment:fake"
  end

  def test_current_tree_exposes_the_known_unpublished_topics
    result = Operator::EventBusReach.report

    %w[agent:mood phantom:retry pipeline:start].each do |topic|
      assert_includes result[:unpublished], topic
    end

    assert_includes result[:subscribers].fetch("agent:mood"), "web/app/services/chat_service.rb"
    assert_includes result[:references].fetch("phantom:retry"), "web/public/topology_registry.js"
    assert_includes result[:references].fetch("pipeline:start"), "web/public/face_semantics.js"
  end
end
