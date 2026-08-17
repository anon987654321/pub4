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

module Pub4
  class CapabilityInventory
    MASTER = File.expand_path("..", __dir__)
    REPO = File.expand_path("..", MASTER)

    SOURCES = {
      slashes: "lib/cli/command_registry.rb",
      help: "lib/cli/command_registry/help.rb",
      personas: "data/council.yml",
      biases: "data/biases.yml",
      constitution: "lib/core/constitution.rb",
      law_files: nil,
    }.freeze

    LAW_FILES = %w[soul.yml rules.yml limits.yml voice.yml].freeze

    def self.report
      new.report
    end

    def report
      current = inventory(nil)
      baseline = inventory(baseline_ref)
      lost = current.keys.to_h { |kind| [kind, Array(baseline[kind]) - Array(current[kind])] }
                    .reject { |_, names| names.empty? }
      { current:, baseline_ref:, lost: }
    end

    def inventory(ref)
      {
        slashes: slashes(read("lib/cli/command_registry.rb", ref)),
        help: slashes(read("lib/cli/command_registry/help.rb", ref)),
        personas: personas(read("data/council.yml", ref)),
        biases: biases(read("data/biases.yml", ref)),
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

      YAML.safe_load(text, aliases: true).keys.map(&:to_s).sort
    end

    def rule_ids(text)
      text.to_s.scan(/id: :(\w+)/).flatten.uniq.sort
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
  report = Pub4::CapabilityInventory.report
  if report[:lost].empty?
    puts "capability: ok vs #{report[:baseline_ref]}"
    exit 0
  end

  report[:lost].each { |kind, names| puts "capability: lost #{kind} #{names.join(", ")}" }
  exit 1
end
