# frozen_string_literal: true

require "json"
require "yaml"
require "open3"
require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  # Is what is committed actually running?
  #
  # 2026-07-29 produced nine production faults and most of them were already
  # understood — they had simply never shipped. brgen's deploys had been failing
  # on one drifted var() fallback since 2026-07-25, so the takeaway 500 fix and
  # the tab-bar overlap fix sat in the repo, correct, for four days. Later the
  # same day two more fixes (every TV channel page 404ing, an invisible primary
  # button on the front page) stayed committed-but-undeployed until someone
  # thought to ask.
  #
  # Every one of those was findable with two facts we already had: the SHA in
  # /var/db/pub4/last_deploy_<app>.json, and `git log <sha>..HEAD -- <paths>`.
  # Nothing was watching them. This does.
  #
  # Deliberately NOT a soft skip when the stamps are missing. Off the deploy
  # host there are no stamps and this gate genuinely cannot judge, so it says so
  # rather than reporting success it has not earned.
  #
  # A warning was not enough to carry that: `GateResult#ok?` only asked about
  # hard failures, so the shim still printed "ok: no deploy drift detected"
  # directly beneath "Nothing was checked." `GateResult#inconclusive!` is the
  # third state that fixes it, and the sixteen other gates in this suite that
  # passed on an absent precondition now use it too.
  class DeployDriftGate
    ROOT = File.expand_path("../../../..", __dir__)
    STAMP_DIR = ENV.fetch("PUB4_STAMP_DIR", "/var/db/pub4")
    APPS_YML = File.join(ROOT, "RAILS", "apps.yml")

    # Paths whose changes mean an app is stale. The shared engine is compiled
    # into every Rails app's bundle, so a shared-only commit still leaves each
    # app behind until it redeploys.
    SHARED_PATHS = ["RAILS/shared"].freeze
    MASTER_PATHS = ["MASTER/web", "MASTER/lib", "MASTER/data"].freeze

    def self.run = new.run

    def run
      result = GateResult.new
      unless git_repo?
        result.inconclusive!("deploy_drift: not a git checkout at #{ROOT} — cannot compare deployed SHA to HEAD")
        return result
      end

      stamps = read_stamps
      if stamps.empty?
        result.inconclusive!(
          "deploy_drift: no deploy stamps under #{STAMP_DIR} — this gate only has something to " \
          "compare on the deploy host"
        )
        return result
      end

      head = capture("git", "rev-parse", "HEAD").strip
      stamps.each { |app, stamp| check_app(result, app, stamp, head) }
      # Say what was compared, so the pass line is backed by a visible claim
      # rather than by the absence of failures.
      result.warn("deploy_drift: compared #{stamps.size} app(s) against HEAD #{head[0, 9]} — #{stamps.keys.join(', ')}")
      result
    end

    private

    def check_app(result, app, stamp, head)
      sha = stamp["sha"].to_s
      status = stamp["status"].to_s

      if sha.empty?
        result.fail("deploy_drift: #{app} stamp has no sha (#{STAMP_DIR}/last_deploy_#{app}.json)")
        return
      end

      # ci_ok means CI passed but vps-deploy had not finished; ok is the only
      # value that means the app is actually running this SHA.
      result.fail("deploy_drift: #{app} last deploy status is #{status.inspect}, not \"ok\"") unless status == "ok"

      unless known_commit?(sha)
        result.inconclusive!("deploy_drift: #{app} deployed #{sha}, which this checkout does not contain — fetch and re-run")
        return
      end

      paths = paths_for(app)
      commits = capture("git", "log", "--oneline", "#{sha}..#{head}", "--", *paths).lines.map(&:strip).reject(&:empty?)
      return if commits.empty?

      subjects = commits.first(3).map { |c| c.sub(/\A\h+\s/, "") }
      more = commits.size > 3 ? " (+#{commits.size - 3} more)" : ""
      result.fail(
        "deploy_drift: #{app} is running #{sha} but #{commits.size} commit(s) since then touch " \
        "#{paths.join(', ')} — #{subjects.join(' | ')}#{more}"
      )
    end

    def paths_for(app)
      return MASTER_PATHS if app == "master"

      root = app_roots[app] || "RAILS/#{app}"
      [root, *SHARED_PATHS]
    end

    def app_roots
      @app_roots ||= begin
        yaml = YAML.safe_load_file(APPS_YML, aliases: true)
        Hash(yaml["apps"]).to_h { |name, cfg| [name, Hash(cfg)["deploy_root"] || "RAILS/#{name}"] }
      rescue StandardError => e
        warn "deploy_drift: apps config unreadable (#{e.class})"
        {}
      end
    end

    def read_stamps
      Dir.glob(File.join(STAMP_DIR, "last_deploy_*.json")).filter_map do |path|
        app = File.basename(path).sub(/\Alast_deploy_/, "").sub(/\.json\z/, "")
        parsed = JSON.parse(File.read(path))
        [app, parsed]
      rescue StandardError # scan: intentional — one app's unreadable state drops from the drift table; the gate reports the table
        nil
      end.sort.to_h
    end

    def known_commit?(sha)
      _out, status = Open3.capture2e("git", "-C", ROOT, "cat-file", "-e", "#{sha}^{commit}")
      status.success?
    end

    def git_repo?
      _out, status = Open3.capture2e("git", "-C", ROOT, "rev-parse", "--git-dir")
      status.success?
    end

    def capture(*args)
      out, status = Open3.capture2e("git", "-C", ROOT, *args[1..])
      status.success? ? out : ""
    end
  end
end
