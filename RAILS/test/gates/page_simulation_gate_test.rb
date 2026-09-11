# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"
require "yaml"
require_relative "gate_probe_harness"
require_relative "../../gates/lib/live/page_simulation"

# page_simulation walks every full-page view twice: once as source text, always,
# and once over HTTP when the app's port is open.
#
# It is the one gate in this batch whose gates.yml row was simply wrong. It was
# declared `needs: [browser]`, which is the runner's only signal for "this gate
# measures nothing without Chrome" — and page_simulation never opens Chrome. It
# fetches over Net::HTTP through CrawlSupport. So the runner counted it among the
# gates that "could measure" when Chrome was present and among the ones degrading
# to warnings when it was not, and neither sentence was about this gate. The row
# now declares no precondition; what it actually needs is a listening port, and
# that it reports per app through skipped_live.
#
# The inventory and the report path are both stubbed here. `run` writes
# page_sim_report.yml into the repo, and a test that dirties the tree it measures
# is its own defect.
class PageSimulationGateTest < Minitest::Test
  include GateProbe

  GATE = Deploy::PageSimulationGate
  INVENTORY = Deploy::PageInventory
  CRAWL = CrawlSupport

  Response = Struct.new(:code, :body)

  CLEAN_VIEW = <<~ERB
    <% content_for :title, t(".title") %>
    <main id="main-content"><%= link_to t(".open"), root_path %></main>
  ERB

  LIVE_HTML = <<~HTML
    <html><head><title>Bergen</title></head>
    <body><a class="skip-link" href="#main-content">Hopp</a><main id="main-content"><h1>Bergen</h1></main></body></html>
  HTML

  def page(root, body: CLEAN_VIEW, app: "brgen", path: "/", persona: "guest")
    view = File.join(root, "view.html.erb")
    File.write(view, body)
    { id: "#{app}#index", app: app, path: path, host: nil, persona: persona, view: "view.html.erb",
      action: "index", needs_id: false, abs_view: view }
  end

  # Everything the gate reaches the world through: the inventory it walks, the
  # ports it probes, and the two files it writes.
  def simulate(pages, live: [], open: false, response: Response.new("200", LIVE_HTML))
    Dir.mktmpdir("page-sim") do |out|
      with_const(GATE, :REPORT_PATH, File.join(out, "report.yml")) do
        with_const(GATE, :SNAPSHOT_PATH, File.join(out, "inventory.yml")) do
          with_methods(
            INVENTORY,
            all: proc { |*, **| pages },
            guest_liveable: proc { |*, **| live },
            uncovered_shared_views: proc { |*, **| [] },
            stale_route_manifests: proc { |*, **| [] },
            write_snapshot!: proc { |*, **| nil }
          ) do
            with_methods(CRAWL, port_open?: proc { |*, **| open },
                                fetch: proc { |*, **| response }) { GATE.run }
          end
        end
      end
    end
  end

  def test_a_guest_surface_carrying_hardcoded_auth_wall_copy_is_named
    Dir.mktmpdir("page-sim-view") do |root|
      walled = %(<main id="main-content"><p>Sign in to continue</p><%= link_to "x", root_path %></main>)
      result = simulate([page(root, body: walled)])

      assert_equal :failed, result.outcome
      assert_match(/hard-coded auth wall copy on guest surface/, result.failures.join(" | "))
    end
  end

  def test_a_mission_control_view_without_a_main_landmark_is_named
    Dir.mktmpdir("page-sim-view") do |root|
      bare = %(<div><%= link_to "x", root_path %><a class="skip-link" href="#main-content">s</a></div>)
      result = simulate([page(root, body: bare, app: "master", path: "/dashboard")])

      assert_match(/mission control missing main landmark/, result.failures.join(" | "))
    end
  end

  def test_a_clean_source_walk_passes_and_counts_every_page
    Dir.mktmpdir("page-sim-view") do |root|
      result = simulate([page(root)])

      assert_equal :passed, result.outcome, result.failures.join(" | ")
      assert_equal 1, result.checks_ran
    end
  end

  # The live half. A 500 is the page being broken; 401 and 403 are the page being
  # right about a guest, which is why they are soft.
  def test_a_live_surface_answering_500_is_named_with_its_url
    Dir.mktmpdir("page-sim-view") do |root|
      row = page(root)
      result = simulate([row], live: [row], open: true, response: Response.new("500", "<html></html>"))

      assert_equal :failed, result.outcome
      assert_match(%r{HTTP 500 for http://127\.0\.0\.1:\d+/}, result.failures.join(" | "))
    end
  end

  def test_a_live_surface_answering_403_to_a_guest_is_soft_rather_than_broken
    Dir.mktmpdir("page-sim-view") do |root|
      row = page(root)
      result = simulate([row], live: [row], open: true, response: Response.new("403", LIVE_HTML))

      assert_equal :passed, result.outcome, result.failures.join(" | ")
      assert_match(/auth-only for the guest persona/, result.soft_failures.join(" | "))
    end
  end

  def test_a_live_page_with_landmarks_and_a_title_passes
    Dir.mktmpdir("page-sim-view") do |root|
      row = page(root)

      assert_equal :passed, simulate([row], live: [row], open: true).outcome
    end
  end

  def test_a_live_page_rendering_exception_chrome_is_named
    Dir.mktmpdir("page-sim-view") do |root|
      row = page(root)
      blown = Response.new("200", "<html><body>Routing Error</body></html>")

      assert_match(/exception chrome in body/, simulate([row], live: [row], open: true, response: blown).failures.join(" | "))
    end
  end

  # The third state this gate actually has. Every port closed means every live
  # surface went unprobed, and the gate has to say so per app rather than letting
  # the source walk speak for both halves.
  def test_with_every_port_closed_each_app_is_named_as_unprobed
    Dir.mktmpdir("page-sim-view") do |root|
      row = page(root)
      result = simulate([row], live: [row], open: false)
      warnings = result.warnings.join(" | ")

      assert_equal GATE::PORTS.size, result.live_skips, "one skip per app, not one for the run"
      GATE::PORTS.each_key { |app| assert_match(/#{app} port \d+ closed — live surfaces skipped/, warnings) }
      assert_match(/live HTTP skipped \(no triangle app listening\) — source checks still ran/, warnings)
    end
  end

  # The row that was wrong. Nothing in this gate opens a browser.
  def test_it_declares_no_browser_precondition_because_it_opens_none
    row = YAML.safe_load_file(File.join(GATE::ROOT, "RAILS", "gates", "gates.yml")).fetch("page_simulation")
    source = File.read(File.join(GATE::ROOT, "RAILS", "gates", "lib", "live", "page_simulation.rb"))

    refute row.key?("needs"), "the runner reads `needs` as the reason a gate measured nothing"
    refute_match(/CdpSession|GeometryProbe|with_browser/, source)
  end
end
