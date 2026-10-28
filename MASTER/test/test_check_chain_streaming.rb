# frozen_string_literal: true

require_relative "test_helper"
require "rbconfig"
require_relative "../lib/operator/check_chain"

class TestCheckChainStreaming < Minitest::Test
  class TimedSink
    attr_reader :events

    def initialize
      @events = []
    end

    def write(text)
      @events << [Process.clock_gettime(Process::CLOCK_MONOTONIC), text.dup]
      text.bytesize
    end

    def flush
      self
    end
  end

  def test_capture_forwards_child_output_before_the_child_exits
    sink = TimedSink.new
    previous_stdout = $stdout
    $stdout = sink
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    script = '$stdout.sync = true; puts "scan-start"; sleep 1.0; puts "scan-finish"'

    ok, output, status = Operator::CheckChain.capture(RbConfig.ruby, "-e", script, chdir: Master::ROOT)

    assert ok
    assert_equal 0, status
    assert_equal %w[scan-start scan-finish], output
    first = sink.events.find { |_at, text| text.include?("scan-start") }
    refute_nil first
    assert_operator first.first - started, :<, 0.8, "capture waited for the child before forwarding its first line"
  ensure
    $stdout = previous_stdout
  end
end
