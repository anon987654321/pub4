# frozen_string_literal: true

require "json"
require "prism"
require "psych"

module Master
  module Fix
    class Restructure
      # Whether a written file still parses, by what it is: Ruby by Prism, a
      # shell script by its own shell's -n, JavaScript by node --check, YAML and
      # JSON by their parsers. A file of no kind it knows passes; the tests
      # stand behind it.
      module Syntax
        SHELLS = %w[sh zsh bash ksh].freeze

        def self.valid?(path)
          case kind(path)
          when :ruby then !Prism.parse_file(path).failure?
          when :shell then command_ok?(shell(path), "-n", path)
          when :javascript then command_ok?("node", "--check", path)
          when :yaml then parses? { Psych.parse(File.read(path)) }
          when :json then parses? { JSON.parse(File.read(path)) }
          else true
          end
        end

        def self.kind(path)
          ext = File.extname(path)
          return :ruby if %w[.rb .rake .ru].include?(ext) || %w[Rakefile Gemfile].include?(File.basename(path))
          return { ".sh" => :shell, ".js" => :javascript, ".mjs" => :javascript, ".yml" => :yaml,
                   ".yaml" => :yaml, ".json" => :json }[ext] unless ext.empty?

          interpreter = File.open(path, &:gets).to_s[%r{\A#!.*?/(?:env\s+)?(\w+)}, 1]
          return :ruby if interpreter == "ruby"

          :shell if SHELLS.include?(interpreter)
        rescue SystemCallError
          nil
        end

        def self.shell(path)
          named = File.open(path, &:gets).to_s[%r{\A#!.*?/(?:env\s+)?(\w+)}, 1]
          SHELLS.include?(named) ? named : "sh"
        end

        def self.command_ok?(*command)
          _, status = Master::Io::Exec.capture2e(*command)
          status.success?
        end

        def self.parses?
          yield
          true
        rescue Psych::SyntaxError, JSON::ParserError
          false
        end
      end
    end
  end
end
