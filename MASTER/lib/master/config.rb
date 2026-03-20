# frozen_string_literal: true

require 'yaml'

module Master
  class Config
    DEFAULTS = {
      'model'          => 'meta-llama/llama-3.3-70b-instruct:free',
      'budget_max'     => 10.0,
      'req_max'        => 1.0,
      'trace'          => 0,
      'prescan'        => true,
      'auto'           => false,
      'cache_ttl'      => 3600,
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

    def [](key)         = @data[key.to_s]
    def []=(key, value) = (@data[key.to_s] = value)

    def model          = self['model']
    def budget_max     = self['budget_max'].to_f
    def req_max        = self['req_max'].to_f
    def trace          = (ENV['MASTER_TRACE'] || self['trace']).to_i
    def prescan?       = self['prescan'] != false
    def auto?          = self['auto'] == true
    def reasoning_mode = self['reasoning_mode'].to_s
    def task_type      = self['task_type'].to_s
    def auto_testing?  = self['auto_testing'] == true

    # Atomic write: write to a temp file then rename to avoid partial reads.
    def save!
      dir = File.dirname(@path)
      Dir.mkdir(dir) unless Dir.exist?(dir)
      tmp = "#{@path}.tmp.#{Process.pid}"
      File.write(tmp, @data.to_yaml)
      File.rename(tmp, @path)
    ensure
      File.delete(tmp) if defined?(tmp) && tmp && File.exist?(tmp) rescue nil
    end

    private

    def load_config
      return DEFAULTS.dup unless File.exist?(@path)

      loaded = YAML.safe_load_file(@path) || {}
      DEFAULTS.merge(loaded)
    rescue Psych::Exception => e
      warn "config: failed to parse #{@path}: #{e.message}"
      DEFAULTS.dup
    end
  end
end
