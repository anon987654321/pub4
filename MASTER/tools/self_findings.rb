# frozen_string_literal: true

# What MASTER's own rules find in MASTER's own tree.
#
# The question "would running MASTER through its own rules make it tidier" has a
# number, and this is it. Two numbers, because this repo has two populations of
# rules and for a year only one of them was counted:
#
#   law       the 122 rules in law/ with a lexical detector, applied to every
#             tracked source file in the four trees
#   registry  the 145 rules the RuleDSL registry builds, run through the
#             scanner itself and kept at error severity
#
# The second row arrived 2026-09-06. The first had been labelled "what our own
# rules find in our own trees" while measuring the law alone, and nothing
# anywhere counted what the registry finds: rule_audit runs those rules over a
# sixth of the tree and measures blindness rather than findings, and `bin/pub4
# gate` runs them over all four trees on every pass and records nothing.
#
# Lexical only, on purpose. The full gate runs /scan with the semantic pass and
# blocks on a model call — measured 2026-08-25 at 17 minutes elapsed against 4
# minutes of CPU, idle in a TLS read, on its way to a 20-minute stage timeout.
# A number that needs a network and an API key is a number nobody has. Both
# populations here need neither and finish in about two minutes.
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
    def tally(current)
      current.each_with_object(Hash.new(0)) { |member, counts| counts[member.split(" ", 2).first] += 1 }
             .sort_by { |_, n| -n }.to_h
    end

    def by_rule = tally(members)

    def registry_by_rule = tally(registry_members)

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

    # The other population, and three decisions that each change its number.
    #
    # Through the scanner, not by hand. A harness calling `rule.check` on every
    # tracked file read 221 findings at error severity where the scanner reads
    # 108, because the scanner routes: PathFilter drops what nobody authored and
    # each rule sees only the languages it declares. The harness number was an
    # upper bound on a question nobody asked.
    #
    # Error severity only. The same run reports 10,147 warnings and 7,997 info.
    # A ceiling nobody can hold is decoration, and the warning half is the
    # scan-noise TODO.md already triages one entry at a time.
    #
    # The scanner's own rules only. A law reaches the scanner through
    # LawBridgeRule and reports under its own id, so the STRICT_MODE_ZSH,
    # NEVER_BATCH_DELETE, RATE_LIMITING_MISSING and MIGRATION_ADD_REFERENCE_NO_FK
    # findings the scan returns are already members of the law row above —
    # fifteen of them, and one fix would have moved two ratchets. Keeping only
    # ids the scanner carries as rules of its own leaves each finding counted
    # once.
    def registry_members
      @registry_members ||= scan_registry
    end

    # Built the way every other caller builds it, and the way tools/example_scan.rb
    # documents: InfraHelpers, then `findings`. There is no scan_file.
    def scan_registry
      law # loads Master, as scan_corpus does
      scanner = Master::Review::Scan::InfraHelpers.build_scanner(root: MASTER_DIR)
      own = scanner.rules.select { |rule| shipped?(rule) }.map { |rule| rule.id.to_s }
      @registry_rule_count = own.size
      corpus = files.reject { |path| Master::Review::Scan::Scanner.skip_path?(path, root: ROOT) }
      scanner.findings(corpus, depth: :deep).filter_map do |hit|
        next unless hit[:severity].to_s == "error" && own.include?(hit[:rule].to_s)

        "#{hit[:rule]} #{hit[:path].to_s.delete_prefix("#{ROOT}/")}:#{hit[:line]}"
      end.sort
    end

    # `Rule.inherited` registers every subclass in the running process, so a
    # suite that defines one joins the population it is measuring — the trap
    # rule_deps.ungraphed hit first, reading two different numbers depending on
    # whether a test had defined a rule. RuleRegistryAudit already owns the
    # question, so this asks it rather than carrying a second answer.
    def shipped?(rule)
      @audit ||= Master::Review::Scan::RuleRegistryAudit.new(root: MASTER_DIR)
      @audit.shipped?(rule.class)
    end

    def registry_rule_count
      registry_members
      @registry_rule_count
    end

    def recorded = YAML.safe_load_file(CEILING) || {}

    # Both populations record the same three things and one file holds them
    # both. Every key is spelled here rather than built from a prefix, because
    # data_reach reads the tree for the literal key name: one pass of
    # `"#{prefix}finding_members"` made finding_members look like a key nothing
    # reads, which is the inert-config shape this repo hunts — introduced by the
    # reader written to serve two populations.
    KEYS = {
      "law" => { total: "findings", by_rule: "by_rule", members: "finding_members" },
      "registry" => { total: "registry_findings", by_rule: "registry_by_rule",
                      members: "registry_finding_members" },
    }.freeze

    def ceiling(name = "law") = recorded.fetch(KEYS.fetch(name)[:total])

    def registry_ceiling = ceiling("registry")

    # Two attributions, because they answer different questions and both were
    # wanted on the same day. `by_rule` says which rules moved and by how much,
    # which is what you read first. `members` says which lines, which is what
    # you act on. A census recording one integer can say "over by twelve" and
    # name neither, and naming them meant checking out the commit that set the
    # baseline and diffing two runs by hand.
    #
    # Absent, attribution is unavailable and the report says so rather than
    # reporting no movement — a different claim.
    def recorded_by_rule(name = "law")
      known = recorded[KEYS.fetch(name)[:by_rule]]
      known.is_a?(Hash) ? known : {}
    end

    def recorded_members(name = "law") = Array(recorded[KEYS.fetch(name)[:members]])

    # Which rules moved since the baseline, and by how much.
    def report_drift(counts, known = recorded_by_rule)
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
    def report_delta(current, known = recorded_members)
      if known.empty?
        puts "self_findings: no members recorded — line attribution unavailable; run --ratchet to seed it"
        return
      end

      arrived = current - known
      left = known - current
      puts "self_findings: #{arrived.size} arrived, #{left.size} left"
      arrived.each { |member| puts "  + #{member}" }
      left.each { |member| puts "  - #{member}" }
    end

    POPULATIONS = KEYS.keys.freeze

    def population(name) = name == "law" ? members : registry_members

    def rules_behind(name) = name == "law" ? law.size : registry_rule_count

    # Both populations are measured on every run, whatever the arguments. One
    # file holds both baselines, so a run that measured one of them and wrote
    # would put the other's last number back as if it were today's.
    def run(json: false, ratchet: false)
      return json_report if json

      over = POPULATIONS.reject { |name| report(name) }
      # A census sitting exactly at its ceiling can still record its
      # attribution, without having to fall first — the same reason data_reach
      # seeds at parity. One already over cannot: a baseline containing the
      # overage would report it as known and hide exactly what is wanted.
      return record if ratchet && over.empty?

      over.empty?
    end

    def json_report
      puts JSON.pretty_generate(POPULATIONS.to_h { |name|
        [name, { total: population(name).size, by_rule: tally(population(name)) }]
      })
      true
    end

    # One population's line, its ten loudest rules, and — only when it is over —
    # which rules moved and which lines arrived.
    def report(name)
      current = population(name)
      counts = tally(current)
      puts "self_findings #{name}: #{current.size} across #{files.size} files from #{rules_behind(name)} rules"
      counts.first(10).each { |id, n| puts format("  %-26s %5d", id, n) }
      return true unless current.size > ceiling(name)

      warn "self_findings #{name}: exceeds baseline — #{current.size} > #{ceiling(name)}"
      report_drift(counts, recorded_by_rule(name))
      report_delta(current, recorded_members(name))
      false
    end

    def record
      # Read before the write: `ceiling` re-reads the file, so asking after
      # writing always answers with the number just written, and every fall
      # reports itself as a re-record.
      previous = POPULATIONS.to_h { |name| [name, ceiling(name)] }
      File.write(CEILING, rewritten_ceiling)
      POPULATIONS.each do |name|
        total = population(name).size
        moved = total < previous.fetch(name) ? "recorded #{total} as the new low" : "re-recorded #{total}"
        puts "self_findings #{name}: #{moved}, with its rules and its members"
      end
      true
    end

    # The prose above `findings:` is most of this file and records what each past
    # move cost somebody, so it is preserved rather than regenerated. A bare
    # to_yaml dump of the ceiling eats all of it, which is how the dup_census
    # ceiling lost thirty lines of history the first time it recorded members.
    def rewritten_ceiling
      prose = File.read(CEILING).split(/^findings: /, 2).first
      prose + POPULATIONS.map { |name| recorded_block(name, population(name)) }.join
    end

    # One population's three keys: the number, the rules behind it, and the
    # lines behind those.
    def recorded_block(name, current)
      keys = KEYS.fetch(name)
      by_rule = tally(current).sort.to_h.map { |id, n| "  #{id}: #{n}\n" }.join
      "#{keys[:total]}: #{current.size}\n#{keys[:by_rule]}:\n#{by_rule}" \
        "#{keys[:members]}:\n#{current.map { |member| "  - #{member}\n" }.join}"
    end
  end
end

require "yaml"

if $PROGRAM_NAME == __FILE__
  ok = Pub4::SelfFindings.run(json: ARGV.include?("--json"), ratchet: ARGV.include?("--ratchet"))
  exit(ok ? 0 : 1)
end
