# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../lib/fix/work_lane"
require_relative "../lib/fix/screenshot_sweep"

# The screenshot sweep's page plan, its lane wiring and its no-browser failure
# path. Rendering itself needs Chrome and booted apps; `bin/operator visual
# sweep` is that proof, and its index.json is the evidence.
class TestScreenshotSweep < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def with_manifest(routes)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "MASTER", "checks", "data"))
      File.write(File.join(dir, Master::Fix::ScreenshotSweep::Plan::MANIFEST), { "apps" => routes }.to_yaml)
      yield Master::Fix::ScreenshotSweep::Plan.new(root: dir)
    end
  end

  def test_seeds_are_pages_with_the_root_first_and_machine_endpoints_left_out
    with_manifest("amber" => { "routes" => {
      "a" => ["/terms"], "b" => ["/manifest.json", "/.well-known/assetlinks.json", "/up"],
      "c" => ["/service-worker.js", "/api/v1/lint", "/posts/:id"], "d" => ["/"]
    } }) do |plan|
      assert_equal %w[/ /terms], plan.seeds("amber").map(&:path)
    end
  end

  def test_an_app_without_manifest_routes_is_swept_at_its_root
    with_manifest({}) { |plan| assert_equal ["/"], plan.seeds("master").map(&:path) }
  end

  def test_parameter_routes_become_patterns_and_catch_alls_are_dropped
    routes = { "a" => ["/posts/:id", "/posts/:id/edit", "/:slug", "/files/*path"] }
    with_manifest("amber" => { "routes" => routes }) do |plan|
      patterns = plan.patterns("amber")

      assert_equal ["/posts/:id", "/posts/:id/edit", "/files/*path"], patterns.keys
      assert_match patterns["/posts/:id"], "/posts/42"
      refute_match patterns["/posts/:id"], "/posts/42/edit"
      assert_match patterns["/files/*path"], "/files/a/b.pdf"
    end
  end

  def test_brgen_is_planned_on_its_apex_and_every_vertical_host
    plan = Master::Fix::ScreenshotSweep::Plan.new(root: ROOT)
    hosts = plan.seeds("brgen").map(&:host).uniq

    assert_includes hosts, "brgen.no"
    assert_includes hosts, "markedsplass.brgen.no"
    assert_includes hosts, "maps.brgen.no"
  end

  # The engines mount at / on their own subdomains; asking the apex for /feed
  # returns the routing-error page, not tv's feed.
  def test_brgen_engine_routes_are_planned_on_their_engine_subdomain
    plan = Master::Fix::ScreenshotSweep::Plan.new(root: ROOT)
    hosts = plan.seeds("brgen").to_h { |page| [[page.path, page.host], true] }

    assert hosts[["/feed", "tv.brgen.no"]], "tv/feed#index belongs on tv.brgen.no"
    assert hosts[["/profile/new", "dating.brgen.no"]], "dating/profiles#new belongs on dating.brgen.no"
    assert hosts[["/shops", "markedsplass.brgen.no"]], "marketplace/stores#index belongs on a marketplace alias"
    refute hosts[["/feed", "brgen.no"]], "the apex has no /feed"
  end

  def test_the_stage_runs_in_the_rendering_lanes_and_not_the_code_lane
    assert Master::Fix::WorkLane.runs?(:screenshot_sweep, :visual)
    assert Master::Fix::WorkLane.runs?(:screenshot_sweep, :all)
    refute Master::Fix::WorkLane.runs?(:screenshot_sweep, :code)
    assert_includes Master::Fix::WorkLane.skipped(:code), "screenshot sweep"
  end

  def test_the_sweep_widths_are_declared_data
    widths = YAML.safe_load_file(File.join(ROOT, Master::Fix::ScreenshotSweep::GEOMETRY)).fetch("sweep_widths")

    assert_equal [320, 360, 375, 390, 430, 480, 640, 768, 1024, 1280], widths
  end

  FailedBoot = Struct.new(:message) do
    def ok? = false
    def ensure_running!(_apps) = self
    def stop_owned! = nil
  end

  def test_apps_that_do_not_boot_leave_an_index_that_says_so
    Dir.mktmpdir do |out|
      summary = Master::Fix::ScreenshotSweep.new(root: ROOT, runtime: FailedBoot.new("port 47312 closed"), out:)
                                            .run(apps: ["bsdports"])

      assert_equal "apps not running: port 47312 closed", summary["error"]
      assert_equal 0, summary["screenshots"]
      assert_equal "apps not running: port 47312 closed", JSON.parse(File.read(File.join(out, "index.json")))["error"]
      assert_includes File.read(File.join(out, "index.html")), "port 47312 closed"
    end
  end
end
