# frozen_string_literal: true

# What MASTER's own rules find in MASTER's own tree.
#
# The question "would running MASTER through its own rules make it tidier" has a
# number, and this is it. Every rule with a lexical detector, over every tracked
# Ruby file in the four trees.
#
# Lexical only, on purpose. The full gate runs /scan with the semantic pass and
# blocks on a model call — measured 2026-08-25 at 17 minutes elapsed against 4
# minutes of CPU, idle in a TLS read, on its way to a 20-minute stage timeout.
# A number that needs a network and an API key is a number nobody has. These 70
# rules need neither and finish in about a minute.
#
#   ruby MASTER/tools/self_findings.rb
#   ruby MASTER/tools/self_findings.rb --json
#   ruby MASTER/tools/self_findings.rb --ratchet  # record a new low, with its members

require "English"
require "json"

module Pub4
  module SelfFindings
    MASTER_DIR = File.expand_path("..", __dir__)
    ROOT = File.expand_path("..", MASTER_DIR)
    CEILING = File.join(MASTER_DIR, "data", "self_findings.yml")

    # The locale trees carry the only non-English prose in the repo, which is
    # what the nb laws in law/prose.rb judge. Without them those two load,
    # prove their fixtures, and reach no file — law that reads as enforcement
    # and enforces nothing, which is the defect this repo names most often.
    TREES = %w[
      MASTER/lib MASTER/law MASTER/tools RAILS/shared/lib RAILS/gates OPENBSD STUDIO
      RAILS/amber RAILS/brgen RAILS/bsdports RAILS/shared/app RAILS/shared/config
    ].freeze

    module_function

    def law
      unless defined?(::Law)
        require File.join(MASTER_DIR, "lib", "master")
        require File.join(MASTER_DIR, "law", "law")
      end
      ::Law.load_all(File.join(MASTER_DIR, "law")) if ::Law.rules.empty?
      ::Law.rules
    end

    # Code we did not write and will not fix. STUDIO/dilla/tools/venv-demucs is
    # a Python virtualenv with pip, torch and urllib3 vendored inside it, and
    # its JavaScript and HTML were being graded against this repo's rules —
    # `var headers = []` in urllib3's emscripten worker is not our debt.
    # Code we did not write, and code we did not type. A Rails app carries both:
    # public/assets is the precompiled output (1361 `var` findings in amber
    # alone, none of them source), app/views/pwa/service-worker.js is what
    # `npm run build:pwa` emits, and db/schema.rb says in its own first line
    # that it is generated from the database.
    THIRD_PARTY = %r{
      /(?:vendor|node_modules|site-packages|assets/builds|public/assets)/
      |/\.?venv[-/]
      |/db/(?:schema|cable_schema|cache_schema|queue_schema)\.rb\z
      |/(?:cable|cache|queue)_migrate/
      |/service-worker\.js\z
      |\.min\.(?:js|css)\z
    }x
    # Every extension a law can declare, not just Ruby. The corpus globbed
    # `*.rb` while the laws claim nine languages, so every css, scss, yaml,
    # markdown, html, json and shell law in the registry was measured against
    # nothing and reported clean: NULLISH_COALESCING, I18N_COVERAGE,
    # STRICT_LOADING_MISSING and META_CHARSET had 75 findings between them that
    # this tool could not see. A ratchet blind to two thirds of its subject
    # counts down to zero without the tree improving.
    # Asked of git rather than of the filesystem. The corpus is what the repo
    # tracks plus what it has not ignored, which is what this tool has always
    # claimed to measure -- and git prunes an ignored directory instead of
    # descending it. Dir.glob could not: STUDIO carries a sample library, a
    # scratch directory and gigabytes of renders, all gitignored, and walking
    # them once per declared extension to throw them away took every one of
    # TestRatchets' four questions past its 300s timeout. The same list comes
    # back in 0.05s. Memoized because `run` asks for it twice.
    def files
      law # loads Master before FILE_LANGUAGE_MAP is read, as by_rule does
      @files ||= begin
        listing = IO.popen(["git", "-C", ROOT, "ls-files", "-z", "--cached", "--others",
                            "--exclude-standard", "--", *TREES], &:read)
        raise "self_findings: git ls-files failed in #{ROOT}" unless $CHILD_STATUS.success?

        extensions = Master::FILE_LANGUAGE_MAP.keys
        listing.split("\0").filter_map do |relative|
          next unless extensions.include?(File.extname(relative))

          path = File.join(ROOT, relative)
          path unless path.match?(THIRD_PARTY)
        end.sort
      end
    end

    # A law file necessarily contains the pattern it forbids — in its detector,
    # its fix line and its bad fixture. Law.scan neutralises those before a law
    # judges law/; this file called rule.scan directly and skipped it, so all 35
    # findings under law/ were laws quoting themselves. With conduct applied it
    # is 0, which is the honest number: those lines declare evidence.
    def considered(path, text)
base = path.include?("/MASTER/law/") ? ::Law.conduct(text) : text
# A Ruby law reading a <<~JS or <<~SQL body reports on a language it does
# not govern. See SourceMasking#without_foreign_heredocs.
return base unless path.end_with?(".rb", ".rake")

Master::Review::Scan::SourceMasking.without_foreign_heredocs(base)
    end

    # Counted from the members rather than tallied alongside them, so the
    # summary and the attribution list can never disagree about a number.
    def by_rule
      members.each_with_object(Hash.new(0)) { |member, counts| counts[member.split(" ", 2).first] += 1 }
             .sort_by { |_, n| -n }.to_h
    end

    # The members behind the count, `RULE path:line`, one per finding.
    # Memoized for the same reason `files` is, and it matters more here: the
    # corpus is 2869 files against 122 rules, and TestRatchets asks five
    # separate questions of it in one process. Rescanning per question put
    # every one of them over the test timeout. The tree does not change
    # inside a run.
    #
    # A census that records only an integer can say "over by twelve" and never
    # which twelve, so the number arrives with no thread to pull — the same gap
    # data_reach closed on 2026-08-31, and the reason that one could name its
    # two keys while this one could only report a delta. Sorted, so two runs of
    # an unchanged tree produce the same list and a diff means a change.
    def members
      @members ||= scan_corpus
    end

    def scan_corpus
      rules = law # loads Master before the map below is read
      found = []
      files.each do |path|
        # The file list and the reads are two moments, and this is a shared
        # checkout: a file listed a second ago can be gone by the time it is
        # opened. That crashed the whole census on
        # STUDIO/dilla/demo.mp3.quality.json while another session was deleting
        # it -- a tool that reports a number for the tree dying because the tree
        # moved. Skipped rather than rescued blind: a file that is gone
        # contributes no findings, which is the right answer, and anything else
        # unreadable still raises.
        next unless File.file?(path)

        text = begin
          considered(path, File.read(path, encoding: "UTF-8").scrub)
        rescue Errno::ENOENT
          next
        end
        lang = Master::FILE_LANGUAGE_MAP[File.extname(path)]&.to_sym
        relative = path.delete_prefix("#{ROOT}/")
        rules.each_value do |rule|
          next if rule.semantic? || !rule.applies?(path, lang)

          rule.scan(text, file: path).each { |hit| found << "#{rule.id} #{relative}:#{hit.line}" }
        end
      end
      found.sort
    end

    def recorded = YAML.safe_load_file(CEILING) || {}

    def ceiling = recorded.fetch("findings")

    # Two attributions, because they answer different questions and both were
    # wanted on the same day. `by_rule` says which rules moved and by how much,
    # which is what you read first. `members` says which lines, which is what
    # you act on. A census recording one integer can say "over by twelve" and
    # name neither, and naming them meant checking out the commit that set the
    # baseline and diffing two runs by hand.
    #
    # Absent, attribution is unavailable and the report says so rather than
    # reporting no movement — a different claim.
    def recorded_by_rule = recorded["by_rule"].is_a?(Hash) ? recorded["by_rule"] : {}

    def recorded_members = Array(recorded["members"])

    # Which rules moved since the baseline, and by how much.
    def report_drift(counts)
      known = recorded_by_rule
      if known.empty?
        puts "self_findings: no by_rule recorded with the baseline — run --ratchet at or below it to make the next rise attributable"
        return
      end

      moved = (known.keys | counts.keys).sort.filter_map do |id|
        before, after = known[id].to_i, counts[id].to_i
        next if before == after

        format("  %-26s %4d -> %4d  %+d", id, before, after, after - before)
      end
      puts moved.empty? ? "self_findings: no rule moved since the baseline" : "self_findings: rules that moved since the baseline:"
      moved.each { |line| puts line }
    end

    # Which lines arrived and which left.
    def report_delta(current)
      if recorded_members.empty?
        puts "self_findings: no members recorded — line attribution unavailable; run --ratchet to seed it"
        return
      end

      arrived = current - recorded_members
      left = recorded_members - current
      puts "self_findings: #{arrived.size} arrived, #{left.size} left"
      arrived.each { |member| puts "  + #{member}" }
      left.each { |member| puts "  - #{member}" }
    end

    def run(json: false, ratchet: false)
      current = members
      counts = by_rule
      total = current.size
      return (puts JSON.pretty_generate(total: total, by_rule: counts)) || true if json

      puts "self_findings: #{total} across #{files.size} files from #{law.size} rules"
      counts.first(10).each { |id, n| puts format("  %-26s %5d", id, n) }
      over = total > ceiling
      # <=, not <, so a census sitting exactly at its ceiling can record its
      # attribution without having to fall first — the same reason data_reach
      # seeds at parity. A census already over cannot: a baseline containing the
      # overage would report it as known and hide exactly what is wanted.
      if ratchet && !over
        # Read before the write: `ceiling` re-reads the file, so asking after
        # writing always answers with the number just written, and every fall
        # reports itself as a re-record.
        previous = ceiling
        File.write(CEILING, rewritten_ceiling(total, counts, current))
        puts "self_findings: #{total < previous ? "recorded #{total} as the new low" : "re-recorded #{total}"}, with its rules and its members"
        return true
      end

      if over
        warn "self_findings: exceeds baseline — #{total} > #{ceiling}"
        report_drift(counts)
        report_delta(current)
      end
      !over
    end

    # The prose above `findings:` is most of this file and records what each past
    # move cost somebody, so it is preserved rather than regenerated. A bare
    # to_yaml dump of the ceiling eats all of it, which is how the dup_census
    # ceiling lost thirty lines of history the first time it recorded members.
    def rewritten_ceiling(total, counts, current)
      prose = File.read(CEILING).sub(/^findings: .*\n(?:by_rule:\n(?:  \S+: \d+\n)*)?(?:members:\n(?:  - .*\n)*)?\z/, "")
      by_rule = counts.sort.to_h.map { |id, n| "  #{id}: #{n}\n" }.join
      members = current.map { |m| "  - #{m}\n" }.join
      "#{prose}findings: #{total}\nby_rule:\n#{by_rule}members:\n#{members}"
    end
  end
end

require "yaml"

if $PROGRAM_NAME == __FILE__
  ok = Pub4::SelfFindings.run(json: ARGV.include?("--json"), ratchet: ARGV.include?("--ratchet"))
  exit(ok ? 0 : 1)
end
