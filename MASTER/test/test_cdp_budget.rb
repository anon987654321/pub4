# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require File.expand_path("../gates/support/cdp_session", __dir__)
require File.expand_path("../lib/trace/dmesg", __dir__)
require File.expand_path("../lib/fix/visual_surface_budget", __dir__)

# A surface that outlives its budget fails with a reason instead of looping in
# the transport. No browser: the session is built but never started.
class TestCdpBudget < Minitest::Test
  Surface = Struct.new(:id)

  def session = Deploy::CdpSession.new

  def test_commands_past_the_deadline_are_refused_with_the_command_named
    cdp = session
    error = assert_raises(Deploy::CdpBudget::Exceeded) do
      cdp.with_budget(0.0, "brgen/home/mobile") { cdp.command("Page.enable") }
    end
    assert_match(/Page\.enable refused/, error.message)
  end

  def test_a_timeout_swallowed_by_the_caller_still_ends_in_exceeded
    cdp = session
    error = assert_raises(Deploy::CdpBudget::Exceeded) do
      cdp.with_budget(0.01, "brgen/home/mobile") do
        sleep 0.05
        raise Deploy::CdpSession::Timeout, "CDP timeout: DOM.getAttributes"
      end
    end
    assert_match(%r{brgen/home/mobile exceeded its 0\.01s budget}, error.message)
  end

  def test_surface_runner_reports_progress_and_the_reason_then_returns_nil
    io = StringIO.new
    cdp = session
    result = Master::Fix::VisualSurfaceBudget.run(cdp, Surface.new("brgen/home/mobile"), 2, 41, seconds: 0.0, io:) do
      cdp.command("Runtime.evaluate")
    end
    assert_nil result
    assert_match(%r{capturing brgen/home/mobile 3/41}, io.string)
    assert_match(%r{FAILED brgen/home/mobile 3/41: .*budget}, io.string)
  end

  def test_within_budget_returns_the_block_value
    io = StringIO.new
    assert_equal :done, Master::Fix::VisualSurfaceBudget.run(session, Surface.new("a/b/c"), 0, 1, seconds: 5, io:) { :done }
  end
end

class TestSurfaceFailureIsolation < Minitest::Test
  def test_a_raising_probe_fails_only_its_surface
    io = StringIO.new
    cdp = Deploy::CdpSession.new
    surface = TestCdpBudget::Surface.new("brgen/x/mobile")
    result = Master::Fix::VisualSurfaceBudget.run(cdp, surface, 0, 2, io:) { raise "web_platform: runtime probe failed" }

    assert_nil result
    assert_match(%r{FAILED brgen/x/mobile 1/2: RuntimeError: web_platform}, io.string)
  end
end
