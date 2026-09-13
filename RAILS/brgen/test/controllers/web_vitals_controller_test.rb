# frozen_string_literal: true

require "test_helper"

# The field sampler beacons LCP, INP and CLS, and with INP the element behind
# the slowest interaction, so a slow number in the log names a control. The
# target is browser-built text, so only selector characters reach the log.
class WebVitalsControllerTest < ActionDispatch::IntegrationTest
  setup { host! "brgen.no" }

  def logged_line
    io = StringIO.new
    capture = ActiveSupport::Logger.new(io)
    Rails.logger.broadcast_to(capture)
    yield
    io.string.lines.find { |line| line.include?("web_vitals ") }
  ensure
    Rails.logger.stop_broadcasting_to(capture)
  end

  test "an interaction target reaches the log as a selector" do
    line = logged_line do
      post "/web_vitals", params: { inp: "340", inp_target: "button.vote-btn[data-controller=action]", path: "/" }
    end

    assert_response :no_content
    assert_includes line, "inp=340"
    assert_includes line, "inp_target=button.vote-btn[data-controller=action]"
  end

  test "a target carrying anything but selector characters is stripped" do
    line = logged_line do
      post "/web_vitals", params: { inp: "90", inp_target: "div\nforged=1 <script>", path: "/" }
    end

    assert_includes line, "inp_target=divforged=1script"
    refute_includes line.chomp, "\n"
  end

  test "a beacon with no metric is refused" do
    post "/web_vitals", params: { path: "/" }

    assert_response :bad_request
  end
end
