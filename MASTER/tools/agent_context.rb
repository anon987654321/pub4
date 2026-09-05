# frozen_string_literal: true

# What MASTER knows, in a form an agent can be handed before every message.
#
# MASTER keeps 17 memory classes, 830 files under knowledge/ and 1,251 under
# .master/. Claude Code keeps its own memory directory. Nothing in lib/, tools/
# or bin/ reads ~/.claude, and nothing writes MASTER's learnings back to it —
# two memories in one repo with no path between them.
#
#   ruby MASTER/tools/agent_context.rb                 # the standing context
#   ruby MASTER/tools/agent_context.rb "<prompt>"      # plus what matches it
#
# Designed for a UserPromptSubmit hook, so it has to be small: data/rules.yml is
# 3,108 lines and injecting it every turn would drown the turn. What goes out is
# the binding half — the code rules that constrain output, what the gate can
# actually block on, and how much of the law is unmeasured right now.

module Pub4
  module AgentContext
    MASTER_DIR = File.expand_path("..", __dir__)
    BLOCKING = %i[veto critical error].freeze

    module_function

    # Both files go through the accessors the rest of MASTER uses. Opening them
    # directly is what reader_singularity counts, and it refused this file twice
    # before this — a data file with two loaders has two behaviours.
    def rules
      load_master
      Master::Ground::Rules.new.data("soul").dig("absolute", "rules") || {}
    end

    # Only the rules that can refuse a write. A list of 225 is a reference; a
    # list of what actually blocks is an instruction.
    def blocking_rules
      load_master
      Master.flatten_rules(Master.load_rules(root: MASTER_DIR).fetch("rules", {}))
            .select { |rule| BLOCKING.include?(rule["severity"].to_s.to_sym) }
            .filter_map { |rule| rule["id"] }.sort
    end

    def load_master
      $LOAD_PATH.unshift(File.join(MASTER_DIR, "lib")) unless $LOAD_PATH.include?(File.join(MASTER_DIR, "lib"))
      require "master"
    end

    def coverage
      load_master
      Master::Review::Scan::RuleRegistryAudit.new(root: MASTER_DIR).call.coverage_line
    rescue StandardError => e
      "rule coverage unavailable (#{e.class})"
    end

    # Memory is matched on the words of the prompt rather than searched
    # semantically: a hook has milliseconds, and an exact-word hit on a lesson
    # filename is a better signal than an embedding at this size.
    def lessons(query)
      return [] unless query

      path = File.join(MASTER_DIR, "data", "pub_archive_restore.yml")
      return [] unless File.file?(path)

      words = query.downcase.scan(/[a-z]{4,}/).uniq
      name = File.basename(path, ".yml").tr("_", " ")
      words.any? { |w| name.include?(w) } ? [path] : []
    end

    def render(query = nil)
      out = ["MASTER law in force (data/soul.yml absolute.rules):"]
      rules.each { |name, text| out << "  #{name}: #{text.to_s.split(/(?<=\.)\s/).first}" }
      out << ""
      out << "Rules that can refuse a write (#{blocking_rules.size}): #{blocking_rules.join(', ')}"
      out << "Coverage: #{coverage}"
      matched = lessons(query)
      out << "Lessons matching this prompt: #{matched.map { |p| File.basename(p, '.yml') }.join(', ')}" if matched.any?
      out.join("\n")
    end
  end
end

puts Pub4::AgentContext.render(ARGV.first) if $PROGRAM_NAME == __FILE__
