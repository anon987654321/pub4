# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module Master
  class Config
    DEFAULTS = {
      'model'          => 'meta-llama/llama-3.3-70b-instruct:free',
      'web_host'       => '0.0.0.0',
      'web_public_url' => 'http://ai.brgen.no:3000',
      'web_port'       => 10_002,
      'budget_max'     => 10.0,
      'req_max'        => 1.0,
      'trace'          => 0,
      'prescan'        => true,
      'auto'           => false,
      'cache_ttl'      => 3_600,
      'history_max'    => 500,
      'reasoning_mode' => 'direct',
      'task_type'      => 'code_generation',
      'auto_testing'   => false
    }.freeze

    attr_reader :data

    def initialize(root = Dir.pwd)
      @root = root
      @path = File.join(root, '.master', 'config.yml')
      @data = load_config
    end

    # Hash‑style access
    def [](key)         = @data[key.to_s]
    def []=(key, value) ; @data[key.to_s] = value ; end

    # Typed helpers
    def model          = self['model']
    def budget_max     = self['budget_max'].to_f
    def req_max        = self['req_max'].to_f
    def trace          = (ENV['MASTER_TRACE'] || self['trace']).to_i
    def prescan?       = !!self['prescan']
    def auto?          = !!self['auto']
    def reasoning_mode = self['reasoning_mode'].to_s
    def task_type      = self['task_type'].to_s
    def auto_testing?  = !!self['auto_testing']

    # Persist atomically; fsync ensures durability.
    def save!
      dir = File.dirname(@path)
      FileUtils.mkdir_p(dir)

      tmp = "#{@path}.tmp.#{Process.pid}"
      File.open(tmp, 'w') do |f|
        f.write(@data.to_yaml)
        f.flush
        f.fsync
      end
      File.rename(tmp, @path)
    ensure
      File.delete(tmp) if defined?(tmp) && File.exist?(tmp) rescue nil
    end

    # Reload from disk, preserving unknown keys.
    def reload!
      @data = load_config
    end

    # Export as plain hash (deep dup to avoid external mutation)
    def to_h = Marshal.load(Marshal.dump(@data))

    private

    def load_config
      return deep_dup(DEFAULTS) unless File.exist?(@path)

      loaded = YAML.safe_load_file(@path) || {}
      deep_merge(DEFAULTS, stringify_keys(loaded))
    rescue Psych::Exception => e
      warn "config: failed to parse #{@path}: #{e.message}"
      deep_dup(DEFAULTS)
    end

    # Recursive merge where +b+ overrides +a+.
    def deep_merge(a, b)
      a.merge(b) do |_key, old_val, new_val|
        old_val.is_a?(Hash) && new_val.is_a?(Hash) ? deep_merge(old_val, new_val) : new_val
      end
    end

    def stringify_keys(hash)
      hash.each_with_object({}) do |(k, v), h|
        h[k.to_s] = v.is_a?(Hash) ? stringify_keys(v) : v
      end
    end

    def deep_dup(hash)
      Marshal.load(Marshal.dump(hash))
    end
  end
end