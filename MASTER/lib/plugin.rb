# frozen_string_literal: true

require "yaml"

module Master
  module Plugin
    VERSION = 1
    Manifest = Data.define(:id, :version, :description, :entrypoint, :path)

    class Error < StandardError; end
    class ManifestError < Error; end
    class PolicyError < Error; end

    module_function

    def root = File.join(Master::ROOT, "plugins")

    def external_roots
      return [] unless ENV["MASTER_ALLOW_EXTERNAL_PLUGINS"] == "1"

      ENV.fetch("MASTER_PLUGIN_PATHS", "").split(File::PATH_SEPARATOR).filter_map do |path|
        expanded = File.expand_path(path)
        expanded if Dir.exist?(expanded)
      end
    end

    def manifest_paths
      ([root] + external_roots).flat_map do |dir|
        Dir.glob(File.join(dir, "*", "plugin.yml"))
      end.uniq.sort
    end

    def list = manifest_paths.map { |path| load_manifest(path) }

    def info(id) = load(id).manifest

    def load(id)
      manifest = find_manifest(id.to_s)
      enforce_external_policy!(manifest.path)
      require_entrypoint!(manifest)
      policy(manifest.id)

      constant = plugin_constant(manifest.id)
      klass = constant.split("::").reduce(Object) { |scope, name| scope.const_get(name) }
      unless klass <= Base
        raise ManifestError, "#{manifest.id}: #{constant} must inherit Master::Plugin::Base"
      end

      klass.new(manifest:)
    rescue NameError => e
      raise ManifestError, "#{id}: #{e.message}"
    end

    def run(id, action:, **args)
      Ground::LawHandshake::Admission.require!
      load(id).call(action:, **args)
    end

    def policy(id)
      Master.law("plugins").fetch(id.to_s) do
        raise PolicyError, "data/rules.yml has no plugin policy for #{id}"
      end
    end

    def find_manifest(id)
      path = manifest_paths.find { |candidate| File.basename(File.dirname(candidate)) == id }
      raise ManifestError, "unknown plugin #{id}" unless path

      load_manifest(path)
    end

    def load_manifest(path)
      raw = YAML.safe_load_file(path)
      validate_manifest!(raw, path)
      Manifest.new(
        id: raw.fetch("id").to_s,
        version: raw.fetch("version").to_s,
        description: raw.fetch("description").to_s.strip,
        entrypoint: raw.fetch("entrypoint").to_s,
        path: File.expand_path(path)
      )
    rescue Psych::Exception => e
      raise ManifestError, "#{path}: invalid YAML: #{e.message}"
    end

    def validate_manifest!(raw, path)
      raise ManifestError, "#{path}: manifest must be a mapping" unless raw.is_a?(Hash)

      required = %w[id version description entrypoint]
      missing = required.reject { |key| raw.key?(key) }
      raise ManifestError, "#{path}: missing #{missing.join(", ")}" unless missing.empty?

      id = raw.fetch("id").to_s
      version = raw.fetch("version").to_s
      entrypoint = raw.fetch("entrypoint").to_s
      directory = File.basename(File.dirname(path))

      unless directory == id
        raise ManifestError, "#{path}: id #{id.inspect} does not match directory #{directory.inspect}"
      end
      raise ManifestError, "#{path}: invalid id" unless id.match?(/\A[a-z][a-z0-9_]*\z/)
      raise ManifestError, "#{path}: invalid version" unless version.match?(/\A\d+\.\d+\.\d+\z/)
      raise ManifestError, "#{path}: description is empty" if raw.fetch("description").to_s.strip.empty?
      raise ManifestError, "#{path}: invalid entrypoint" unless entrypoint.match?(/\A[a-z0-9_]+\.rb\z/)
    end

    def require_entrypoint!(manifest)
      path = File.expand_path(manifest.entrypoint, File.dirname(manifest.path))
      root_dir = File.dirname(manifest.path)
      unless path.start_with?("#{root_dir}#{File::SEPARATOR}") && File.file?(path)
        raise ManifestError, "#{manifest.id}: entrypoint not found: #{manifest.entrypoint}"
      end

      require path
    end

    def enforce_external_policy!(path)
      return if path.start_with?("#{File.expand_path(root)}#{File::SEPARATOR}")
      return if ENV["MASTER_ALLOW_EXTERNAL_PLUGINS"] == "1"

      raise PolicyError, "external plugins are disabled; set MASTER_ALLOW_EXTERNAL_PLUGINS=1 explicitly"
    end

    def plugin_constant(id)
      "Master::Plugins::#{id.split("_").map { |part| part.capitalize }.join}"
    end
  end
end
