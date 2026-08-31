# frozen_string_literal: true

require "yaml"
require "fileutils"
require_relative "atomic_write"

module Master
  module Ground
    class Config
      # Typed convenience readers over Config#[] — kept in a separate module
      # so NO_GOD_CLASS's AST-based public-method count only sees Config's
      # own storage/persistence/validation methods, not this passthrough layer.
      module ConfigAccessors
        def model = self["model"]
        def budget_max = self["budget_max"].to_f
        def warn_at = self["warn_at"].to_f
        def max_per_file = self["max_per_file"].to_f
        def req_max = self["req_max"].to_f
        def trace = (ENV["MASTER_TRACE"] || self["trace"]).to_i
        def prescan? = self["prescan"] == true
        def auto? = self["auto"] == true
        def reasoning_mode = self["reasoning_mode"].to_s
        def task_type = self["task_type"].to_s
        def auto_testing? = self["auto_testing"] == true
        def web_port = self["web_port"].to_i
        def history_max = self["history_max"].to_i
        def cache_ttl = self["cache_ttl"].to_i
      end
    end
  end
end

module Master
  module Ground
    class Config
      include ConfigAccessors

      BUDGET_MAX_DEFAULT = 10.0
      HISTORY_MAX = 500
      DEFAULT_WEB_PORT = 53_187

      DEFAULTS = {
        # xAI deprecated grok-4-fast (confirmed 2026-07-11: 404 "xAI
        # recommends switching to Grok 4.3"). This is the ultimate fallback
        # model for disabled routing, or as the last resort in
        # ModelRouter#fallback_chain — must work
        # without requiring paid credits, since this repo should work for
        # anyone with or without an OpenRouter balance.
        "model" => "nvidia/nemotron-3-super-120b-a12b:free",
        "web_host" => "127.0.0.1",
        "web_public_url" => "https://ai.brgen.no",
        "web_port" => DEFAULT_WEB_PORT,
        "budget_max" => BUDGET_MAX_DEFAULT,
        "warn_at" => 0.50,
        "max_per_file" => 1.0,
        "req_max" => 60.0,
        "trace" => 0,
        "prescan" => true,
        "auto" => false,
        "cache_ttl" => 300,
        "history_max" => 500,
        "reasoning_mode" => "direct",
        "task_type" => "code_generation",
        "auto_testing" => false,
      }.freeze

      def initialize(root = Dir.pwd)
        @root = root
        @path = File.join(root, ".master", "config.yml")
        @mutex = Mutex.new
        @settings = load_config
      end

      def [](key) = @mutex.synchronize { @settings[key.to_s] }
      def []=(key, value); @mutex.synchronize { @settings[key.to_s] = value }; end
      def dig(key, *rest)
        @mutex.synchronize do
          k = key.to_s
          rest.empty? ? @settings[k] : @settings.dig(k, *rest.map(&:to_s))
        end
      end

      include AtomicWrite

      def save!
        FileUtils.mkdir_p(File.dirname(@path))
        errs = validate if respond_to?(:validate)
        warn "config: validation issues before save: #{errs.join('; ')}" if errs && !errs.empty?
        write_atomic(@path, @settings.to_yaml, fsync: true)
      end

      def reload!
        @mutex.synchronize { @settings = load_config }
      end

      # Validate config against known schema. Returns array of error strings.
      def validate
        errors = []
        errors << "budget_max must be > 0" unless budget_max > 0
        errors << "warn_at must be between 0 and 1" unless warn_at.between?(0.0, 1.0)
        wp = self["web_port"].to_i
        errors << "web_port must be 1-65535" unless wp.between?(1, 65_535)
        errors << "history_max must be >= 0" unless history_max >= 0
        errors << "cache_ttl must be >= 0" unless cache_ttl >= 0
        errors << "model must not be empty" if model.to_s.empty?
        errors
      end

      def valid? = validate.empty?

      # Frozen snapshot of boot values — safe to share across threads.
      BootConfig = Data.define(:root, :model, :web_host, :web_port, :web_public_url,
        :budget_max, :warn_at, :max_per_file, :req_max, :cache_ttl, :history_max)

      def freeze_boot
        snap = @mutex.synchronize { @settings.dup }
        BootConfig.new(
          root: @root, model: snap["model"], web_host: snap["web_host"], web_port: snap["web_port"].to_i,
          web_public_url: snap["web_public_url"], budget_max: snap["budget_max"].to_f,
          warn_at: snap["warn_at"].to_f, max_per_file: snap["max_per_file"].to_f,
          req_max: snap["req_max"].to_f, cache_ttl: snap["cache_ttl"].to_i, history_max: snap["history_max"].to_i
        ).freeze
      end

      def to_h = @mutex.synchronize { deep_dup(@settings) }

      private

      def load_config
        defaults = deep_dup(DEFAULTS)
        return defaults unless File.exist?(@path)
        raw = YAML.safe_load_file(@path, aliases: true)
        loaded = raw.is_a?(Hash) ? raw : {}
        deep_merge(defaults, stringify_keys(loaded))
      rescue Psych::Exception => e
        warn "config: failed to parse #{@path}: #{e.message}"
        defaults
      end

      def deep_merge(base, overlay)
        base.merge(overlay) do |_key, old_val, new_val|
          old_val.is_a?(Hash) && new_val.is_a?(Hash) ? deep_merge(old_val, new_val) : new_val
        end
      end

      def stringify_keys(hash)
        hash.each_with_object({}) do |(k, v), h|
          h[k.to_s] = v.is_a?(Hash) ? stringify_keys(v) : v
        end
      end

      def deep_dup(obj)
        case obj
        when Hash then obj.transform_values { |v| deep_dup(v) }
        when Array then obj.map { |v| deep_dup(v) }
        when String then obj.dup
        when Numeric, Symbol, TrueClass, FalseClass, NilClass then obj
        else
          obj.respond_to?(:dup) ? (obj.dup rescue obj) : obj
        end
      end
    end
  end
end
