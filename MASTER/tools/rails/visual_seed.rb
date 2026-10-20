#!/usr/bin/env ruby
# frozen_string_literal: true

# Loads believable Norwegian content into the LOCAL development database of
# brgen, amber and bsdports, so the visual pass judges full pages instead of
# empty ones.
#
#   bin/operator visual seed [app ...] [--scale=N] [--yes]   plan, or with --yes run
#   bin/operator visual unseed [app ...]                      put the backed-up database back
#   bin/operator visual status                                which apps carry a seed
#
# The content is not written here. Each app's db/seeds.rb already authors
# posts, comments, profiles, listings and messages (brgen's through
# Brgen::PlausibleContent and the per-city seeders), so this runs it and adds
# only the safety around it: development environment only, never a server box,
# never an app that is serving, and the primary database copied aside first.
# Those seeds clear the development tables before they fill them, which is why
# the copy exists and why nothing runs without --yes.
#
# The marker MASTER/.master/visual_seed/<app>/seeded.json labels the seed and
# names the copy, so `unseed` removes exactly what `seed` added.

require "fileutils"
require "json"
require "net/http"
require "rbconfig"
require "time"
require "yaml"
require_relative "../../lib/io/exec"
require_relative "../../lib/operator/ruby_runner"

module Deploy
  class VisualSeed
    ROOT = File.expand_path("../../..", __dir__)
    APPS = %w[brgen amber bsdports].freeze
    SCALE = 2
    TIMEOUT = Integer(ENV.fetch("VISUAL_SEED_TIMEOUT", "900"))

    def initialize(root: ROOT, out: $stdout, runner: nil, serving: nil)
      @root = root
      @out = out
      @runner = runner || method(:run_rails)
      @serving = serving || method(:port_answers?)
    end

    def refusal
      return "refusing: this is an OpenBSD box, the seed is for the local triangle" if RbConfig::CONFIG["host_os"].to_s.match?(/openbsd/i)
      return "refusing: /home/dev/pub4 exists, this looks like vm23" if File.directory?("/home/dev/pub4")
      return "refusing: DATABASE_URL is set, the seed only touches storage/development.sqlite3" if ENV["DATABASE_URL"]

      nil
    end

    def selected(names)
      names = names.empty? ? APPS : names
      unknown = names - APPS
      raise ArgumentError, "no seedable app named #{unknown.join(", ")} (#{APPS.join(", ")})" unless unknown.empty?

      names
    end

    def seed(names, scale: SCALE, yes: false)
      if (why = refusal)
        @out.puts("visual seed: #{why}")
        return 2
      end
      apps = selected(names)
      unless yes
        apps.each { |app| @out.puts("visual seed: would seed #{app} at SEED_SCALE=#{scale}, copying #{relative(database(app))} first") }
        @out.puts("visual seed: nothing run; add --yes (the app seeds clear development tables first)")
        return 0
      end
      apps.map { |app| seed_one(app, scale) }.all? ? 0 : 1
    end

    def unseed(names)
      selected(names).each do |app|
        next @out.puts("visual seed: #{app} carries no seed") unless File.file?(marker(app))

        record = JSON.parse(File.read(marker(app)))
        restore(app, record)
        FileUtils.rm_rf(backup_dir(app))
        @out.puts("visual seed: #{app} restored to its state before the seed")
      end
      0
    end

    def status
      APPS.each do |app|
        record = File.file?(marker(app)) ? JSON.parse(File.read(marker(app))) : nil
        @out.puts("visual seed: #{app.ljust(9)} #{record ? "seeded #{record["at"]} (scale #{record["scale"]})" : "no seed"}")
      end
      0
    end

    def marker(app) = File.join(backup_dir(app), "seeded.json")
    def backup_dir(app) = File.join(@root, "MASTER", ".master", "visual_seed", app)
    def app_dir(app) = File.join(@root, "RAILS", app)
    def database(app) = File.join(app_dir(app), "storage", "development.sqlite3")

    private

    def seed_one(app, scale)
      return skip(app, "already seeded; `visual unseed #{app}` first") if File.file?(marker(app))
      return skip(app, "serving on its port; `bin/operator triangle down #{app}` first") if @serving.call(port(app))
      return skip(app, "no directory at #{app_dir(app)}") unless File.directory?(app_dir(app))

      files = back_up(app)
      env = { "SEED_SCALE" => scale.to_s, "VISUAL_SEED" => "1" }
      ok = @runner.call(app, env, "db:prepare") && @runner.call(app, env, "db:seed")
      return restore_after_failure(app, files) unless ok

      File.write(marker(app), JSON.pretty_generate(at: Time.now.utc.iso8601, scale:, files:))
      @out.puts("visual seed: #{app} seeded (SEED_SCALE=#{scale}); `visual unseed #{app}` removes it")
      true
    end

    def skip(app, why)
      @out.puts("visual seed: #{app} skipped, #{why}")
      false
    end

    def back_up(app)
      FileUtils.mkdir_p(backup_dir(app))
      %w[.sqlite3 .sqlite3-wal .sqlite3-shm].filter_map do |suffix|
        source = database(app).sub(/\.sqlite3\z/, suffix)
        next unless File.file?(source)

        FileUtils.cp(source, File.join(backup_dir(app), File.basename(source)))
        File.basename(source)
      end
    end

    def restore(app, record)
      live = File.dirname(database(app))
      %w[development.sqlite3 development.sqlite3-wal development.sqlite3-shm].each { |name| FileUtils.rm_f(File.join(live, name)) }
      Array(record["files"]).each { |name| FileUtils.cp(File.join(backup_dir(app), name), File.join(live, name)) }
    end

    def restore_after_failure(app, files)
      restore(app, { "files" => files })
      FileUtils.rm_rf(backup_dir(app))
      @out.puts("visual seed: #{app} failed; its database is back as it was")
      false
    end

    def port(app) = YAML.safe_load_file(File.join(@root, "RAILS", "apps.yml")).fetch("apps").fetch(app).fetch("port")

    def port_answers?(port)
      Net::HTTP.start("127.0.0.1", port, open_timeout: 1, read_timeout: 2) { |http| http.get("/up") }
      true
    rescue StandardError
      false
    end

    def relative(path) = path.delete_prefix("#{@root}/")

    # The app's own Gemfile and Ruby, the parent's bundler state dropped, the
    # same way triangle boots it.
    def run_rails(app, env, task)
      version = File.file?(File.join(@root, ".ruby-version")) ? File.read(File.join(@root, ".ruby-version")).strip : ""
      full = env.merge("RAILS_ENV" => "development", "RBENV_VERSION" => version, "DATABASE_URL" => nil,
                       "BUNDLE_GEMFILE" => File.join(app_dir(app), "Gemfile"), "BUNDLE_BIN_PATH" => nil,
                       "BUNDLER_SETUP" => nil, "BUNDLER_VERSION" => nil, "RUBYOPT" => nil, "RUBYLIB" => nil)
      out, status = Master::Io::Exec.capture2e(full, Operator::RubyRunner.bundle_cmd, "exec", Operator::RubyRunner.ruby_cmd,
                                               "bin/rails", task, chdir: app_dir(app), timeout: TIMEOUT)
      @out.puts("visual seed: #{app} #{task} failed\n#{out.lines.last(8).join}") unless status.success?
      status.success?
    end
  end
end

if $PROGRAM_NAME == __FILE__
  args = ARGV.dup
  command = args.shift
  flags, names = args.partition { |arg| arg.start_with?("--") }
  scale = flags.filter_map { |flag| flag[/\A--scale=(\d+)\z/, 1] }.first&.to_i || Deploy::VisualSeed::SCALE
  seeder = Deploy::VisualSeed.new
  begin
    case command
    when "seed" then exit seeder.seed(names, scale:, yes: flags.include?("--yes"))
    when "unseed" then exit seeder.unseed(names)
    when "status" then exit seeder.status
    else
      warn "usage: bin/operator visual <seed [app ...] [--scale=N] [--yes] | unseed [app ...] | status>"
      exit 2
    end
  rescue ArgumentError => e
    warn "visual seed: #{e.message}"
    exit 2
  end
end
