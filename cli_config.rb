#!/usr/bin/env ruby
# frozen_string_literal: true

# CONVERGENCE CLI - Configuration Management
# Handles persistence to ~/.convergence/config.yml

require "yaml"
require "fileutils"

module Convergence
  class Config
    CONFIG_DIR = File.expand_path("~/.convergence").freeze
    CONFIG_PATH = File.join(CONFIG_DIR, "config.yml").freeze

    attr_accessor :mode, :provider, :api_keys, :model, :preferences

    def self.load
      new.tap(&:load!)
    end

    def initialize
      @mode = nil
      @provider = nil
      @api_keys = {}
      @model = nil
      @preferences = {
        headless: true,
        auto_rotate: true
      }
    end

    def load!
      return self unless File.exist?(CONFIG_PATH)
      
      data = YAML.safe_load_file(CONFIG_PATH, permitted_classes: [Symbol], aliases: false)
      return self unless data.is_a?(Hash)
      
      @mode = data["mode"]&.to_sym if data["mode"]
      @provider = data["provider"]&.to_sym if data["provider"]
      @api_keys = data["api_keys"] || {}
      @model = data["model"]
      @preferences = (@preferences || {}).merge(data["preferences"] || {})
      
      self
    rescue => e
      warn "Warning: Failed to load config: #{e.message}"
      self
    end

    def save
      FileUtils.mkdir_p(CONFIG_DIR)
      
      data = {
        "mode" => @mode.to_s,
        "provider" => @provider.to_s,
        "api_keys" => @api_keys,
        "model" => @model,
        "preferences" => @preferences
      }
      
      File.write(CONFIG_PATH, YAML.dump(data))
      
      # Set secure permissions (user read/write only)
      File.chmod(0600, CONFIG_PATH)
      
      true
    rescue => e
      warn "Warning: Failed to save config: #{e.message}"
      false
    end

    def reset
      File.delete(CONFIG_PATH) if File.exist?(CONFIG_PATH)
      initialize
      true
    rescue => e
      warn "Warning: Failed to reset config: #{e.message}"
      false
    end

    def configured?
      !@mode.nil? && !@provider.nil?
    end

    def api_key_for(provider)
      @api_keys[provider.to_s]
    end

    def set_api_key(provider, key)
      @api_keys[provider.to_s] = key
    end

    def to_h
      {
        mode: @mode,
        provider: @provider,
        model: @model,
        has_api_keys: @api_keys.keys,
        preferences: @preferences
      }
    end
  end
end
