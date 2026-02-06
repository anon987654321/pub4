# frozen_string_literal: true

require 'json'

module MASTER
  module Protocol
    def self.pipe
      input = JSON.parse($stdin.read, symbolize_names: true)
      result = yield(input)
      $stdout.puts JSON.generate(result)
    rescue => e
      $stdout.puts JSON.generate({ error: e.message, backtrace: e.backtrace.first(3) })
      exit 1
    end
  end
end
