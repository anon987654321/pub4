# frozen_string_literal: true

require "json"
require "net/http"
require "optparse"
require "rbconfig"
require "socket"
require "yaml"
require_relative "../fix/routes_manifest"
require_relative "../io/exec"

module Operator
  # The post-deploy canary. It answers one question after vps-deploy: is the box
  # serving what it should, and if not, exactly what is not.
  #
  #   ports      amber's and bsdports' ports are the ones a deploy sheds and
  #              relayd keeps answering TLS without, so a dead app looks like a
  #              hang; brgen and master are checked with them.
  #   services   rcctl check for each daemon.
  #   routes     every public GET route from the route manifest: 200..399, under
  #              the latency budget, response headers under relayd's 8 KB limit,
  #              no "translation missing" in the body.
  #   flows      the HTTP-only user journeys in checks/data/flows.yml (local mode only:
  #              they read the apps on 127.0.0.1), one result per journey.
  #   smoke      OPENBSD/bin/deploy-smoke.sh, the rehearsal subset that needs only
  #              the box itself.
  #
  # It reads and reports. Rolling back is a human decision, so on failure it
  # prints the previous deployed SHA and the commands, and runs none of them.
  module Canary
    HEADER_LIMIT_BYTES = 8 * 1024
    DEFAULT_BUDGET_MS = 3000
    SERVICES = %w[master brgen amber bsdports relayd].freeze
    SKIPPED_PREFIXES = %w[/internal /rails /cable /admin].freeze
    Reply = Struct.new(:status, :headers, :body, :elapsed_ms, keyword_init: true)
    Result = Struct.new(:name, :ok, :detail, keyword_init: true)

    module_function

    def main(argv, root: File.expand_path("../../..", __dir__), out: $stdout, **runner_opts)
      opts = { mode: :local, apps: nil, budget_ms: DEFAULT_BUDGET_MS, smoke: true, flows: true, json: false }
      OptionParser.new do |o|
        o.on("--local") { opts[:mode] = :local }
        o.on("--public") { opts[:mode] = :public }
        o.on("--app LIST") { |v| opts[:apps] = v.split(",") }
        o.on("--budget-ms N", Integer) { |v| opts[:budget_ms] = v }
        o.on("--no-smoke") { opts[:smoke] = false }
        o.on("--no-flows") { opts[:flows] = false }
        o.on("--json") { opts[:json] = true }
      end.parse!(argv.dup)

      results = Runner.new(root:, **opts.slice(:mode, :apps, :budget_ms, :smoke, :flows), **runner_opts).run
      out.puts(opts[:json] ? JSON.pretty_generate(results.map(&:to_h)) : render(results, root))
      results.all?(&:ok) ? 0 : 1
    end

    def render(results, root)
      lines = results.map { |r| "#{r.ok ? 'ok  ' : 'FAIL'} #{r.name}#{r.detail.to_s.empty? ? '' : " — #{r.detail}"}" }
      failed = results.reject(&:ok)
      lines << (failed.empty? ? "canary: #{results.size} checks passed" : "canary: #{failed.size} of #{results.size} checks FAILED")
      lines.concat(Rollback.advice(root:)) unless failed.empty?
      lines.join("\n")
    end

    # What a failed canary tells the operator to do. It never does it.
    module Rollback
      module_function

      def advice(root:, git: ->(*argv) { Master::Io::Exec.capture2(*argv, err: File::NULL).first.to_s.strip })
        current = git.call("git", "-C", root, "rev-parse", "--short", "HEAD")
        previous = git.call("git", "-C", root, "rev-parse", "--short", "HEAD@{1}")
        previous = "unknown" if previous.empty?
        [
          "",
          "rollback (manual; the canary changes nothing):",
          "  deployed now: #{current.empty? ? 'unknown' : current}   previous: #{previous}",
          "  vps-deploy takes no SHA, and its git pull --ff-only would return to origin/main, so the",
          "  rollback is a revert on main followed by a deploy, from the dev machine:",
          "    git revert --no-edit #{previous}..#{current.empty? ? 'HEAD' : current} && git push origin main",
          "    bin/operator vps deploy <app> --remote",
          "  per-app stamps: /var/db/pub4/last_deploy_<app>.json on the box",
        ]
      end
    end

    class Runner
      def initialize(root:, mode: :local, apps: nil, budget_ms: DEFAULT_BUDGET_MS, smoke: true, flows: true,
                     http: nil, shell: nil, connect: nil)
        @root = root
        @mode = mode
        @budget_ms = budget_ms
        @smoke = smoke
        @flows = flows
        @http = http || method(:fetch)
        @shell = shell || ->(*argv) { Master::Io::Exec.capture2e(*argv) }
        @connect = connect || method(:open_port)
        @apps = load_apps(apps)
      end

      def run
        results = []
        results.concat(port_checks) if @mode == :local
        results.concat(service_checks) if @mode == :local
        results.concat(route_checks)
        results.concat(flow_checks) if @flows && @mode == :local
        results.concat(smoke_check) if @smoke
        results
      end

      private

      def load_apps(only)
        data = YAML.safe_load_file(File.join(@root, "RAILS", "apps.yml"), aliases: true).fetch("apps")
        apps = data.select { |_name, row| row["public"] && row["port"] }
                   .transform_values { |row| row.slice("domain", "port") }
        only ? apps.slice(*only) : apps
      end

      def port_checks
        @apps.map do |name, cfg|
          up = @connect.call("127.0.0.1", cfg["port"])
          Result.new(name: "port #{cfg['port']} (#{name})", ok: up, detail: up ? nil : "closed — the app is down or was shed; relayd still answers TLS")
        end
      end

      def service_checks
        SERVICES.map do |svc|
          out, status = @shell.call("rcctl", "check", svc)
          Result.new(name: "rcctl #{svc}", ok: status.success?, detail: status.success? ? nil : out.to_s.strip.lines.last.to_s.strip)
        rescue SystemCallError => e
          Result.new(name: "rcctl #{svc}", ok: false, detail: "#{e.class}: #{e.message}")
        end
      end

      def route_checks
        @apps.flat_map do |name, cfg|
          paths = paths_for(name)
          paths.map { |path| route_result(name, cfg, path) }
        end
      end

      def paths_for(app)
        # master's routes are its own chat and face endpoints, most of them
        # streams or behind AuthTier, so its canary is liveness alone.
        return ["/up"] if app == "master"

        manifest = Master::Fix::RoutesManifest.new(app_root: File.join(@root, "RAILS", app), shared_root: File.join(@root, "RAILS", "__shared"))
        (["/up"] + manifest.public_get_paths).uniq.reject { |p| SKIPPED_PREFIXES.any? { |s| p.start_with?(s) } }
      end

      def route_result(app, cfg, path)
        reply = @http.call(@mode == :local ? "127.0.0.1" : cfg["domain"], @mode == :local ? cfg["port"] : 443, path, cfg["domain"], @mode == :public)
        problems = problems_for(reply)
        Result.new(name: "GET #{app} #{path}", ok: problems.empty?, detail: problems.empty? ? "#{reply.status} #{reply.elapsed_ms}ms" : problems.join("; "))
      rescue StandardError => e
        Result.new(name: "GET #{app} #{path}", ok: false, detail: "#{e.class}: #{e.message}")
      end

      def problems_for(reply)
        problems = []
        problems << "status #{reply.status}, expected 200..399" unless (200..399).cover?(reply.status)
        problems << "#{reply.elapsed_ms}ms over the #{@budget_ms}ms budget" if reply.elapsed_ms > @budget_ms
        size = header_bytes(reply.headers)
        problems << "response headers #{size} bytes, relayd's limit is #{HEADER_LIMIT_BYTES}" if size >= HEADER_LIMIT_BYTES
        problems << "body contains 'translation missing'" if reply.body.to_s.match?(/translation[ _]missing/i)
        problems
      end

      def header_bytes(headers)
        headers.sum { |k, vs| Array(vs).sum { |v| "#{k}: #{v}\r\n".bytesize } }
      end

      FLOW_LINE = %r{surface0: (?<app>[\w-]+)/(?<id>\S+) (?<state>PASS|FAIL|INCONCLUSIVE|SKIPPED|ERROR)\b}
      FLOW_PROBLEM = /^\s*- flow:(?<id>\S+?)[\s:\/](?<why>.*)$/

      # The flow_journey check, scoped to the apps under test, reported per journey.
      # A journey that could not run (no credentials, port closed) is not a failure
      # here: the port and rcctl checks own "down", and an unmeasured journey is
      # named as such rather than counted as passed.
      def flow_checks
        script = File.join(@root, "MASTER", "checks", "runner.rb")
        return [] unless File.file?(script)

        out, status = @shell.call("env", "CHECK_AUTOFIX=0", "FLOW_APP=#{@apps.keys.join(',')}", RbConfig.ruby, script, "flow_journey")
        rows = out.to_s.lines.filter_map { |line| FLOW_LINE.match(line) }
        return [Result.new(name: "flows", ok: false, detail: out.to_s.lines.last(3).join.strip)] if rows.empty? && !status.success?

        problems = out.to_s.lines.filter_map { |line| FLOW_PROBLEM.match(line) }.to_h { |m| [m[:id], m[:why].strip] }
        rows.map do |m|
          bad = %w[FAIL ERROR].include?(m[:state])
          Result.new(name: "flow #{m[:app]}/#{m[:id]}", ok: !bad, detail: bad ? (problems[m[:id]] || m[:state]) : m[:state].downcase)
        end
      rescue SystemCallError => e
        [Result.new(name: "flows", ok: false, detail: "#{e.class}: #{e.message}")]
      end

      def smoke_check
        script = File.join(@root, "OPENBSD", "bin", "deploy-smoke.sh")
        return [] unless File.file?(script)

        out, status = @shell.call("sh", script, @mode == :local ? "--local" : "--public")
        [Result.new(name: "deploy-smoke #{@mode}", ok: status.success?, detail: status.success? ? nil : out.to_s.lines.grep(/FAIL/).first(4).join(" ").strip)]
      rescue SystemCallError => e
        [Result.new(name: "deploy-smoke #{@mode}", ok: false, detail: "#{e.class}: #{e.message}")]
      end

      def open_port(host, port)
        Socket.tcp(host, port, connect_timeout: 3) { true }
      rescue SystemCallError, Socket::ResolutionError
        false
      end

      # Net::HTTP without following redirects: a 3xx is the answer being judged.
      def fetch(host, port, path, domain, tls)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        http = Net::HTTP.new(host, port)
        http.use_ssl = tls
        http.open_timeout = http.read_timeout = 15
        res = http.request(Net::HTTP::Get.new(path, "Host" => domain, "Accept-Language" => "nb", "User-Agent" => "pub4-canary"))
        ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        Reply.new(status: res.code.to_i, headers: res.to_hash, body: res.body.to_s, elapsed_ms: ms)
      end
    end
  end

  # The checks the code about to be deployed must pass before anything on vm23
  # is stopped. A SyntaxError or a law that raises at boot kills master's
  # container after production is already shed, so each check below reproduces
  # such a failure where it is cheap: before the deploy, not after the stop.
  #
  #   syntax       every Ruby file under MASTER/lib, MASTER/law and RAILS/*/app
  #                compiles (one process, no per-file ruby -c)
  #   law files    MASTER/test/test_law_files_load.rb, each law file in its own process
  #   boot smoke   MASTER/tools/boot_smoke.rb, which builds the FixLoop
  #   rehearse     OPENBSD/bin/rehearse, the static deploy contracts (the Mac only:
  #                it loads RAILS tests the box has no reason to carry)
  module DeployPreflight
    Result = Struct.new(:name, :ok, :detail, keyword_init: true)
    SWEEP_GLOBS = %w[MASTER/lib/**/*.rb MASTER/law/**/*.rb RAILS/*/app/**/*.rb].freeze
    TIMEOUT = 900

    module_function

    def main(argv, root: File.expand_path("../../..", __dir__), out: $stdout)
      opts = { rehearse: true }
      OptionParser.new do |o|
        o.on("--root DIR") { |v| root = v }
        o.on("--no-rehearse") { opts[:rehearse] = false }
      end.parse!(argv.dup)
      results = run(root:, **opts)
      out.puts(report(results))
      results.all?(&:ok) ? 0 : 1
    end

    # Stops at the first failure: the later checks load the same code, and the
    # first message is the one the operator needs.
    def run(root:, rehearse: true, runner: method(:capture))
      results = []
      steps(root, rehearse, runner).each do |name, step|
        results << step.call
        results.last.name = name
        break unless results.last.ok
      end
      results
    end

    def steps(root, rehearse, runner)
      ruby = RbConfig.ruby
      list = {
        "syntax" => -> { syntax(root) },
        "law files" => -> { shell(runner, [ruby, "-Itest", "test/test_law_files_load.rb"], File.join(root, "MASTER")) },
        "boot smoke" => -> { shell(runner, [ruby, "tools/boot_smoke.rb"], File.join(root, "MASTER")) }
      }
      list["rehearse"] = -> { shell(runner, [ruby, "OPENBSD/bin/rehearse"], root) } if rehearse
      list
    end

    def syntax(root)
      bad = SWEEP_GLOBS.flat_map { |glob| Dir.glob(File.join(root, glob)) }.sort.filter_map do |file|
        RubyVM::InstructionSequence.compile_file(file)
        nil
      rescue SyntaxError => e
        "#{file.delete_prefix("#{root}/")}: #{e.message.lines.first.to_s.strip}"
      end
      Result.new(ok: bad.empty?, detail: bad.first(5).join("\n"))
    end

    def shell(runner, argv, chdir)
      out, ok = runner.call(argv, chdir)
      Result.new(ok:, detail: ok ? "" : out.to_s.lines.last(12).join)
    end

    def capture(argv, chdir, timeout: TIMEOUT)
      out, status = Master::Io::Exec.capture2e(*argv, chdir:, timeout:, raise_on_timeout: true)
      [out, status.success?]
    rescue Master::Io::Exec::TimeoutError => error
      out = Array(error.result).first.to_s
      out << "\n" unless out.empty? || out.end_with?("\n")
      [out + "timed out after #{timeout}s\n", false]
    end

    # `bin/operator vps deploy <app> --remote`: judge the commit here, then hand the
    # box the exact SHA and the word that it passed. Returns [true, command] or
    # [false, reason]; the caller runs the command or prints the reason.
    #
    # The commit judged is HEAD, and HEAD must be origin/main with no edits to
    # tracked files in the governed trees, because the box deploys origin/main and a
    # preflight of anything else proves nothing about what it will run.
    def remote_command(root:, app:, env: ENV, git: method(:git_out), runner: method(:capture), out: $stdout)
      git.call(root, "fetch", "-q", "origin", "main")
      sha = git.call(root, "rev-parse", "HEAD")
      return [false, "cannot read HEAD of #{root}"] if sha.empty?
      return [false, "HEAD #{sha[0, 9]} is not origin/main (#{git.call(root, 'rev-parse', 'origin/main')[0, 9]}); the box deploys origin/main, so push and deploy from that commit"] unless git.call(root, "rev-parse", "origin/main") == sha

      dirty = git.call(root, "status", "--porcelain", "-uno", "--", "MASTER", "RAILS", "OPENBSD")
      return [false, "commit these first:\n#{dirty.lines.first(5).join}"] unless dirty.empty?

      lead = "cd /home/dev/pub4 && VPS_DEPLOY_SHA=#{sha}"
      tail = "zsh OPENBSD/bin/vps-deploy #{app}"
      if env["VPS_DEPLOY_SKIP_PREFLIGHT"] == "1"
        return [false, "VPS_DEPLOY_SKIP_PREFLIGHT=1 needs the human-only I_UNDERSTAND_FAST_DEPLOY=1"] unless env["I_UNDERSTAND_FAST_DEPLOY"] == "1"

        return [true, "#{lead} VPS_DEPLOY_SKIP_PREFLIGHT=1 I_UNDERSTAND_FAST_DEPLOY=1 #{tail}"]
      end

      results = run(root:, runner:)
      out.puts(report(results))
      return [false, "preflight failed on #{sha[0, 9]}; nothing was sent to the box"] unless results.all?(&:ok)

      [true, "#{lead} VPS_DEPLOY_PREFLIGHT_SHA=#{sha} #{tail}"]
    end

    def git_out(root, *argv)
      Master::Io::Exec.capture2("git", "-C", root, *argv, err: File::NULL).first.to_s.strip
    end

    def report(results)
      failed = results.find { |r| !r.ok }
      lines = results.map { |r| "#{r.ok ? 'ok  ' : 'FAIL'} preflight #{r.name}" }
      return (lines << "preflight: all #{results.size} checks passed").join("\n") unless failed

      lines << failed.detail.to_s.lines.map { |l| "       #{l.rstrip}" }.join("\n")
      lines << "preflight: #{failed.name} FAILED - this commit does not boot. Nothing was stopped or pulled onto the box."
      lines.join("\n")
    end
  end
end

exit Operator::DeployPreflight.main(ARGV) if $PROGRAM_NAME == __FILE__
