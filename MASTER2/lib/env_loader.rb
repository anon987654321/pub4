# encoding: utf-8
# EnvLoader: load env vars from ~/.zshrc exports without spawning a shell.
# Usage: MASTER::EnvLoader.ensure!
# Reads lines matching /^export KEY="VALUE"/ and sets them in ENV if not already set.
module MASTER
  module EnvLoader
    ZSHRC = File.expand_path("~/.zshrc").freeze
    EXPORT_RE = /Aexport +([A-Z0-9_]+)=["']?([^"'
]*)["']?z/.freeze

    def self.ensure!(path: ZSHRC)
      return unless File.exist?(path)

      loaded = 0
      File.foreach(path, encoding: "utf-8") do |line|
        m = line.chomp.match(EXPORT_RE)
        next unless m
        key, val = m[1], m[2]
        next if ENV.key?(key) && !ENV[key].empty?
        ENV[key] = val
        loaded += 1
      end
      loaded
    rescue StandardError
      0
    end
  end
end
