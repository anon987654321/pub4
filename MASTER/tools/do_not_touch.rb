# frozen_string_literal: true

require "open3"

# A "Do Not Touch" entry must name the gate that fails when its claim stops
# being true — or say plainly that no gate can hold it, and why.
#
# START_HERE.md's item 2 said the rule shards stayed split because they sat near
# their consumers. That was false, and had been false for as long as the shards
# existed: the four of them had one consumer between them, `load_rules`, which
# concatenated them back into a single hash before any scanner saw them. Nobody
# was careless. The entry stated a conclusion, and conclusions do not rot loudly
# — it took an operator override in 2026-08 to find out the reason had never
# been true.
#
# Had the entry named the test its reason implied — each shard has a distinct
# reader — that test would have been red from the first day and the entry would
# have re-argued itself years before anyone had to override it by hand.
#
# So every entry carries one of:
#
#   — gate: `rake lint:spine`, `test/test_core_no_lib_backedges.rb`
#   — no gate: <why the claim cannot be mechanically held>
#
# and this checks that the named rake tasks and files actually exist. A gate
# reference that stops resolving is the same failure one level up.
#
#   ruby MASTER/tools/do_not_touch.rb
#   ruby MASTER/tools/do_not_touch.rb --json
#
# Wired as `rake lint:do_not_touch`, pinned by test/test_do_not_touch.rb.

require "json"

module Pub4
  class DoNotTouch
    MASTER = File.expand_path("..", __dir__)
    ROOT = File.expand_path("..", MASTER)
    DOC = File.join(MASTER, "START_HERE.md")

    HEADING = /^##\s+Do Not Touch/
    ENTRY = /^(\d+)\.\s+(.*)$/
    RAKE = /`rake ([a-z_]+(?::[a-z_]+)*)`/
    FILE = /`([A-Za-z0-9_.\-\/]+\.(?:rb|sh|yml))`/
    NO_GATE = /—\s*no gate:\s*(.+)/

    # Reasons shorter than this are a shrug, not an argument. Same threshold
    # doc_baselines.yml#doc_paths entries are held to.
    MIN_REASON = 20

    def self.entries
      @entries ||= parse(File.readlines(DOC))
    end

    # An entry is its whole paragraph, not its first line. Prose here wraps at 80
    # columns like the rest of the tree, so reading one line drops the gate
    # reference off any entry long enough to need two, and an entry that names its
    # gate on the second line then reports as naming none. Separate from `entries`
    # so a test can hand it a wrapped list instead of the live document.
    def self.parse(lines)
      start = lines.index { |line| line.match?(HEADING) }
      raise "START_HERE.md has no 'Do Not Touch' heading" unless start

      rest = lines[(start + 1)..]
      stop = rest.index { |line| line.start_with?("## ") } || rest.size
      rest[0...stop].each_with_object([]) do |line, acc|
        if (match = line.match(ENTRY))
          acc << match.captures
        elsif !acc.empty? && !line.strip.empty?
          acc.last[1] = "#{acc.last[1]} #{line.strip}"
        end
      end
    end

    # Described rake tasks, from rake itself rather than a regex over the
    # Rakefile — a task can be defined in any file the Rakefile loads.
    def self.rake_tasks
      @rake_tasks ||= begin
        out, _status = Open3.capture2("bundle", "exec", "rake", "-T", chdir: MASTER, err: File::NULL)
        out.scan(/^rake (\S+)/).flatten
      end
    end

    def self.file?(path)
      [File.join(ROOT, path), File.join(MASTER, path)].any? { |candidate| File.exist?(candidate) }
    end

    def self.check(number, text)
      if (reason = text[NO_GATE, 1])
        return [] if reason.strip.length >= MIN_REASON

        return [finding(number, "declares no gate without saying why (reason must be a sentence)")]
      end

      gates = text.scan(RAKE).flatten + text.scan(FILE).flatten
      return [finding(number, "names no gate and does not say why it cannot have one")] if gates.empty?

      missing(number, text)
    end

    def self.missing(number, text)
      dead = text.scan(RAKE).flatten.reject { |task| rake_tasks.include?(task) }.map { |task| "rake #{task}" }
      dead += text.scan(FILE).flatten.reject { |path| file?(path) }

      return [] if dead.empty?

      [finding(number, "names a gate that does not exist: #{dead.join(', ')}")]
    end

    def self.finding(number, message)
      { "entry" => number, "message" => message }
    end

    def self.run
      findings = entries.flat_map { |number, text| check(number, text) }
      gated = entries.count { |_, text| !text.match?(NO_GATE) }

      { "entries" => entries.size, "gated" => gated, "ungated" => entries.size - gated,
        "rake_tasks" => rake_tasks.size, "findings" => findings }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  report = Pub4::DoNotTouch.run

  if ARGV.include?("--json")
    puts JSON.pretty_generate(report)
  else
    report["findings"].each { |row| puts "Do Not Touch #{row['entry']}: #{row['message']}" }
    puts
    puts "#{report['entries']} entries — #{report['gated']} name a gate, " \
         "#{report['ungated']} state why they cannot have one"
    puts "do_not_touch: #{report['findings'].empty? ? 'clean' : "#{report['findings'].size} finding(s)"}"
  end

  exit(report["findings"].empty? ? 0 : 1)
end
