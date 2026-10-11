# frozen_string_literal: true

require "json"
require "net/http"
require "open3"
require "optparse"
require "socket"
require "yaml"
require_relative "../fix/routes_manifest"

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
  #   smoke      OPENBSD/bin/deploy-smoke.sh, the rehearsal subset that needs only
  #              the box itself.
  #
  # It reads and reports. Rolling back is a human decision, so on failure it
  # prints the previous deployed SHA and the commands, and runs none of them.
  module Canary
    HEADER_LIMIT_BYTES = 8 * 1024
    DEFAULT_BUDGET_MS = 3000
    SERVICES = %w[master brgen amber bsdports relayd].freeze
    MASTER = { "domain" => "ai.brgen.no", "port" => 53_187 }.freeze
    SKIPPED_PREFIXES = %w[/internal /rails /cable /admin].freeze
    Reply = Struct.new(:status, :headers, :body, :elapsed_ms, keyword_init: true)
    Result = Struct.new(:name, :ok, :detail, keyword_init: true)

    module_function

    def main(argv, root: File.expand_path("../../..", __dir__), out: $stdout, **runner_opts)
      opts = { mode: :local, apps: nil, budget_ms: DEFAULT_BUDGET_MS, smoke: true, json: false }
      OptionParser.new do |o|
        o.on("--local") { opts[:mode] = :local }
        o.on("--public") { opts[:mode] = :public }
        o.on("--app LIST") { |v| opts[:apps] = v.split(",") }
        o.on("--budget-ms N", Integer) { |v| opts[:budget_ms] = v }
        o.on("--no-smoke") { opts[:smoke] = false }
        o.on("--json") { opts[:json] = true }
      end.parse!(argv.dup)

      results = Runner.new(root:, **opts.slice(:mode, :apps, :budget_ms, :smoke), **runner_opts).run
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

      def advice(root:, git: ->(*argv) { Open3.capture2(*argv, err: File::NULL).first.to_s.strip })
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
      def initialize(root:, mode: :local, apps: nil, budget_ms: DEFAULT_BUDGET_MS, smoke: true,
                     http: nil, shell: nil, connect: nil)
        @root = root
        @mode = mode
        @budget_ms = budget_ms
        @smoke = smoke
        @http = http || method(:fetch)
        @shell = shell || ->(*argv) { Open3.capture2e(*argv) }
        @connect = connect || method(:open_port)
        @apps = load_apps(apps)
      end

      def run
        results = []
        results.concat(port_checks) if @mode == :local
        results.concat(service_checks) if @mode == :local
        results.concat(route_checks)
        results.concat(smoke_check) if @smoke
        results
      end

      private

      def load_apps(only)
        data = YAML.safe_load_file(File.join(@root, "RAILS", "apps.yml"), aliases: true).fetch("apps")
        apps = data.select { |_, v| v["public"] && v["port"] }.transform_values { |v| v.slice("domain", "port") }
        apps["master"] = MASTER.dup
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
end
