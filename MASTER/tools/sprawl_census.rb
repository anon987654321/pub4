# frozen_string_literal: true

# Shape census over every tracked file in all four trees. The tree's shape is
# conduct: a directory bought for one file, a name that repeats its parent, a
# name that says nothing, and a path deeper than its neighbours all cost a
# reader something. FILE_SPRAWL in the scan registry measures the first two for
# MASTER's .rb files only, and skips law/, core/, test/ and spec/ besides. This
# is the same law over the whole repo and every file type.
#
#   ruby MASTER/tools/sprawl_census.rb            # counts against the ceilings
#   ruby MASTER/tools/sprawl_census.rb --list     # what was counted, per kind
#   ruby MASTER/tools/sprawl_census.rb --ratchet  # record a new low
#
# Mandated paths are excluded rather than priced, because they can never fall:
# Zeitwerk resolves a constant FROM its path, so engines/dating/app/services/
# dating/ is the depth Rails requires and lib/io/base.rb is named after the
# constant it defines. Everything else is counted, the way dup_census counts the
# per-app error pages it cannot collapse -- the ceiling prices what is here, and
# the next one that arrives is a +1 nobody has to notice by hand.
#
# The uncalibrated version of this file called 130 RAILS paths too deep and 26
# names vague. Both were the rule misreading correct markup, which is the same
# way 596 of 981 design findings died. Check a class against a real file before
# adding it.

require "yaml"

module Pub4
  module SprawlCensus
    ROOT = File.expand_path("../..", __dir__)
    CEILINGS = File.join(ROOT, "MASTER", "data", "sprawl_census.yml")

    MANDATED = [
      # Zeitwerk reads the namespace off the path, so the nesting IS the name.
      %r{/engines/[^/]+/(?:app|test)/[^/]+/[^/]+/},
      %r{/engines/[^/]+/lib/[^/]+/(?:engine|version)\.rb\z},
      # Rails loads these by location, not by reference.
      %r{/db/(?:migrate|[a-z]+_migrate)/},
      %r{/config/(?:environments|initializers|locales)/},
      %r{/app/(?:channels|controllers|helpers|jobs|mailers|models|reflexes|views|javascript|assets|services|policies|serializers)/},
      %r{/(?:bin|lib/tasks|public|storage|log|vendor|node_modules|knowledge|output)/},
      # The locale code and the daemon's config name are not ours to choose.
      %r{/locales/[a-z]{2}(?:-[A-Z]{2})?\.yml\z},
      %r{\.(?:conf|lock|sample|keep|gitkeep|woff2|png|ico|onnx)\z},
    ].freeze

    # A name that says nothing on its own, in a stack trace or a diff.
    VAGUE = %w[base common shared misc util utils helper helpers main data
               stuff extras things new old temp tmp code lib].freeze

    module_function

    def tracked
      @tracked ||= `git -C #{ROOT} ls-files -z`.split("\0")
                   .reject { |f| MANDATED.any? { |re| "/#{f}".match?(re) } }
                   .select { |f| File.file?(File.join(ROOT, f)) }
    end

    # A directory holding one file and no subdirectories is a namespace bought
    # for nothing.
    def lone_dirs
      tracked.group_by { |f| File.dirname(f) }
             .select { |dir, files| files.size == 1 && dir != "." && Dir.glob(File.join(ROOT, dir, "*/")).empty? }
             .values.flatten.sort
    end

    # dilla/dilla.rb is the tool named after its folder and reads correctly at
    # the command line. cli/cli.rb is Master::CLI::CLI, which says it three
    # times. The entry point is the one that is also executable or is required
    # by name from outside its own directory.
    def stutter
      tracked.select do |f|
        parts = f.split("/")
        next false unless parts.size >= 2
        next false unless File.basename(f, File.extname(f)) == parts[-2]

        !entry_point?(f)
      end.sort
    end

    def entry_point?(path)
      full = File.join(ROOT, path)
      return true if File.executable?(full)
      return true if path.end_with?(".sh", ".yml", ".toml")

      # The repeated word is only a stutter when the file says it twice: once
      # for the namespace and again for the thing inside it, which is how
      # lib/cli/cli.rb comes to hold Master::CLI::CLI. Said once, it is a module
      # root and how Ruby finds the namespace at all -- law/law.rb declares Law.
      # Said not at all, the file is a script and its folder is named after the
      # tool, which is `ruby STUDIO/dilla/dilla.rb` reading correctly.
      name = File.basename(path, File.extname(path))
      File.read(full).scan(/^\s*(?:module|class)\s+#{Regexp.escape(name)}\b/i).size < 2
    rescue ArgumentError
      true
    end

    def vague_names
      tracked.select { |f| VAGUE.include?(File.basename(f, File.extname(f))) }.sort
    end

    def counts
      { "lone_dirs" => lone_dirs.size, "stutter" => stutter.size, "vague_names" => vague_names.size }
    end

    def ceilings
      File.exist?(CEILINGS) ? YAML.safe_load_file(CEILINGS) : {}
    end

    def run(ratchet: false, list: false)
      now = counts
      recorded = ceilings
      now.each { |k, v| puts "sprawl_census: #{k} #{v} (ceiling #{recorded.fetch(k, v)})" }

      if list
        { "lone_dirs" => lone_dirs, "stutter" => stutter, "vague_names" => vague_names }.each do |kind, files|
          puts "\n#{kind} (#{files.size})"
          files.each { |f| puts "  #{f}" }
        end
        return 0
      end

      over = now.select { |k, v| v > recorded.fetch(k, v) }
      if ratchet && now.any? { |k, v| v < recorded.fetch(k, v) }
        File.write(CEILINGS, recorded.merge(now) { |_, old, new| [old, new].min }.to_yaml)
        puts "sprawl_census: recorded a new low"
        return 0
      end
      return 0 if over.empty?

      over.each { |k, v| puts "sprawl_census: #{k} rose to #{v} from #{recorded.fetch(k)} — flatten it, name it, or price the ceiling" }
      1
    end
  end
end

if $PROGRAM_NAME == __FILE__
  exit Pub4::SprawlCensus.run(ratchet: ARGV.include?("--ratchet"), list: ARGV.include?("--list"))
end
