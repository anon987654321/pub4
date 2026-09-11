# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "yaml"

# rails_runtime is one of three gates that stay subprocesses, and the only one
# whose name promises more than the runner asks it for.
#
# Its row in gates.yml is `script: rails_runtime.rb` with no arguments, and the
# runtime half is behind `--runtime`. So every invocation through the runner runs
# `static_gate!` — the in-process production gate, already a gate of its own — and
# exits 0. Nothing boots, no bundle is checked, no route is proved against a real
# controller, and the pass reads as all four. That is what the first two tests
# hold: the gate now says which half it ran, so the pass cannot be misread.
#
# The half that only exists here is DEAD_ROUTE_PROBE. `resources :x` declares seven
# routes whether or not the controller has seven actions, and Rails answers 404 for
# the ones it does not — which no source read finds, because routes.rb is correct.
# The probe is plain Ruby run inside the booted app, so it is testable here against
# a planted route table, which is the only part of this gate that can be proved
# without booting three Rails apps.
class RailsRuntimeGateTest < Minitest::Test
  GATES_DIR = File.expand_path("../../gates", __dir__)
  SCRIPT = File.join(GATES_DIR, "rails_runtime.rb")

  def run_script(*args, env: {})
    out, status = Open3.capture2e(ENV.to_h.merge(env), RbConfig.ruby, SCRIPT, *args)
    [out, status]
  end

  def test_the_registry_invokes_it_with_no_arguments_so_the_runtime_half_is_off
    row = YAML.safe_load_file(File.join(GATES_DIR, "gates.yml")).fetch("rails_runtime")

    assert_equal "rails_runtime.rb", row.fetch("script")
    refute row.key?("args"), "an args key here would be the only way the runner could ask for --runtime"
  end

  # The defect is a silent one: a green gate named rails_runtime that ran no
  # runtime. Removing the line below puts it back.
  def test_a_run_without_the_runtime_flag_says_which_half_it_ran
    out, status = run_script

    assert_equal 0, status.exitstatus, out
    assert_match(/static half only — pass --runtime to boot each app/, out)
    refute_match(/Rails runtime gate passed/, out, "no app was booted, so nothing may claim one was")
  end

  # SKIP_RUNTIME_GATE=1 is the hotfix path. It must stay audible: the skip is the
  # reason a regression bin/ci would have caught got through.
  def test_a_skipped_runtime_half_is_audible_and_claims_no_pass
    out, status = run_script("--runtime", env: { "SKIP_RUNTIME_GATE" => "1" })

    assert_equal 0, status.exitstatus, out
    assert_match(/runtime gate skipped: SKIP_RUNTIME_GATE=1/, out)
    refute_match(/Rails runtime gate passed/, out)
  end

  # The probe, lifted out of the script and run against a planted route table. The
  # heredoc escapes its interpolations for the app-side eval, so they are unescaped
  # here for the same reason.
  def probe_source
    body = File.read(SCRIPT)[/DEAD_ROUTE_PROBE = <<~RUBY\n(.*?)\n^RUBY$/m, 1]
    refute_nil body, "the probe moved; this test measures nothing without it"
    body.gsub('\#{', '#{')
  end

  Route = Struct.new(:defaults)

  # A stand-in for the booted application: a route table, and controllers resolved
  # by name the way safe_constantize resolves them.
  def run_probe(routes, controllers)
    app = Object.new
    app.define_singleton_method(:routes) { Struct.new(:routes).new(routes.map { |d| Route.new(d) }) }
    rails = Object.new
    rails.define_singleton_method(:application) { app }
    sandbox = Module.new
    sandbox.const_set(:Rails, rails)
    sandbox.const_set(:CONTROLLERS, controllers)
    sandbox.module_eval(SHIMS)
    capture_io { sandbox.module_eval(probe_source) }
    nil
  end

  # camelize and safe_constantize are ActiveSupport, which this suite does not
  # load. Both are one line for the shapes the probe uses, and both are reopened on
  # the real String because that is what the probe calls them on.
  SHIMS = <<~RUBY
    class ::String
      def camelize = split("_").map(&:capitalize).join
      def safe_constantize = CONTROLLERS[self]
    end
  RUBY

  def controller(*actions)
    Struct.new(:action_methods).new(actions.map(&:to_s))
  end

  def test_the_probe_names_a_route_whose_controller_has_no_such_action
    error = assert_raises(SystemExit) do
      run_probe([{ controller: "posts", action: "edit" }], { "PostsController" => controller(:index) })
    end

    assert_match(/dead routes: posts#edit/, error.message)
  end

  def test_the_probe_names_a_route_whose_controller_does_not_exist
    error = assert_raises(SystemExit) do
      run_probe([{ controller: "ghosts", action: "index" }], {})
    end

    assert_match(/dead routes: ghosts#index \(no controller\)/, error.message)
  end

  def test_the_probe_is_silent_when_every_route_reaches_a_real_action
    assert_nil run_probe([{ controller: "posts", action: "index" }, { controller: "posts", action: "show" }],
                         { "PostsController" => controller(:index, :show) })
  end

  # Rails' own engine routes are not the app's to answer for, and flagging them
  # would bury a real finding under a fixed list of six.
  def test_the_probe_skips_the_framework_engines_rather_than_reporting_them
    assert_nil run_probe([{ controller: "rails/health", action: "show" },
                          { controller: "active_storage/blobs", action: "show" }], {})
  end
end
