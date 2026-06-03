# frozen_string_literal: true

require "yaml"
require "fileutils"

module Master
  module Ground
    class Config
      BUDGET_MAX_DEFAULT = 10.0
      HISTORY_MAX = 500
      DEFAULT_WEB_PORT = 53_187

      DEFAULTS = {
        "model" => "google/gemini-2.5-flash",
        "web_host" => "127.0.0.1",
        "web_public_url" => "https://ai.brgen.no",
        "web_port" => DEFAULT_WEB_PORT,
        "budget_max" => BUDGET_MAX_DEFAULT,
        "req_max" => 60.0,
        "trace" => 0,
        "prescan" => true,
        "auto" => false,
        "cache_ttl" => 3_600,
        "history_max" => 500,
        "reasoning_mode" => "direct",
        "task_type" => "code_generation",
        "auto_testing" => false
      }.freeze

      def initialize(root = Dir.pwd)
        @root = root
        @path = File.join(root, ".master", "config.yml")
        @mutex = Mutex.new
        @data = load_config
      end

      def [](key) = @mutex.synchronize { @data[key.to_s] }
      def []=(key, value); @mutex.synchronize { @data[key.to_s] = value }; end
      def dig(key, *rest)
        @mutex.synchronize { k = key.to_s; rest.empty? ? @data[k] : @data.dig(k, *rest) }
      end

      def model = self["model"]
      def budget_max = self["budget_max"].to_f
      def req_max = self["req_max"].to_f
      def trace = (ENV["MASTER_TRACE"] || self["trace"]).to_i
      def prescan? = self["prescan"] == true
      def auto? = self["auto"] == true
      def reasoning_mode = self["reasoning_mode"].to_s
      def task_type = self["task_type"].to_s
      def auto_testing? = self["auto_testing"] == true

      include AtomicWrite

      def save!
        FileUtils.mkdir_p(File.dirname(@path))
        write_atomic(@path, @data.to_yaml, fsync: true)
      end

      def reload!
        @mutex.synchronize { @data = load_config }
      end

      # Frozen snapshot of boot values — safe to share across threads.
      BootConfig = Data.define(:root, :model, :web_host, :web_port, :web_public_url,
        :budget_max, :req_max, :cache_ttl, :history_max)

      def freeze_boot
        snap = @mutex.synchronize { @data.dup }
        BootConfig.new(
          root: @root, model: snap["model"], web_host: snap["web_host"], web_port: snap["web_port"].to_i,
          web_public_url: snap["web_public_url"], budget_max: snap["budget_max"].to_f,
          req_max: snap["req_max"].to_f, cache_ttl: snap["cache_ttl"].to_i, history_max: snap["history_max"].to_i
        ).freeze
      end

      def to_h = @mutex.synchronize { deep_dup(@data) }

      private

      def load_config
        defaults = deep_dup(DEFAULTS)
        return defaults unless File.exist?(@path)
        raw = Master.load_yaml(@path)
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
        when Hash then obj.each_with_object({}) { |(k, v), h| h[k] = deep_dup(v) }
        when Array then obj.map { |v| deep_dup(v) }
        when Numeric, Symbol, TrueClass, FalseClass, NilClass then obj
        else
          obj.respond_to?(:dup) ? (obj.dup rescue obj) : obj
        end
      end
    end
  end
end
