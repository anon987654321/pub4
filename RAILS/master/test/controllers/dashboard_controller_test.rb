# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  # Through the key, not the English literal. This app serves nb by default, so
  # "mission control" is not what the page says — and a test that pins the
  # English spelling is a test that fails on a correct translation.
  test "index renders the mission control shell" do
    get "/dashboard"

    assert_response :success
    assert_includes response.body, I18n.t("dashboard.heading_mission")
    assert_select "#refresh-state[role='status']"
    assert_select "#status[aria-live='polite']"
    assert_includes response.body, I18n.t("dashboard.refresh_failed")
  end

  test "index is Norwegian by default and English when the browser asks" do
    get "/dashboard"
    assert_includes response.body, 'lang="nb"'

    get "/dashboard", headers: { "HTTP_ACCEPT_LANGUAGE" => "en-GB,en;q=0.9" }
    assert_includes response.body, 'lang="en"'
    assert_includes response.body, "mission control"
  end

  test "live requires authentication" do
    get "/dashboard/live"

    assert_response :unauthorized
  end

  test "live returns warming up when container absent" do
    Rails.application.config.x.master_container = nil

    # The Accept header dashboard_live.js sends; a GET does not take its format from as: :json.
    # rearm! starts a thread that boots the real MASTER where one is installed; it raced the
    # request and answered 200, so the loader is held still here (minitest 6 has no stub).
    rearm = MasterContainerLoader.method(:rearm!)
    MasterContainerLoader.define_singleton_method(:rearm!) { |*| nil }
    get "/dashboard/live", headers: auth_headers.merge("Accept" => "application/json")

    assert_response :service_unavailable
    assert_equal "warming up", JSON.parse(response.body)["error"]
  ensure
    MasterContainerLoader.define_singleton_method(:rearm!, rearm) if rearm
    Rails.application.config.x.master_container = stub_master_container
  end

  test "live reports a generic error instead of returning exception details" do
    source = File.read(File.expand_path("../../app/controllers/dashboard_controller.rb", __dir__))
    assert_includes source, 'Master::Ground::Swallow.log(e, context: "Dashboard.live")'
    assert_includes source, 'render json: { error: "dashboard unavailable" }'
    refute_includes source, "error: e.message"
  end

  test "dashboard file previews stay within fixed byte and line budgets" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "history.jsonl")
      File.write(path, (1..80).map { |n| "#{n} #{'x' * 1024}" }.join("\n"))
      controller = DashboardController.new

      recent = controller.send(:recent_lines, path)
      assert_operator recent.length, :<=, DashboardController::PANEL_RECENT_LINES
      assert_operator recent.join("\n").bytesize, :<=, DashboardController::PANEL_TAIL_BYTES

      excerpt = controller.send(:bounded_excerpt, path)
      assert_operator excerpt.bytesize, :<=, DashboardController::PROPOSAL_EXCERPT_BYTES
    end

    Dir.mktmpdir do |dir|
      path = File.join(dir, "invalid-utf8.bin")
      lines = Array.new(24) { |n| "#{n} ".b + ("\xFF".b * 1_024) }
      File.binwrite(path, lines.join("\n".b))
      controller = DashboardController.new

      recent = controller.send(:recent_lines, path)
      excerpt = controller.send(:bounded_excerpt, path)
      assert_equal DashboardController::PANEL_RECENT_LINES, recent.length
      assert_operator recent.join("\n").bytesize, :<=, DashboardController::PANEL_TAIL_BYTES
      assert_operator excerpt.bytesize, :<=, DashboardController::PROPOSAL_EXCERPT_BYTES
      assert_predicate recent.join, :valid_encoding?
      assert_predicate excerpt, :valid_encoding?
    end
  end

  test "live returns the mission payload when container present" do
    get "/dashboard/live", headers: auth_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "test/model", body["model"]
    assert body.key?("tokens")
    assert body.key?("open_breakers")
    assert body.key?("context_pressure")
    assert body.key?("provider_health")
    assert_equal "healthy", body.dig("provider_health", "status")
  end
end
