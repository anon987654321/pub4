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
      path.include?("/MASTER/law/") ? ::Law.conduct(text) : text
    end

    # Memoized for the same reason `files` is, and it matters more here: the
    # corpus is 2871 files against 72 rules, and TestRatchets asks five separate
    # questions of it in one process. Rescanning per question put every one of
    # them over the test's timeout. The tree does not change inside a run.
    def by_rule
      @by_rule ||= scan_corpus
    end

    def scan_corpus
      rules = law # loads Master before the map below is read
      counts = Hash.new(0)
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
        rules.each_value do |rule|
          next if rule.semantic? || !rule.applies?(path, lang)

          counts[rule.id.to_s] += rule.scan(text, file: path).size
        end
      end
      counts.reject { |_, v| v.zero? }.sort_by { |_, v| -v }.to_h
    end

    def ceiling = YAML.safe_load_file(CEILING).fetch("findings")

    def run(json: false)
      counts = by_rule
      total = counts.values.sum
      return (puts JSON.pretty_generate(total: total, by_rule: counts)) || true if json

      puts "self_findings: #{total} across #{files.size} files from #{law.size} rules"
      counts.first(10).each { |id, n| puts format("  %-26s %5d", id, n) }
      over = total > ceiling
      warn "self_findings: exceeds baseline — #{total} > #{ceiling}" if over
      !over
    end
  end
end

require "yaml"

if $PROGRAM_NAME == __FILE__
  ok = Pub4::SelfFindings.run(json: ARGV.include?("--json"))
  exit(ok ? 0 : 1)
end
