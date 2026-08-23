# frozen_string_literal: true

# Which top-level keys in data/*.yml does anything actually read?
#
# The dominant defect class in this repo is the declaration with no reader:
# media_providers claimed a media routing that never existed, soul negotiable
# carried a default_model nothing consulted, law/rails.rb declared a language
# no map produces. Each was found by hand, months apart. This is the census
# that finds them by count.
#
#   ruby MASTER/tools/data_reach.rb            # list unnamed keys
#   ruby MASTER/tools/data_reach.rb --ratchet  # record a new low
#
# A key is NAMED when its literal appears in code outside data/ — string,
# symbol or dig argument. A named key can still be dead (the name may appear
# in a comment) and an unnamed key can still be read (a file iterated
# generically never names its keys), so this is a census with a ceiling, not
# a verdict: the ceiling exists so the NEXT unread declaration cannot arrive
# silently, which is how all three above did.

require "yaml"

module Pub4
  module DataReach
    ROOT = File.expand_path("..", __dir__)
    CEILING = File.join(ROOT, "data", "data_reach.yml")

    CODE_GLOBS = %w[lib/**/*.rb core/**/*.rb web/app/**/*.rb web/config/**/*.rb
                    bin/* tools/**/*.rb test/**/*.rb spec/**/*.rb law/*.rb Rakefile].freeze

    module_function

    def code
      @code ||= Dir.glob(CODE_GLOBS.map { |g| File.join(ROOT, g) })
                   .select { |f| File.file?(f) }
                   .map { |f| File.read(f) }.join
    end

    def unnamed
      Dir.glob(File.join(ROOT, "data", "*.yml")).sort.flat_map do |path|
        doc = begin
          YAML.safe_load_file(path, aliases: true)
        rescue StandardError
          nil
        end
        next [] unless doc.is_a?(Hash)

        doc.keys.filter_map do |key|
          "#{File.basename(path)}##{key}" unless code.match?(/["':]#{Regexp.escape(key.to_s)}\b/)
        end
      end
    end

    def ceiling
      File.exist?(CEILING) ? YAML.safe_load_file(CEILING).fetch("unnamed", 0) : 0
    end

    def run(ratchet: false)
      out = unnamed
      puts "data_reach: #{out.size} top-level keys no code names (ceiling #{ceiling})"
      if ratchet && out.size < ceiling
        File.write(CEILING, { "unnamed" => out.size }.to_yaml)
        puts "data_reach: recorded #{out.size} as the new low"
        return 0
      end
      return 0 unless out.size > ceiling

      # All of them, not the first 15. A census that names a third of what it
      # counted leaves the rest invisible: this printed 15 of 55, so the forty
      # it did not name could not be acted on and a +1 could not be attributed
      # to any change. Silent truncation reads as "that is all of them", which
      # is the one thing it must not say.
      out.each { |k| puts "  #{k} — no code names this key; wire a reader or delete the block" }
      1
    end
  end
end

exit Pub4::DataReach.run(ratchet: ARGV.include?("--ratchet")) if $PROGRAM_NAME == __FILE__
