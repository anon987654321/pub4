# frozen_string_literal: true

require "minitest/autorun"
require_relative "../event_bus_reach"

class TestEventBusReach < Minitest::Test
  def test_ruby_extracts_only_literal_publishers_and_subscribers
    source = <<~RUBY
      # bus.publish("comment:fake")
      bus.publish("pipeline:stage_start")
      @bus.subscribe("agent:mood") { |event| event }
      bus.publish(topic)
      subscribe("dynamic:" + suffix)
    RUBY

    assert_equal [
      { topic: "pipeline:stage_start", role: :publisher },
      { topic: "agent:mood", role: :subscriber },
    ], Operator::EventBusReach.ruby_events(source)
  end

  def test_ruby_extracts_safe_navigation_publishers
    rows = Operator::EventBusReach.ruby_events('bus&.publish("phantom:recovery", step: 1)')

    assert_equal [{ topic: "phantom:recovery", role: :publisher }], rows
  end

  def test_javascript_ignores_comments_and_finds_regex_references
    source = <<~JS
      // window.addEventListener("comment:fake", handler)
      window.addEventListener("pipeline:stage_start", handler)
      emitTtsEvent("tts:started")
      const classify = /phantom:recovery|pipeline:stage_start/i;
      const url = "https://example.test/path";
    JS

    rows = Operator::EventBusReach.js_events(source)
    listeners = rows.select { |row| row[:role] == :listener }.map { |row| row[:topic] }
    publishers = rows.select { |row| row[:role] == :publisher }.map { |row| row[:topic] }
    refs = rows.select { |row| row[:role] == :reference }.map { |row| row[:topic] }

    assert_equal ["pipeline:stage_start"], listeners
    assert_equal ["tts:started"], publishers
    assert_includes refs, "phantom:recovery"
    assert_includes refs, "pipeline:stage_start"
    refute_includes refs, "comment:fake"
  end

  def test_current_tree_exposes_real_face_topics_without_stale_aliases
    result = Operator::EventBusReach.report

    refute_includes result[:unpublished], "phantom:retry"
    refute_includes result[:unpublished], "pipeline:start"

    assert_includes result[:publishers], "phantom:detected"
    assert_includes result[:publishers], "phantom:occurrence"
    assert_includes result[:publishers], "phantom:recovery"
    assert_includes result[:publishers], "pipeline:stage_start"
    assert_includes result[:references].fetch("phantom:recovery"), "web/public/visual_bridge.js"
    assert_includes result[:references].fetch("pipeline:stage_start"), "web/public/face_semantics.js"
  end

  def test_operator_exposes_the_census
    source = File.read(File.expand_path("../../bin/operator", __dir__))
    assert_includes source, 'when "event-bus"'
    assert_includes source, 'MASTER", "tools", "event_bus_reach.rb"'
  end
end
