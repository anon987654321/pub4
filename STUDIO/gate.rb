#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "rbconfig"
require "timeout"

module Studio
  class Gate
    ROOT = File.expand_path(__dir__)
    VENDORED = %r{/(?:.git|node_modules|tmp|.cache|storage|output|renders|samples|weights)/}
    FILES = -> { Dir.glob(File.join(ROOT, "**", "*.rb")).reject { |path| "/#{path.delete_prefix(ROOT + "/")}" =~ VENDORED }.sort }
    ENTRYPOINTS = %w[postpro/postpro.rb replicate/replicate.rb photograph.rb].freeze
    # A script, not a library: dilla.rb is a command that runs when it is loaded, so
    # it has to exist and parse, and it carries no PROGRAM_NAME guard to look for.
    SCRIPTS = %w[dilla/dilla.rb].freeze
    FORBIDDEN = %r{require(?:_relative)?\s+["'][^"']*(?:MASTER|RAILS|OPENBSD)/(?:lib|app|tools|shared|engines)[^"']*["']}

    def self.run = new.run

    def initialize
      @failures = []
      @checked = 0
    end

    def run
      files = FILES.call
      return result("no Ruby source under STUDIO") if files.empty?

      files.each { |path| parse(path) }
      files.each { |path| boundary(path) }
      SCRIPTS.each { |entry| @failures << "missing script #{entry}" unless File.file?(File.join(ROOT, entry)) }
      ENTRYPOINTS.each { |entry| guarded(entry) }
      result
    end

    private

    def parse(path)
      RubyVM::AbstractSyntaxTree.parse_file(path)
      @checked += 1
    rescue SyntaxError => e
      @failures << "#{relative(path)}: syntax error: #{e.message.lines.first.to_s.strip}"
    end

    def boundary(path)
      File.foreach(path).with_index(1) do |line, number|
        next if line.lstrip.start_with?("#")

        @failures << "#{relative(path)}:#{number}: sibling implementation require" if line.match?(FORBIDDEN)
      end
      @checked += 1
    end

    def guarded(entry)
      path = File.join(ROOT, entry)
      unless File.file?(path)
        @failures << "missing entrypoint #{entry}"
        return
      end

      return if File.read(path).match?(/\$(?:PROGRAM_NAME|0)\s*==\s*__FILE__|__FILE__\s*==\s*\$(?:PROGRAM_NAME|0)/)

      @failures << "#{entry}: CLI runs at load; add a PROGRAM_NAME guard"
    end

    def result(error = nil)
      @failures << error if error
      @checked += 1 if error.nil?
      puts "studio0: #{@failures.empty? ? "#{@checked} checks passed" : "#{@failures.size} failures"}"
      @failures.each { |failure| warn "  - #{failure}" }
      Kernel.exit(@failures.empty? ? 0 : 1) if $PROGRAM_NAME == __FILE__
      self
    end

    def relative(path) = path.delete_prefix(ROOT + "/")
  end
end

Studio::Gate.run if $PROGRAM_NAME == __FILE__
