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
    MASTER_DIR = File.expand_path("..", __dir__)
    CEILING = File.join(MASTER_DIR, "data", "data_reach.yml")

    CODE_GLOBS = %w[lib/**/*.rb core/**/*.rb web/app/**/*.rb web/config/**/*.rb
                    bin/* tools/**/*.rb test/**/*.rb spec/**/*.rb law/*.rb Rakefile].freeze

    module_function

    def code_files
      @code_files ||= Dir.glob(CODE_GLOBS.map { |g| File.join(MASTER_DIR, g) })
                         .select { |path| File.file?(path) }
                         .to_h { |path| [path, File.read(path)] }
    end

    def code
      @code ||= code_files.values.join
    end

    # A file this cannot parse has no keys, so every key in it passed as read:
    # the census that exists to find unread declarations reported an unreadable
    # file as a clean one, twice, once per question. It cannot fix the file, so
    # the answer is still no keys — said out loud on stderr, naming the file and
    # the parse error. One file answers it today,
    # radio_bergen_track_dossiers.yml, whose bare Ruby symbols safe_load refuses
    # (TODO.md records why quoting them is not this session's change to make).
    # Memoized because both questions ask for every file, and a file that does
    # not parse would otherwise announce itself once per question.
    def document(path)
      @documents ||= {}
      return @documents[path] if @documents.key?(path)

      @documents[path] = begin
        YAML.safe_load_file(path, aliases: true)
      rescue StandardError => e
        warn "data_reach: #{File.basename(path)} does not parse " \
             "(#{e.class}: #{e.message.lines.first.to_s.strip}) — its keys pass this census unread"
        nil
      end
    end

    # A key whose name appears in code that never mentions the yaml file is
    # counted as named by the census and still unread: success_criteria lived
    # in rules.yml while phase_gates.rb read session state under the same word.
    def attributed?(key, yaml_basename)
      needle = /["':]#{Regexp.escape(key.to_s)}\b/
      code_files.any? { |_path, src| src.match?(needle) && src.include?(yaml_basename) }
    end

    def misattributed
      check_corpus!(Dir.glob(File.join(MASTER_DIR, "data", "*.yml")).sort).flat_map do |path|
        doc = document(path)
        next [] unless doc.is_a?(Hash)

        basename = File.basename(path)
        doc.keys.filter_map do |key|
          next unless code.match?(/["':]#{Regexp.escape(key.to_s)}\b/)
          next if attributed?(key, basename)

          "#{basename}##{key}"
        end
      end
    end

    # Both ends, because they fail in opposite directions. An empty code corpus
    # matches no key and reports every one of them, which is loud. An empty data
    # corpus has no keys to report and passes clean, which is the quiet one and
    # the reason this exists.
    def check_corpus!(data_files)
      abort("data_reach: no data/*.yml found -- a report of zero unnamed keys read nothing") if data_files.empty?
      abort("data_reach: the code corpus is empty, so every key reads as unnamed") if code.empty?

      data_files
    end

    def unnamed
      check_corpus!(Dir.glob(File.join(MASTER_DIR, "data", "*.yml")).sort).flat_map do |path|
        doc = document(path)
        next [] unless doc.is_a?(Hash)

        doc.keys.filter_map do |key|
          "#{File.basename(path)}##{key}" unless code.match?(/["':]#{Regexp.escape(key.to_s)}\b/)
        end
      end
    end

    def recorded
      return {} unless File.exist?(CEILING)

      YAML.safe_load_file(CEILING) || {}
    end

    def ceiling = recorded.fetch("unnamed", 0)

    # The members behind the count. A census that records only an integer can
    # say "over by two" and never which two, so the number arrives with no
    # thread to pull and the next reader re-derives the whole list by hand.
    # Absent, attribution is simply unavailable and the report says so rather
    # than guessing.
    def recorded_members = Array(recorded["members"])

    def run(ratchet: false)
      out = unnamed
      misplaced = misattributed
      puts "data_reach: #{out.size} top-level keys no code names (ceiling #{ceiling})"
      unless misplaced.empty?
        puts "data_reach: #{misplaced.size} named in code that never mentions their file:"
        misplaced.each { |key| puts "  #{key} — name appears, but not next to #{key.split('#', 2).first}" }
      end
      # <=, not <, so a census sitting exactly at its ceiling can record its
      # members without having to fall first. That is the common case for a
      # ratchet that is holding, and it seeds the attribution for the next rise.
      #
      # It does NOT help a census that is already over, which cannot record
      # anything without either moving the ceiling or writing a baseline that
      # includes the overage — and a baseline containing the two keys that are
      # over would report them as known and hide exactly what is wanted. When
      # the census is over, attribution comes from diffing against the commit
      # that set the ceiling; that is how business_plan and markdown_style were
      # identified on 2026-08-31.
      if ratchet && out.size <= ceiling
        File.write(CEILING, { "unnamed" => out.size, "members" => out.sort }.to_yaml)
        verb = out.size < ceiling ? "recorded #{out.size} as the new low" : "re-recorded #{out.size}"
        puts "data_reach: #{verb}, with its members"
        return 0
      end
      return 0 unless out.size > ceiling

      report_new(out)

      # All of them, not the first 15. A census that names a third of what it
      # counted leaves the rest invisible: this printed 15 of 55, so the forty
      # it did not name could not be acted on and a +1 could not be attributed
      # to any change. Silent truncation reads as "that is all of them", which
      # is the one thing it must not say.
      out.each { |k| puts "  #{k} — no code names this key; wire a reader or delete the block" }
      1
    end

    # Which of them are new since the low was recorded. This is the whole reason
    # the member list is stored: over-by-two is actionable and a bare 48 is not.
    def report_new(out)
      known = recorded_members
      if known.empty?
        puts "data_reach: no members recorded with the ceiling — run --ratchet once to make the next rise attributable"
        return
      end

      arrived = out - known
      left = known - out
      puts "data_reach: #{arrived.size} arrived since the low was recorded:"
      arrived.each { |k| puts "  + #{k}" }
      puts "data_reach: #{left.size} of the recorded members are gone (#{left.join(', ')})" unless left.empty?
    end
  end
end

exit Pub4::DataReach.run(ratchet: ARGV.include?("--ratchet")) if $PROGRAM_NAME == __FILE__
