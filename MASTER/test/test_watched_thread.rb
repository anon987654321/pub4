# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/builder/ai_boot"

class WatchedThreadTest < Minitest::Test
  class RecordingBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(name, **payload)
      @events << [name, payload]
    end
  end

  def test_background_thread_failure_is_published_and_logged
    bus = RecordingBus.new

    Master::Trace::Dmesg.stub(:status, nil) do
      thread = Master::Builder.watched_thread(bus, "builder_self_test") { raise "boom" }
      thread.join
      refute thread.alive?
    end

    event = bus.events.fetch(0)
    assert_equal "boot:thread_died", event.fetch(0)
    assert_equal "builder_self_test", event.fetch(1).fetch(:where)
    assert_equal "RuntimeError: boom", event.fetch(1).fetch(:error)
  end

  def test_non_strict_boot_routes_self_test_through_watched_thread
    source = File.read(File.join(Master::ROOT, "lib", "builder", "ai_boot.rb"))

    assert_includes source, 'strict_boot_requested? ? run.call : watched_thread(bus, "builder_self_test", &run)'
    refute_includes source, "Thread.new(&run).tap { |thread| thread.report_on_exception = false }"
  end
end
