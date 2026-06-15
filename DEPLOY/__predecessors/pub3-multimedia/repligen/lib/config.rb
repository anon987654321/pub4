#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"

module Repligen
  class Config

    CONFIG_PATH = File.expand_path("~/.config/repligen/config.json")

    def self.load
      return ENV["REPLICATE_API_TOKEN"] if ENV["REPLICATE_API_TOKEN"]

      return load_from_file if File.exist?(CONFIG_PATH)

      fail_with_instructions
    end

    def self.save(token)
      FileUtils.mkdir_p(File.dirname(CONFIG_PATH))

      File.write(CONFIG_PATH, JSON.pretty_generate({ api_token: token }))

      File.chmod(0600, CONFIG_PATH)

    end

    private
    def self.load_from_file
      token = JSON.parse(File.read(CONFIG_PATH))["api_token"]

      return token if token

      fail_with_instructions

    end

    def self.fail_with_instructions
      abort <<~MSG

        Missing REPLICATE_API_TOKEN

        Get your token: https://replicate.com/account/api-tokens
        Then either:
          export REPLICATE_API_TOKEN=r8_...

        Or:

          echo '{"api_token":"r8_..."}' > #{CONFIG_PATH}

          chmod 600 #{CONFIG_PATH}

      MSG

    end

  end

end

