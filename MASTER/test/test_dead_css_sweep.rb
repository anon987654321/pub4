# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# The sweep proposes deletions only when rendered coverage and the static scan
# agree. These tests build a small Rails-shaped tree and drive each proof alone
# and together; nothing here reads the real RAILS tree.
class DeadCssSweepTest < Minitest::Test
  Sweep = Master::Fix::DeadCssSweep
  Rules = Master::Fix::ScssRules

  SCSS = <<~SCSS
    .card { color: red; }
    .card--wide { width: 10px; }
    .orphan { color: blue; }
    .btn-primary { x: 1; }
    .tab-open { y: 1; }
    .stateful { z: 1; }
    .nest { a: 1; &:hover { b: 2 } .gone-child { c: 3 } }
    @keyframes spin { from { a: b } }
    .swiper-slide { d: 1; }
    body { margin: 0; }
  SCSS

  def setup
    @root = Dir.mktmpdir("dead-css")
    rails = File.join(@root, "RAILS")
    write("RAILS/apps.yml", "apps:\n  demo: {}\n")
    write("RAILS/demo/app/assets/stylesheets/application.scss", SCSS)
    write("RAILS/demo/app/views/home/index.html.erb", %(<div class="card card--wide nest <%= x %>"><a class="btn-<%= kind %>"></a></div>))
    write("RAILS/demo/app/javascript/app.js", %(el.classList.add("stateful"); el.className = "tab-" + id;))
    FileUtils.mkdir_p(File.join(rails, "__shared"))
    @out = File.join(@root, "out")
    @sweep = Sweep.new(root: @root, out_dir: @out)
  end

  def teardown = FileUtils.rm_rf(@root)

  def write(rel, body)
    path = File.join(@root, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def verdicts(res = @sweep.run(apps: ["demo"]))
    res["demo"][:verdicts].to_h { |v| [v.rule.selectors.join(","), v.kind] }
  end

  def coverage(selectors)
    write_cov = File.join(@out, "coverage", "demo.json")
    FileUtils.mkdir_p(File.dirname(write_cov))
    File.write(write_cov, JSON.generate("app" => "demo", "surfaces" => ["demo/home/desktop"], "selectors" => selectors))
  end

  def test_scss_flattens_nesting_and_skips_keyframes
    sels = Rules.parse(SCSS).map(&:selectors)
    assert_includes sels, [".nest:hover"]
    assert_includes sels, [".nest .gone-child"]
    refute(sels.flatten.any? { |s| s.include?("from") })
    nest = Rules.parse(SCSS).find { |r| r.selectors == [".nest"] }
    refute nest.leaf, "a rule with nested rules is not a leaf"
  end

  def test_static_only_marks_unnamed_classes_and_spares_runtime_names
    kinds = verdicts
    assert_equal :static, kinds[".orphan"]
    assert_equal :live, kinds[".card"]
    assert_equal :live, kinds[".btn-primary"], "btn-<%= kind %> is a dynamic prefix"
    assert_equal :live, kinds[".tab-open"], "\"tab-\" + id is a dynamic prefix"
    assert_equal :live, kinds[".stateful"], "classList.add names it"
    assert_equal :live, kinds[".swiper-slide"], "vendor runtime classes are never judged"
    assert_equal :live, kinds["body"], "a selector with no class or id is structural"
  end

  def test_without_coverage_nothing_is_dead_and_apply_refuses
    res = @sweep.run(apps: ["demo"])
    assert_equal 0, res["demo"][:summary][:dead]
    assert_match(/unverified/, res["demo"][:summary][:basis])
    out = @sweep.apply("demo", results: res)
    assert_match(/refusing to delete on one proof/, out[:error])
    assert_includes File.read(File.join(@root, "RAILS/demo/app/assets/stylesheets/application.scss")), ".orphan"
  end

  def test_both_proofs_make_a_rule_dead_and_one_proof_does_not
    coverage(".orphan" => false, ".card" => true, ".stateful" => false)
    kinds = verdicts
    assert_equal :dead, kinds[".orphan"]
    assert_equal :state, kinds[".stateful"], "unrendered but named in JS is a state, not dead"
    assert_equal :live, kinds[".card"]
    findings = @sweep.findings(@sweep.run(apps: ["demo"]))
    assert_equal [".orphan"], findings.map { |f| f[:selector] }.reject { |x| x.include?("nest") }
    assert_equal "DEAD_CSS", findings.first[:law]
    assert findings.first[:advisory]
  end

  def test_dead_share_counts_proposed_lines
    summary = @sweep.run(apps: ["demo"])["demo"][:summary]
    assert_operator summary[:dead_share_pct], :>, 0.0
    assert_equal 2, summary[:static_only]
  end

  def test_apply_removes_only_the_dead_leaf_rule_through_the_transaction
    coverage(".orphan" => false, ".card" => true)
    path = File.join(@root, "RAILS/demo/app/assets/stylesheets/application.scss")
    out = @sweep.apply("demo")
    assert_nil out[:error], out[:error].to_s
    assert_equal 1, out[:removed]
    after = File.read(path)
    refute_includes after, ".orphan"
    assert_equal SCSS.sub(".orphan { color: blue; }\n", ""), after
  end

  def test_report_is_written_under_the_out_dir
    res = @sweep.run(apps: ["demo"])
    file = @sweep.write_report(res, @sweep.findings(res))
    assert File.file?(file)
    assert JSON.parse(File.read(File.join(@out, "report.json"))).key?("summary")
  end

  def test_coverage_fold_keys_by_selector_and_ors_usage
    usage = [{ "styleSheetId" => "1", "startOffset" => 0, "endOffset" => 20, "used" => false },
             { "styleSheetId" => "1", "startOffset" => 21, "endOffset" => 35, "used" => true }]
    text = ".a > .b, .c { x: 1 } .a>.b { y: 1 }"
    folded = Master::Fix::DeadCssCoverage.fold(usage, { "1" => text })
    assert_equal true, folded[".a>.b"]
    assert_equal false, folded[".c"]
  end

  def test_coverage_store_accumulates_across_surfaces
    store = Master::Fix::DeadCssCoverage.new(dir: @out)
    store.merge("demo", { ".a" => false, ".b" => true }, "demo/one/mobile")
    data = store.merge("demo", { ".a" => true }, "demo/one/desktop")
    assert_equal true, data["selectors"][".a"]
    assert_equal 2, data["surfaces"].size
  end

  class FakeCdp
    attr_reader :calls

    def initialize = @calls = []

    def command(method, **_params)
      @calls << method
      case method
      when "CSS.stopRuleUsageTracking" then { "ruleUsage" => [{ "styleSheetId" => "s", "startOffset" => 0, "endOffset" => 12, "used" => true }] }
      when "CSS.getStyleSheetText" then { "text" => ".live { a: b }" }
      else {}
      end
    end
  end

  def test_track_starts_and_stops_tracking_around_the_block
    cdp = FakeCdp.new
    surface = Struct.new(:app, :id).new("demo", "demo/home/desktop")
    store = Master::Fix::DeadCssCoverage.new(dir: @out)
    assert_equal :states, store.track(cdp, surface) { :states }
    assert_equal "CSS.startRuleUsageTracking", cdp.calls.find { |c| c.include?("start") }
    assert_equal true, Master::Fix::DeadCssCoverage.load("demo", dir: @out)["selectors"][".live"]
  end

  def test_routes_manifest_reads_nesting_resources_and_shared_includes
    write("RAILS/demo/config/routes.rb", <<~RUBY)
      Rails.application.routes.draw do
        root "home#index"
        get "about" => "pages#about"
        resources :posts, only: %i[index show new] do
          resources :comments, only: :index
        end
        resource :session, only: %i[new create]
        namespace :admin do
          resources :reports, only: :index
        end
        constraints(subdomain: "x") do
          get "hidden" => "hidden#show"
        end
        instance_eval(File.read(File.expand_path("../../__shared/config/routes/legal.rb", __dir__)))
      end
    RUBY
    write("RAILS/__shared/config/routes/legal.rb", %(get "privacy" => "legal#privacy"\n))
    m = Master::Fix::RoutesManifest.new(app_root: File.join(@root, "RAILS/demo"), shared_root: File.join(@root, "RAILS/__shared"))
    assert_equal %w[/ /about /admin/reports /posts /posts/new /privacy /session/new], m.public_get_paths
    assert_includes m.controllers, "sessions"
    assert_includes m.controllers, "admin/reports"
    show = m.routes.find { |r| r.path == "/posts/:id" }
    assert show.parametric
    assert m.routes.find { |r| r.path == "/hidden" }.constrained
  end

  def test_dead_route_sweep_flags_missing_controllers_and_unreachable_views
    write("RAILS/demo/config/routes.rb", %(Rails.application.routes.draw do\n  get "x" => "ghosts#show"\n  get "y" => "pages#about"\nend\n))
    write("RAILS/demo/app/controllers/pages_controller.rb", "class PagesController\n  def about; end\nend\n")
    write("RAILS/demo/app/views/orphans/index.html.erb", "x")
    write("RAILS/demo/app/views/pages/about.html.erb", "x")
    found = Master::Fix::DeadRouteSweep.new(app_roots: { "demo" => File.join(@root, "RAILS/demo") },
                                            shared_root: File.join(@root, "RAILS/__shared"), corpus_text: "").candidates
    assert_equal [[:dead_route, "GET /x"], [:unreachable_view, "home/index.html.erb"], [:unreachable_view, "orphans/index.html.erb"]], found.map { |c| [c.kind, c.subject] }
  end
end
