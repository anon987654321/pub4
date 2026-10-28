# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "socket"
require "open3"
require "rbconfig"
require "stringio"
require_relative "../lib/operator/canary"

# The canary reads a deploy; it must never touch the real box. Everything here
# runs against a throwaway HTTP server on loopback, stubbed rcctl and a stubbed
# ssh on PATH. No part of it reaches vm23.
class CanaryTest < Minitest::Test
  Canary = Operator::Canary
  Ok = Struct.new(:success?)

  # A one-thread HTTP server whose replies are keyed by path.
  class FakeServer
    attr_reader :port, :hits

    def initialize
      @server = TCPServer.new("127.0.0.1", 0)
      @port = @server.addr[1]
      @hits = []
      @thread = Thread.new { loop { serve(@server.accept) } }
    end

    def stop
      @thread.kill
      @server.close
    end

    def serve(sock)
      request = sock.gets.to_s
      path = request.split[1].to_s
      host = nil
      while (line = sock.gets) && line != "\r\n"
        host = line.split(": ", 2).last.strip if line.downcase.start_with?("host:")
      end
      @hits << [path, host]
      status, headers, body = reply(path)
      sock.write("HTTP/1.1 #{status}\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n#{headers}\r\n#{body}")
    ensure
      sock.close
    end

    def reply(path)
      case path
      when "/slow" then sleep 0.25 and ["200 OK", "", "late"]
      when "/fat" then ["200 OK", "X-Pad: #{'a' * 9000}\r\n", "ok"]
      when "/i18n" then ["200 OK", "", %(<span class="translation_missing">translation missing: nb.x</span>)]
      when "/gone" then ["500 Internal Server Error", "", "boom"]
      when "/moved" then ["302 Found", "Location: /\r\n", ""]
      else ["200 OK", "", "fine"]
      end
    end
  end

  def setup
    @server = FakeServer.new
    @root = Dir.mktmpdir("canary")
    write("RAILS/apps.yml", "apps:\n  demo:\n    domain: demo.test\n    port: #{@server.port}\n    public: true\n")
    paths = %w[slow fat i18n gone moved fine]
    write("RAILS/demo/config/routes.rb", "Rails.application.routes.draw do\n#{paths.map { |p| %(  get "#{p}" => "x##{p}"\n) }.join}  get \"items/:id\" => \"x#show\"\nend\n")
  end

  def teardown
    @server.stop
    FileUtils.rm_rf(@root)
  end

  def write(rel, body)
    path = File.join(@root, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def runner(**opts)
    Canary::Runner.new(root: @root, apps: %w[demo], smoke: false, shell: ->(*_) { ["", Ok.new(true)] }, budget_ms: 100, **opts)
  end

  def by_name(results) = results.to_h { |r| [r.name, r] }

  def test_routes_are_judged_on_status_latency_header_size_and_translation_missing
    got = by_name(runner.run)
    assert got["GET demo /up"].ok
    assert got["GET demo /fine"].ok
    assert got["GET demo /moved"].ok, "a redirect is the answer, not a failure"
    assert_match(/status 500/, got["GET demo /gone"].detail)
    assert_match(/over the 100ms budget/, got["GET demo /slow"].detail)
    assert_match(/response headers \d+ bytes, relayd's limit is 8192/, got["GET demo /fat"].detail)
    assert_match(/translation missing/, got["GET demo /i18n"].detail)
    assert(got.keys.none? { |k| k.include?(":id") }, "a route with a dynamic segment has no URL to probe")
  end

  def test_requests_carry_the_apps_host_header
    runner.run
    requests = @server.hits.reject { |path, _| path.empty? }
    refute_empty requests
    assert(requests.all? { |_, host| host == "demo.test" })
  end

  def test_ports_and_services_are_checked_in_local_mode_and_failures_are_exact
    asked = []
    shell = lambda do |*argv|
      asked << argv
      [argv.last == "relayd" ? "relayd(failed)" : "ok", Ok.new(argv.last != "relayd")]
    end
    results = Canary::Runner.new(root: @root, apps: %w[demo], smoke: false, shell:, connect: ->(_h, _p) { false }).run
    got = by_name(results)
    refute got["port #{@server.port} (demo)"].ok
    assert_match(/closed/, got["port #{@server.port} (demo)"].detail)
    refute got["rcctl relayd"].ok
    assert_equal "relayd(failed)", got["rcctl relayd"].detail
    assert got["rcctl brgen"].ok
    assert_includes asked, %w[rcctl check amber]
  end

FLOW_OUTPUT = <<~OUT
    Warnings:
      - surface0: demo/demo_browse PASS - 2 step(s) - demo.test [/, /up]
      - surface0: demo/demo_search FAIL - 1 step(s) - demo.test [/search]
      - surface0: demo/demo_signed_in INCONCLUSIVE - 2 step(s) - credentials unavailable
    Failures:
      - flow:demo_search invariant broken: hits(0) > 0 - search is wired to data
  OUT

  def test_flow_journeys_are_reported_one_result_per_flow_scoped_to_the_apps
    write("MASTER/checks/runner.rb", "")
    asked = []
    shell = lambda do |*argv|
      asked << argv
      [FLOW_OUTPUT, Ok.new(false)]
    end
    got = by_name(runner(shell:).run)
    assert got["flow demo/demo_browse"].ok
    refute got["flow demo/demo_search"].ok
    assert_match(/invariant broken: hits\(0\) > 0/, got["flow demo/demo_search"].detail)
    assert got["flow demo/demo_signed_in"].ok, "an unmeasured journey is named, not failed"
    assert_equal "inconclusive", got["flow demo/demo_signed_in"].detail
    call = asked.find { |a| a.include?("flow_journey") }
    assert_includes call, "FLOW_APP=demo"
    assert_includes call, "CHECK_AUTOFIX=0"
  end

  def test_a_crashed_flow_runner_is_one_failed_result_and_no_flows_skips_it
    write("MASTER/checks/runner.rb", "")
    crash = ->(*_) { ["boom\n", Ok.new(false)] }
    got = by_name(runner(shell: crash).run)
    refute got["flows"].ok
    assert_includes got["flows"].detail, "boom"
    refute(by_name(runner(shell: crash, flows: false).run).key?("flows"))
  end

  def test_public_mode_never_runs_flows_because_they_read_the_box_loopback
    write("MASTER/checks/runner.rb", "")
    asked = []
    runner(mode: :public, shell: ->(*argv) { asked << argv; ["", Ok.new(true)] }).run
    assert(asked.none? { |a| a.include?("flow_journey") })
  end

  def test_the_deploy_shed_ports_are_probed_by_number
    real = File.expand_path("../..", __dir__)
    ports = []
    Canary::Runner.new(root: real, apps: %w[amber bsdports], smoke: false, shell: ->(*_) { ["", Ok.new(true)] },
                       connect: ->(_h, p) { ports << p },
                       http: ->(*) { Canary::Reply.new(status: 200, headers: {}, body: "", elapsed_ms: 1) }).run
    assert_includes ports, 61_352
    assert_includes ports, 47_312
  end

  def test_the_real_manifest_yields_public_get_routes_and_skips_internal_ones
    real = File.expand_path("../..", __dir__)
    seen = []
    http = ->(_h, _p, path, _d, _tls) { seen << path and Canary::Reply.new(status: 200, headers: {}, body: "", elapsed_ms: 1) }
    Canary::Runner.new(root: real, apps: %w[brgen], smoke: false, http:, shell: ->(*_) { ["", Ok.new(true)] }, connect: ->(*) { true }).run
    assert_includes seen, "/"
    assert_includes seen, "/up"
    assert(seen.none? { |p| p.include?(":") || p.start_with?("/internal") })
  end

  def test_public_mode_skips_rcctl_and_ports
    names = runner(mode: :public, http: ->(*) { Canary::Reply.new(status: 200, headers: {}, body: "", elapsed_ms: 1) }).run.map(&:name)
    assert(names.none? { |n| n.start_with?("rcctl", "port") })
  end

  def test_smoke_script_failure_is_reported_with_its_fail_lines
    write("OPENBSD/bin/deploy-smoke.sh", "#!/bin/sh\n")
    shell = ->(*argv) { argv.first == "sh" ? ["FAIL amber_local\nok x\n", Ok.new(false)] : ["", Ok.new(true)] }
    r = Canary::Runner.new(root: @root, apps: %w[demo], smoke: true, shell:, connect: ->(*) { true },
                           http: ->(*) { Canary::Reply.new(status: 200, headers: {}, body: "", elapsed_ms: 1) }).run.last
    refute r.ok
    assert_match(/FAIL amber_local/, r.detail)
  end

  def test_failure_output_names_what_failed_and_prints_the_manual_rollback_without_running_it
    out = StringIO.new
    code = Canary.main(%w[--local --app demo --no-smoke --budget-ms 100], root: @root, out:, shell: ->(*_) { ["", Ok.new(true)] })
    assert_equal 1, code
    text = out.string
    assert_match(/FAIL GET demo \/gone — status 500/, text)
    assert_match(/rollback \(manual; the canary changes nothing\)/, text)
    assert_match(/vps-deploy takes no SHA/, text)
  end

  def test_deploy_preflight_capture_kills_a_hung_process_group
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    output, ok = Operator::DeployPreflight.capture(
      [RbConfig.ruby, "-e", "Process.spawn('sleep','10', out: STDOUT, err: STDERR); exit 0"],
      @root,
      timeout: 0.1,
    )
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    refute ok
    assert_includes output, "timed out after 0.1s"
    assert_operator elapsed, :<, 3
  end

  def test_rollback_advice_names_previous_and_current_sha
    git = ->(*argv) { argv.include?("HEAD@{1}") ? "aaa1111" : "bbb2222" }
    lines = Canary::Rollback.advice(root: @root, git:)
    assert_includes lines.join("\n"), "git revert --no-edit aaa1111..bbb2222"
  end

  # The operator in a clean environment: the test run's bundler variables
  # would point its ruby at gems built for another one.
  def operator_run(env, *argv)
    operator = File.expand_path("../bin/operator", __dir__)
    Bundler.with_unbundled_env do
      clean = { "GEM_HOME" => nil, "GEM_PATH" => nil, "RUBYLIB" => nil, "RUBYOPT" => nil }
      Open3.capture2e(clean.merge(env), operator, *argv)
    end
  end

  def test_operator_remote_canary_goes_through_ssh_and_nothing_else
    bin = Dir.mktmpdir("fakessh")
    File.write(File.join(bin, "ssh"), "#!/bin/sh\necho \"SSH $*\"\n")
    File.chmod(0o755, File.join(bin, "ssh"))
    out, st = operator_run({ "PATH" => "#{bin}:#{ENV['PATH']}", "PUB4_SSH_HOST" => "dev@example.invalid" }, "vps", "canary", "--remote", "--app", "amber")
    assert st.success?, out
    assert_match(%r{SSH .*dev@example\.invalid .*OPENBSD/bin/canary --local --app amber}, out)
  ensure
    FileUtils.rm_rf(bin)
  end

  def test_operator_rollback_is_explicit_and_not_automated
    out, st = operator_run({}, "vps", "rollback", "abc1234")
    assert_equal 2, st.exitstatus
    assert_match(/not automated/, out)
    assert_match(/git revert --no-edit abc1234\.\.HEAD/, out)
  end
end
