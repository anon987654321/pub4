# frozen_string_literal: true

require "yaml"

module Master3
  class Config
    DEFAULTS = {
      "model"       => "meta-llama/llama-3.3-70b-instruct:free",
      "budget_max"  => 10.0,
      "req_max"     => 1.0,
      "trace"       => 0,
      "prescan"     => true,
      "auto"        => false,
      "cache_ttl"   => 3600,
      "history_max" => 500,
      "reasoning_mode" => "direct",
      "task_type" => "exploration",
      "auto_testing" => false
    }.freeze

    attr_reader :data

    def initialize(root = Dir.pwd)
      @root = root
      @path = File.join(root, ".master3", "config.yml")
      @data = load_config
    end

    def [](key)
      @data[key.to_s]
    end

    def []=(key, v)
      @data[key.to_s] = v
    end

    def model      = self["model"]
    def budget_max = self["budget_max"].to_f
    def req_max    = self["req_max"].to_f
    def trace      = (ENV["MASTER_TRACE"] || self["trace"]).to_i
    def prescan?   = self["prescan"] != false
    def auto?      = self["auto"] == true
    def reasoning_mode = self["reasoning_mode"].to_s
    def task_type = self["task_type"].to_s
    def auto_testing? = self["auto_testing"] == true

    def save!
      dir = File.dirname(@path)
      Dir.mkdir(dir) unless Dir.exist?(dir)
      File.write(@path, @data.to_yaml)
    end

    private

    def load_config
      base = DEFAULTS.dup
      if File.exist?(@path)
        loaded = YAML.safe_load_file(@path) || {}
        base.merge!(loaded)
      end
      base
    end
  end
end
