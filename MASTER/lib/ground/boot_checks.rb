# frozen_string_literal: true

require "fileutils"

module Master
  module Ground
    # Pre-flight checks run before any infrastructure boot. Fails fast
    # with structured diagnostics so callers can decide abort vs degrade.
    module BootChecks
      CheckResult = Data.define(:name, :ok, :message, :severity)

      SEVERITIES = %i[fatal warning info].freeze

      class << self
        def run(root: Dir.pwd, strict: false)
          results = [
            check_master_dir(root),
            check_config_readable(root),
            check_config_valid(root),
            check_data_dir(root),
            check_soul_yaml(root),
            check_rules_yaml(root),
            check_providers_yaml(root),
            check_models_yaml(root),
            check_voice_yaml(root),
            check_limits_yaml(root),
            check_web_dir(root),
            check_constitution_chain(root),
          ]

          abort_on_fatals(results)
          warn_on_warnings(results)
          results
        end

        def abort_on_fatals(results)
          fatals = results.select { |r| !r.ok && r.severity == :fatal }
          return if fatals.empty?

          messages = fatals.map { |f| "  ✗ #{f.name}: #{f.message}" }.join("\n")
          abort "BOOT FAILED — #{fatals.size} fatal check(s):\n#{messages}"
        end

        def warn_on_warnings(results)
          warnings = results.select { |r| !r.ok && r.severity == :warning }
          return if warnings.empty?

          messages = warnings.map { |w| "  ⚠ #{w.name}: #{w.message}" }.join("\n")
          warn "BOOT WARNINGS — #{warnings.size} warning(s):\n#{messages}"
        end

        private

        def ok(name, message = nil)
          CheckResult.new(name:, ok: true, message:, severity: :info)
        end

        def fail(name, message, severity: :fatal)
          CheckResult.new(name:, ok: false, message:, severity:)
        end

        def warn_check(name, message)
          CheckResult.new(name:, ok: false, message:, severity: :warning)
        end

        def check_master_dir(root)
          dir = File.join(root, ".master")
          if File.directory?(dir)
            ok(".master_dir", "writable state directory present")
          else
            create_master_dir(dir)
          end
        end

        def create_master_dir(dir)
          FileUtils.mkdir_p(dir)
          ok(".master_dir", "created writable state directory")
        rescue StandardError => e
          fail(".master_dir", "cannot create: #{e.message}")
        end

        def check_config_readable(root)
          path = File.join(root, ".master", "config.yml")
          return ok("config_readable", "no config yet — defaults apply") unless File.exist?(path)

          YAML.safe_load_file(path, aliases: true)
          ok("config_readable", "config parses as valid YAML")
        rescue Psych::Exception => e
          fail("config_readable", "invalid YAML: #{e.message}")
        end

        def check_config_valid(root)
          config = Config.new(root)
          errors = config.validate
          if errors.empty?
            ok("config_valid", "all config values within bounds")
          else
            fail("config_valid", errors.join("; "), severity: :fatal)
          end
        rescue StandardError => e
          fail("config_valid", "validation error: #{e.message}")
        end

        def check_data_dir(root)
          dir = File.join(root, "data")
          return fail("data_dir", "missing data/ directory") unless File.directory?(dir)

          required = %w[soul.yml rules.yml limits.yml]
          missing = required.reject { |f| File.exist?(File.join(dir, f)) }
          if missing.empty?
            ok("data_dir", "required law files present")
          else
            fail("data_dir", "missing required: #{missing.join(", ")}")
          end
        end

        def check_soul_yaml(root)
          check_yaml_file(root, "data/soul.yml", "soul_yaml")
        end

        def check_rules_yaml(root)
          check_yaml_file(root, "data/rules.yml", "rules_yaml")
        end

        def check_providers_yaml(root)
          check_yaml_file(root, "data/providers.yml", "providers_yaml", required: false)
        end

        def check_models_yaml(root)
          check_yaml_file(root, "data/models.yml", "models_yaml", required: false)
        end

        def check_voice_yaml(root)
          check_yaml_file(root, "data/voice.yml", "voice_yaml", required: false)
        end

        def check_limits_yaml(root)
          check_yaml_file(root, "data/limits.yml", "limits_yaml", required: false)
        end

        def check_yaml_file(root, rel_path, name, required: true)
          path = File.join(root, rel_path)
          return ok(name, "optional file absent") if !required && !File.exist?(path)
          return fail(name, "missing #{rel_path}") unless File.exist?(path)

          data = YAML.safe_load_file(path, aliases: true)
          return fail(name, "#{rel_path} is not a Hash") unless data.is_a?(Hash)

          ok(name, "#{rel_path} valid")
        rescue Psych::Exception => e
          fail(name, "#{rel_path} invalid YAML: #{e.message}")
        rescue StandardError => e
          fail(name, "#{rel_path} error: #{e.message}")
        end

        def check_web_dir(root)
          dir = File.join(root, "web")
          return ok("web_dir", "no web face — OK for headless") unless File.directory?(dir)

          gemfile = File.join(dir, "Gemfile")
          if File.exist?(gemfile)
            ok("web_dir", "web face with Gemfile detected")
          else
            warn_check("web_dir", "web/ exists but no Gemfile — may be incomplete")
          end
        end

        # Wire constitution Parliament chain integrity (from kimi patches)
        def check_constitution_chain(root)
          require "ground/constitution"
          parliament = Master::Ground::Parliament.new
          chain_ok, err = parliament.verify_chain
          if chain_ok
            ok("constitution_chain", "cryptographic amendment chain intact")
          else
            fail("constitution_chain", "chain verification failed: #{err}", severity: :warning)
          end
        rescue StandardError => e
          warn_check("constitution_chain", "verification failed: #{e.message}")
        end
      end
    end
  end
end
