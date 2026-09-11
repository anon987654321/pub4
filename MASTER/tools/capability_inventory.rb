# frozen_string_literal: true

# Capability inventory — the non-v115.1 "have we lost anything" check.
#
# Compares named surfaces in the working tree to origin/main (HEAD if that
# ref is missing). Additions are fine. A deleted name fails.
#
#   ruby MASTER/tools/capability_inventory.rb
#   rake lint:capability
#
# Pinned by MASTER/test/test_capability_inventory.rb.

require "open3"
require "yaml"

module Operator
  class CapabilityInventory
    MASTER = File.expand_path("..", __dir__)
    REPO = File.expand_path("..", MASTER)

    SOURCES = {
      slashes: "lib/cli/command_registry.rb",
      help: "lib/cli/command_registry/help.rb",
      personas: "data/council.yml",
      biases: "data/rules.yml",
      constitution: "lib/core/constitution.rb",
      law_files: nil,
    }.freeze

    LAW_FILES = %w[soul.yml rules.yml limits.yml voice.yml].freeze

    def self.report
      new.report
    end

    # A rename is not a loss, and a diff of names cannot tell them apart: each
    # shows a word absent from the working tree. Recording the rename is what
    # keeps this guard strict — a name no successor claims still fails.
    #
    # Each key is a word this surface no longer answers to, and each value is the
    # word that took its work. /review is named for lib/review, the subsystem that
    # scans and critiques.
    RENAMES = { "through" => "review" }.freeze

    def report
      current = inventory(nil)
      baseline = inventory(baseline_ref)
      lost = {}
      current.each_key do |kind|
        gone = Array(baseline[kind]) - Array(current[kind])
        unclaimed = gone.reject { |name| renamed?(name, Array(current[kind])) }
        lost[kind] = unclaimed unless unclaimed.empty?
      end
      { current:, baseline_ref:, lost: }
    end

    def renamed?(name, present)
      successor = RENAMES[name]
      successor && present.include?(successor)
    end

    def inventory(ref)
      {
        slashes: slashes(read("lib/cli/command_registry.rb", ref)),
        help: slashes(read("lib/cli/command_registry/help.rb", ref)),
        personas: personas(read("data/council.yml", ref)),
        biases: biases(read("data/rules.yml", ref)),
        constitution: rule_ids(read("lib/core/constitution.rb", ref)),
        law_files: law_files(ref),
      }
    end

    def baseline_ref
      show_ok?("origin/main") ? "origin/main" : "HEAD"
    end

    private

    def slashes(text)
      text.to_s.scan(/^\s+"(\w+)" =>/).flatten.uniq.sort
    end

    def personas(text)
      return [] if text.to_s.empty?

      YAML.safe_load(text, aliases: true).fetch("personas", []).map { |row| row["name"] }.compact.sort
    end

    def biases(text)
      return [] if text.to_s.empty?

      (YAML.safe_load(text, aliases: true)["biases"] || {}).keys.map(&:to_s).sort
    end

    # Both shapes a rule declares its id in.
    #
    # This reads source text rather than asking the constitution, because it
    # also reads older versions out of a git ref to compare — there is no
    # runtime to ask for a commit that is not checked out. The cost is that a
    # refactor which changes how an id is written makes rules vanish from the
    # inventory while they keep working: folding five builders into reason_rule
    # turned `id: :batch_delete` into `reason_rule(:batch_delete` plus a
    # shorthand `id:`, and batch_delete, forbidden_file, scope_creep, two_hats
    # and new_path_ask disappeared from a report that is meant to notice
    # exactly that.
    RULE_ID = /id: :(\w+)|reason_rule\(:(\w+)/

    def rule_ids(text)
      text.to_s.scan(RULE_ID).flatten.compact.uniq.sort
    end

    def law_files(ref)
      LAW_FILES.select { |name| ref ? show_ok?("#{ref}:MASTER/data/#{name}") : File.exist?(File.join(MASTER, "data", name)) }
    end

    def read(relative, ref)
      return File.read(File.join(MASTER, relative)) unless ref

      out, status = Open3.capture2("git", "-C", REPO, "show", "#{ref}:MASTER/#{relative}")
      status.success? ? out : ""
    end

    def show_ok?(spec)
      _out, status = Open3.capture2("git", "-C", REPO, "cat-file", "-e", spec)
      status.success?
    end
  end
end

if $PROGRAM_NAME == __FILE__
  report = Operator::CapabilityInventory.report
  if report[:lost].empty?
    puts "capability: ok vs #{report[:baseline_ref]}"
    exit 0
  end

  report[:lost].each { |kind, names| puts "capability: lost #{kind} #{names.join(", ")}" }
  exit 1
end
