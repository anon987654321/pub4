#!/usr/bin/env ruby
# frozen_string_literal: true

# Boots brgen, amber, bsdports and the MASTER face on the ports every check
# probes, so the live half of the suite measures something.
#
#   bin/operator triangle up      boot, migrate, wait for /up, print status
#   bin/operator triangle up bsdports   the same, for the named surfaces only
#   bin/operator triangle status  which ports answer
#   bin/operator triangle down    stop what this script started
#
# Why this exists: the browser and live-HTTP checks belong on the deploy host,
# and vm23 has no headroom to run them (the old backlog item 2). So they ran nowhere,
# and every check whose live half was skipped still printed PASSED. None of the
# three apps ships bin/dev, so this is the one way to boot them together.
#
# Pending migrations are the usual reason a booted app answers 500 rather than
# 200, so `up` migrates before it waits.

require "fileutils"
require "net/http"
require_relative "../../lib/io/exec"
require "yaml"
require_relative "../../lib/operator/ruby_runner"

module Deploy
  module Triangle
    ROOT = File.expand_path("../../..", __dir__)
    RAILS_ROOT = File.join(ROOT, "RAILS")
    RUBY = Operator::RubyRunner.ruby_cmd
    BUNDLE = Operator::RubyRunner.bundle_cmd
    RUN_DIR = File.join(RAILS_ROOT, "tmp", "triangle")
    BOOT_TIMEOUT = Integer(ENV.fetch("TRIANGLE_BOOT_TIMEOUT", "180"))

    # Ports come from apps.yml so this file cannot disagree with the checks.
    def self.apps
      @apps ||= begin
        config = YAML.safe_load_file(File.join(RAILS_ROOT, "apps.yml")).fetch("apps")
        config.map { |name, row| { name:, port: row.fetch("port"), dir: File.join(RAILS_ROOT, name), rails: true } }
      end
    end

    def self.ruby_version
      path = File.join(ROOT, ".ruby-version")
      File.file?(path) ? File.read(path).strip : ENV.fetch("RBENV_VERSION", "")
    end

    # bin/operator runs under MASTER's own bundler environment, and a child `bundle exec`
    # inherits BUNDLE_GEMFILE from it: every app then booted on MASTER/Gemfile and died with
    # "cannot load bootsnap/setup" or "rails/commands". Each app is pinned to its own Gemfile
    # and the parent's bundler state is dropped, so the same command works from any caller.
    def self.env_for(app)
      { "RBENV_VERSION" => ruby_version, "RAILS_ENV" => "development", "PORT" => app[:port].to_s,
        "RAILS_LOG_LEVEL" => ENV.fetch("RAILS_LOG_LEVEL", "info"),
        "BUNDLE_GEMFILE" => File.join(app[:dir], "Gemfile"),
        "BUNDLE_BIN_PATH" => nil, "BUNDLER_SETUP" => nil, "BUNDLER_VERSION" => nil, "RUBYOPT" => nil, "RUBYLIB" => nil,
        "GEM_HOME" => nil, "GEM_PATH" => nil, "BUNDLE_PATH" => nil, "BUNDLE_APP_CONFIG" => nil,
        "BUNDLE_USER_CONFIG" => nil, "BUNDLE_DISABLE_SHARED_GEMS" => nil, "BUNDLE_LOCKFILE" => nil }
    end

    def self.listening?(port)
      response = Net::HTTP.start("127.0.0.1", port, open_timeout: 2, read_timeout: 4) { |http| http.get("/up") }
      response.code.to_i.between?(200, 399)
    rescue StandardError
      false
    end

    # The process listening on a port and the directory it was started in. lsof
    # is the only portable way to ask; nil when nothing listens or lsof cannot say.
    def self.listener(port)
      out, status = Master::Io::Exec.capture2e("lsof", "-nP", "-iTCP:#{port}", "-sTCP:LISTEN", "-Fp", timeout: 10)
      pid = status.success? ? out[/^p(\d+)/, 1] : nil
      return unless pid

      cwd_out, = Master::Io::Exec.capture2e("lsof", "-a", "-p", pid, "-d", "cwd", "-Fn", timeout: 10)
      { pid: pid.to_i, cwd: cwd_out[/^n(.+)$/, 1].to_s }
    rescue StandardError
      nil
    end

    # A server answering on the port is only this checkout's if it was started in
    # this checkout. One left behind by a sibling agent worktree (pub4-<name>)
    # answers /up too, so a booted run measured another tree's code. Those are
    # stopped; a server in the main checkout or anywhere else is the operator's
    # and is reported, never killed.
    SIBLING_WORKTREE = %r{/pub4-[^/]+/RAILS/}

    def self.foreign_listener(app)
      found = listener(app[:port])
      return if found.nil? || found[:cwd].start_with?(app[:dir])

      found
    end

    def self.reap_sibling(app, found)
      return false unless found[:cwd].match?(SIBLING_WORKTREE)

      warn "triangle: #{app[:name]} port #{app[:port]} was held by pid #{found[:pid]} from #{found[:cwd]}; stopping it"
      Process.kill("TERM", found[:pid])
      sleep 2
      true
    rescue Errno::ESRCH, Errno::EPERM
      true
    end

    # An empty development database makes db:prepare run the seeds, which attach
    # images and took over ten minutes on a fresh /fix worktree. A seeded copy in
    # the main checkout is the same data, so a worktree starts from it.
    def self.seed_from_main(app)
      target = File.join(app[:dir], "storage")
      return if File.file?(File.join(target, "development.sqlite3"))

      common, status = Master::Io::Exec.capture2e("git", "-C", ROOT, "rev-parse", "--path-format=absolute", "--git-common-dir", timeout: 10)
      return unless status.success?

      source = File.join(File.dirname(common.strip), "RAILS", File.basename(app[:dir]), "storage")
      return if File.expand_path(source) == File.expand_path(target)
      return unless File.file?(File.join(source, "development.sqlite3"))

      FileUtils.mkdir_p(target)
      FileUtils.cp_r(File.join(source, "."), target)
      puts "triangle: #{app[:name]} database copied from #{source}"
    rescue StandardError => e
      warn "triangle: #{app[:name]} seeded database not copied (#{e.message}); db:prepare will seed"
    end

    def self.pid_file(app) = File.join(RUN_DIR, "#{app[:name]}.pid")

    def self.log_file(app) = File.join(RUN_DIR, "#{app[:name]}.log")

    # application.css is built output and git-ignored, so a fresh worktree has
    # none: every page of an app whose layout links it answered 500 and the
    # rendered checks screenshotted Rails' error page instead of the layout.
    def self.build_css(app)
      return true unless File.file?(File.join(app[:dir], "app", "assets", "stylesheets", "application.scss"))
      return true if File.file?(File.join(app[:dir], "app", "assets", "builds", "application.css"))

      out, status = Master::Io::Exec.capture2e(RUBY, File.join(ROOT, "MASTER", "tools", "rails", "build_all_css.rb"), "--app", app[:name], chdir: ROOT, timeout: BOOT_TIMEOUT)
      return true if status.success?

      warn "triangle: #{app[:name]} css build failed\n#{out.lines.last(8).join}"
      false
    end

    def self.migrate(app)
      seed_from_main(app)
      return false unless build_css(app)

      out, status = Master::Io::Exec.capture2e(env_for(app), BUNDLE, "exec", RUBY, "bin/rails", "db:prepare", chdir: app[:dir], timeout: BOOT_TIMEOUT)
      return true if status.success?

      warn "triangle: #{app[:name]} db:prepare failed\n#{out.lines.last(8).join}"
      false
    end

    # Propshaft pins the digest it serves through public/assets/.manifest.json,
    # and Rails says so out loud when you precompile in development: "Rails will
    # not serve any changed assets until you delete public/assets/.manifest.json".
    # So a stylesheet edit plus dartsass:build changes the file on disk and
    # nothing that a browser — or a rendered check — actually reads. On 2026-08-24
    # that cost three edit/build/measure rounds against an unchanged number while
    # the fix was already compiled in.
    #
    # Clearing it here rather than documenting it: a manual step that only
    # matters after a CSS change, and whose absence produces a plausible wrong
    # measurement rather than an error, is a step that will be skipped.
    def self.clear_asset_manifest(app)
      manifest = File.join(app[:dir], "public", "assets", ".manifest.json")
      File.delete(manifest) if File.file?(manifest)
    end

    def self.boot(app)
      clear_asset_manifest(app)
      FileUtils.mkdir_p(RUN_DIR)
      # Truncated, not appended. What this log is for is "why did this boot
      # fail", which the current boot answers; keeping every prior one grew
      # brgen.log to 1.8 GB and filled the disk.
      log = File.open(log_file(app), "w")
      pid = Process.spawn(
        env_for(app),
        BUNDLE, "exec", RUBY, "bin/rails", "server", "-p", app[:port].to_s, "-b", "127.0.0.1",
        chdir: app[:dir], out: log, err: log, pgroup: true
      )
      Process.detach(pid)
      File.write(pid_file(app), pid)
      pid
    end

    def self.wait_for(app)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + BOOT_TIMEOUT
      until Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        return true if listening?(app[:port])

        sleep 2
      end
      false
    end

    # Named surfaces only, when names are given. One app with a prepared
    # database boots in about a minute, where all four wait on brgen's
    # db:prepare, so a rendered check can measure one app cheaply.
    def self.selected(names)
      return apps if names.empty?

      unknown = names - apps.map { |app| app[:name] }
      abort "triangle: no surface named #{unknown.join(', ')}" unless unknown.empty?
      apps.select { |app| names.include?(app[:name]) }
    end

    def self.up(names = [])
      failed = []
      selected(names).each do |app|
        if listening?(app[:port])
          foreign = foreign_listener(app)
          if foreign && !reap_sibling(app, foreign)
            warn "triangle: #{app[:name]} port #{app[:port]} is held by pid #{foreign[:pid]} running from #{foreign[:cwd]}, not this checkout"
            failed << app[:name]
            next
          end
          unless foreign
            puts "triangle: #{app[:name]} already up on #{app[:port]}"
            next
          end
        end
        unless File.directory?(app[:dir])
          warn "triangle: #{app[:name]} has no directory at #{app[:dir]}"
          failed << app[:name]
          next
        end

        unless migrate(app)
          failed << app[:name]
          next
        end
        boot(app)
        if wait_for(app)
          puts "triangle: #{app[:name]} up on #{app[:port]}"
        else
          warn "triangle: #{app[:name]} did not answer /up within #{BOOT_TIMEOUT}s — see #{log_file(app)}"
          failed << app[:name]
        end
      end
      failed
    end

    def self.status
      apps.map do |app|
        up = listening?(app[:port])
        puts "triangle: #{app[:name].ljust(9)} #{app[:port]} #{up ? 'up' : 'down'}"
        up
      end
    end

    def self.down(names = [])
      selected(names).each do |app|
        path = pid_file(app)
        unless File.file?(path)
          # A server whose pid file is gone (the run was killed) still holds the port.
          mine = listener(app[:port])
          if mine && mine[:cwd].start_with?(app[:dir])
            Process.kill("TERM", mine[:pid])
            puts "triangle: stopped #{app[:name]} (pid #{mine[:pid]}, no pid file)"
          end
          next
        end

        pid = File.read(path).to_i
        begin
          Process.kill("TERM", -pid)
          puts "triangle: stopped #{app[:name]} (pid #{pid})"
        rescue Errno::ESRCH
          puts "triangle: #{app[:name]} already gone"
        end
        FileUtils.rm_f(path)
      end
    end
  end
end

if File.expand_path($PROGRAM_NAME) == File.expand_path(__FILE__)
  case ARGV[0]
  when nil, "up"
    failed = Deploy::Triangle.up(ARGV.drop(1))
    exit(failed.empty? ? 0 : 1)
  when "status"
    exit(Deploy::Triangle.status.all? ? 0 : 1)
  when "down"
    Deploy::Triangle.down(ARGV.drop(1))
  else
    warn "usage: bin/operator triangle [up|status|down] [surface ...]"
    exit 2
  end
end
