# frozen_string_literal: true

require "fileutils"
require "yaml"
require_relative "../configuration_guard"

module Master
  module Ground
    # Pre-flight checks run before any infrastructure boot. Fails fast
    # with structured diagnostics so callers can decide abort vs degrade.
    module BootChecks
      CheckResult = Data.define(:name, :ok, :message, :severity)

      SEVERITIES = %i[fatal warning info].freeze

      class << self
        def run(root: Dir.pwd, strict: false)
          root = Master.master_root(root:)
          results = [
            check_master_dir(root),
            check_config_readable(root),
            check_config_valid(root),
            check_data_dir(root),
            check_soul_yaml(root),
            check_laws_yaml(root),
            check_tokens_yaml(root),
            check_providers_yaml(root),
            check_dynamic_tools_yaml(root),
            check_models_yaml(root),
            check_voice_yaml(root),
            *check_config_sections_yaml(root),
            check_web_dir(root),
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

          detail = warnings.map { |w| "#{w.name}, #{w.message}" }.join("; ")
          if defined?(Master::Trace::Dmesg)
            Master::Trace::Dmesg.status("boot0", "#{warnings.size} warning(s), #{detail}")
          else
            warn "boot0: #{warnings.size} warning(s), #{detail}"
          end
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
          return fail("config_valid", errors.join("; "), severity: :fatal) unless errors.empty?

          ok("config_valid", "all config values within bounds")
        rescue StandardError => e
          fail("config_valid", "validation error: #{e.message}")
        end

        def check_data_dir(root)
          dir = File.join(root, "data")
          return fail("data_dir", "missing data/ directory") unless File.directory?(dir)

          required = %w[soul.yml laws.yml console.yml scan.yml budgets.yml]
          missing = required.reject { |f| File.exist?(File.join(dir, f)) }
          return fail("data_dir", "missing required: #{missing.join(", ")}") unless missing.empty?

          ok("data_dir", "required law files present")
        end

        def check_soul_yaml(root)
          check_yaml_file(root, "data/soul.yml", "soul_yaml")
        end

        def check_laws_yaml(root)
          check_yaml_file(root, "data/laws.yml", "laws_yaml")
        end

        def check_tokens_yaml(root)
          check_catalogue_yaml(root, "data/tokens.yml", "tokens_yaml")
        end

        def check_providers_yaml(root)
          check_catalogue_yaml(root, "data/providers.yml", "providers_yaml")
        end

        def check_models_yaml(root)
          check_catalogue_yaml(root, "data/models.yml", "models_yaml")
        end

        def check_dynamic_tools_yaml(root)
          master_root = Master.master_root(root:)
          path = File.join(master_root, "data", "tools.dynamic.yml")
          return ok("dynamic_tools_yaml", "optional file absent") unless File.file?(path)

          Master::Io::DynamicTools.validate_source(File.read(path, encoding: "UTF-8"), path:)
          # The canonical runtime also reads ~/.master/tools.dynamic.yml. Load the
          # combined registry here so duplicate names across either source fail
          # before the runtime silently chooses one.
          Master::Io::DynamicTools.load_definitions if File.expand_path(master_root) == File.expand_path(Master::ROOT)
          ok("dynamic_tools_yaml", "dynamic tool catalogue schema valid")
        rescue StandardError => error
          fail("dynamic_tools_yaml", "dynamic tool catalogue invalid: #{error.class}: #{error.message}")
        end

        # Real MASTER needs both routing catalogues. Isolated test/workspace roots
        # may omit them, but a missing catalogue in the canonical installation must
        # never become an empty routing table.
        def check_catalogue_yaml(root, relative_path, name)
          required = File.expand_path(root) == File.expand_path(Master::ROOT)
          basic = check_yaml_file(root, relative_path, name, required:)
          return basic unless basic.ok
          path = File.join(root, relative_path)
          return basic unless File.file?(path)

          reason = Master::ConfigurationGuard.validate(path:, content: File.read(path, encoding: "UTF-8"), root:)
          return fail(name, reason) if reason

          ok(name, "#{relative_path} schema and references valid")
        rescue StandardError => error
          fail(name, "#{relative_path} validation error: #{error.class}: #{error.message}")
        end

        def check_voice_yaml(root)
          check_yaml_file(root, "data/voice.yml", "voice_yaml", required: false)
        end

        # console.yml, scan.yml and budgets.yml, which data/limits.yml held until 2026-10-31.
        def check_config_sections_yaml(root)
          %w[console scan budgets].map { |name| check_catalogue_yaml(root, "data/#{name}.yml", "#{name}_yaml") }
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
          dir = File.expand_path("../RAILS/master", root)
          return ok("web_dir", "no web face — OK for headless") unless File.directory?(dir)

          gemfile = File.join(dir, "Gemfile")
          if File.exist?(gemfile)
            ok("web_dir", "web face with Gemfile detected")
          else
            warn_check("web_dir", "RAILS/master exists but no Gemfile — may be incomplete")
          end
        end
      end
    end
  end
end
