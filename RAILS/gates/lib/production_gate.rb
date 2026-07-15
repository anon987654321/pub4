# frozen_string_literal: true

require "open3"
require "yaml"
require_relative "../../../OPENBSD/lib/gate_result"
require_relative "master_web_assets_gate"
require_relative "master_tts_gate"

module Deploy
  class ProductionGate
    ROOT = File.expand_path("../../..", __dir__)
    RAILS_ROOT = File.join(ROOT, "RAILS")
    APPS_YML = File.join(RAILS_ROOT, "apps.yml")
    SHARED_DEPLOY = File.join(RAILS_ROOT, "_deploy.sh")

    def self.run(skip_nested: false)
      new(skip_nested: skip_nested).run
    end

    def initialize(skip_nested: false)
      @skip_nested = skip_nested
      @result = GateResult.new
    end

    def run
      apps = load_yaml(APPS_YML).fetch("apps")
      env_sample = File.join(RAILS_ROOT, "env.sample")

      tracked_master_keys = git_ls_files("RAILS/*/config/master.key")
      @result.fail("tracked Rails master keys: #{tracked_master_keys.join(', ')}") if tracked_master_keys.any?
      @result.fail("missing shared RAILS/env.sample") unless File.file?(env_sample)

      apps.each do |name, metadata|
        check_app(name, metadata)
      end

      run_nested_gates unless @skip_nested
      @result
    end

    private

    def check_app(name, metadata)
      app_dir = File.join(RAILS_ROOT, name)
      return unless File.directory?(app_dir)

      production = File.join(app_dir, "config", "environments", "production.rb")
      gemfile = File.join(app_dir, "Gemfile")
      ci_bin = File.join(app_dir, "bin", "ci")
      deploy_script = File.join(ROOT, metadata.fetch("deploy_script"))
      domain = metadata.fetch("domain")
      app_failures = []

      unless File.file?(production)
        @result.fail("#{name}: missing config/environments/production.rb")
        return
      end

      baseline = File.join(RAILS_ROOT, "shared", "config", "environments", "production_baseline.rb")
      prod_active = active_lines(production)
      prod_active += active_lines(baseline) if File.read(production).include?("production_baseline")
      fail_app!(app_failures, "production config still has active example.com placeholder") if prod_active.any? { |line| line.include?("example.com") }
      fail_app!(app_failures, "production config must trust relayd with config.assume_ssl = true") unless prod_active.any? { |line| line.match?(/\bconfig\.assume_ssl\s*=\s*true\b/) }
      fail_app!(app_failures, "TLS terminates at relayd; do not enable config.force_ssl in Rails") if prod_active.any? { |line| line.match?(/\bconfig\.force_ssl\s*=\s*true\b/) }
      mailer_ok = prod_active.any? { |line| line.include?(domain) && (line.include?("action_mailer.default_url_options") || line.include?("mailer_host:")) }
      fail_app!(app_failures, "production mailer host must use #{domain}") unless mailer_ok
      hosts_ok = prod_active.any? { |line| line.include?(domain) && (line.include?("config.hosts") || line.include?("hosts:")) }
      fail_app!(app_failures, "production config.hosts must include #{domain}") unless hosts_ok
      prod_text = prod_active.join("\n")
      fail_app!(app_failures, "production host_authorization must keep /up available") unless prod_text.include?("config.host_authorization") && prod_text.include?("/up")
      fail_app!(app_failures, "production host_authorization must keep /health available") unless prod_text.include?("config.host_authorization") && prod_text.include?("/health")

      routes = File.join(app_dir, "config", "routes.rb")
      if File.file?(routes)
        routes_text = File.read(routes)
        fail_app!(app_failures, "routes must load shared fleet health endpoint") unless routes_text.include?("fleet.rb")
      else
        fail_app!(app_failures, "missing config/routes.rb")
      end
      fail_app!(app_failures, "Solid Cache must be enabled") unless prod_active.any? { |line| line.match?(/\bconfig\.cache_store\s*=\s*:solid_cache_store\b/) }
      fail_app!(app_failures, "Solid Queue must be enabled") unless prod_active.any? { |line| line.match?(/\bconfig\.active_job\.queue_adapter\s*=\s*:solid_queue\b/) }

      if File.file?(gemfile)
        gemfile_text = File.read(gemfile)
        @result.warn("#{name}: Gemfile has no explicit ruby version") unless gemfile_text.match?(/^ruby\s+/)
        fail_app!(app_failures, "Gemfile must target Rails 8.1") unless gemfile_text.match?(/^gem ['"]rails['"], ['"]~> 8\.1/)
        if gemfile_text.include?("solid_queue")
          deploy_yml = File.join(app_dir, "config", "deploy.yml")
          rcd = File.join(ROOT, "OPENBSD", "etc", "rc.d", name)
          deploy_yml_text = File.file?(deploy_yml) ? File.read(deploy_yml) : ""
          rcd_text = File.file?(rcd) ? File.read(rcd) : ""
          fail_app!(app_failures, "Solid Queue deploy.yml must set SOLID_QUEUE_IN_PUMA: true") unless deploy_yml_text.include?("SOLID_QUEUE_IN_PUMA: true")
          fail_app!(app_failures, "rc.d must export SOLID_QUEUE_IN_PUMA=true for Falcon") unless rcd_text.include?("SOLID_QUEUE_IN_PUMA=true")
        end
      else
        fail_app!(app_failures, "missing Gemfile")
      end

      ci_config = File.join(app_dir, "config", "ci.rb")
      shared_ci = File.join(RAILS_ROOT, "shared", "config", "ci.rb")
      if File.file?(ci_bin)
        ci_parts = [File.read(ci_bin)]
        ci_parts << File.read(ci_config) if File.file?(ci_config)
        ci_parts << File.read(shared_ci) if File.file?(shared_ci) && ci_parts.join.include?("shared/config/ci")
        ci_text = ci_parts.join("\n")
        fail_app!(app_failures, "bin/ci must be executable") unless File.executable?(ci_bin)
        fail_app!(app_failures, "bin/ci must run RuboCop") unless ci_text.include?("rubocop")
        fail_app!(app_failures, "bin/ci must run bundler-audit") unless ci_text.include?("bundler-audit")
        fail_app!(app_failures, "bin/ci must run Brakeman") unless ci_text.include?("brakeman")
        fail_app!(app_failures, "bin/ci must run Rails tests") unless ci_text.include?("rails") && ci_text.include?("test")
        fail_app!(app_failures, "bin/ci must pin BUNDLER_AUDIT_UPDATE (offline VPS)") unless ci_text.include?("BUNDLER_AUDIT_UPDATE")
        fail_app!(app_failures, "bin/ci must set NPM_CONFIG_CACHE (copy-tree npm)") unless ci_text.include?("NPM_CONFIG_CACHE")
        guard = File.join(RAILS_ROOT, "shared", "lib", "pub4", "ci_guard.rb")
        paths = File.join(RAILS_ROOT, "shared", "lib", "pub4", "deploy_paths.rb")
        fail_app!(app_failures, "missing shared/lib/pub4/ci_guard.rb") unless File.file?(guard)
        fail_app!(app_failures, "missing shared/lib/pub4/deploy_paths.rb") unless File.file?(paths)
        fail_app!(app_failures, "shared CI must use Pub4::CiGuard") unless ci_text.include?("Pub4::CiGuard")
        fail_app!(app_failures, "shared CI must skip importmap on VPS") unless ci_text.include?("unless vps_host")
        fail_app!(app_failures, "shared CI must skip RuboCop on VPS") unless ci_text.match?(/rubocop.*unless vps_host|unless vps_host.*rubocop/m)
      else
        fail_app!(app_failures, "missing bin/ci")
      end

      if File.file?(deploy_script)
        deploy_text = File.read(deploy_script)
        deploy_contract = [deploy_text, File.file?(SHARED_DEPLOY) ? File.read(SHARED_DEPLOY) : ""].join("\n")
        fail_app!(app_failures, 'deploy script must call shared deploy entrypoint') unless deploy_text.include?('deploy_tracked_app "$APP_NAME"')
        fail_app!(app_failures, "deploy contract must require ruby34") unless deploy_contract.include?("need_cmd ruby34")
        fail_app!(app_failures, "deploy contract must configure relayd for #{domain}") unless deploy_contract.include?("relayd_add_relay")
      else
        fail_app!(app_failures, "missing deploy script #{metadata.fetch('deploy_script')}")
      end

      app_failures.each { |failure| @result.fail("#{name}: #{failure}") }
    end

    def run_nested_gates
      assets = MasterWebAssetsGate.run
      assets.failures.each { |failure| @result.fail(failure) }
      puts "MASTER/web assets gate passed (#{MasterWebAssetsGate::REQUIRED.size} required assets present)." if assets.ok?

      tts = MasterTtsGate.run
      tts.failures.each { |failure| @result.fail(failure) }
      puts "MASTER TTS gate passed." if tts.ok?
    end

    def fail_app!(app_failures, message)
      app_failures << message
    end

    def active_lines(path)
      File.readlines(path, chomp: true).reject { |line| line.strip.start_with?("#") }
    end

    def git_ls_files(pattern)
      stdout, status = Open3.capture2("git", "-C", ROOT, "ls-files", pattern)
      status.success? ? stdout.lines.map(&:chomp).reject(&:empty?) : []
    end

    def load_yaml(path)
      YAML.safe_load(File.read(path))
    end
  end
end