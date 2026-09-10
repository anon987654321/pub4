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
# 4,609 lines and injecting it every turn would drown the turn. Six kilobytes
# go out — the binding half: the conduct rules that govern how to work, what the
# gate can actually block on, and how much of the law is unmeasured right now.

module Pub4
  module AgentContext
    MASTER_DIR = File.expand_path("..", __dir__)
    BLOCKING = %i[veto critical error].freeze

    module_function

    # The 47 rules about how to work, each as one sentence. They are `practice`
    # laws in law/practice.rb, which is the only population a detector cannot
    # describe — "sweep to convergence", "one SSH session" — and therefore the
    # half of the law an agent has to be told rather than caught on.
    #
    # This read `soul.yml`'s `absolute.rules`, where they lived until the
    # `conduct` kind let them be Laws. Since that move the key has not existed,
    # `dig` answered nil, and the heading below printed over an empty list: the
    # law-in-force section of the file that hands agents the law in force named
    # nothing at all. Every other section kept working, which is why it stood.
    def conduct
      load_master
      require File.join(MASTER_DIR, "law", "law") unless defined?(::Law)
      ::Law.load_all(File.join(MASTER_DIR, "law")) if ::Law.rules.empty?
      ::Law.rules.values.select(&:practice).to_h do |rule|
        [rule.id.to_s, rule.practice.to_s.gsub(/\s+/, " ").strip]
      end
    rescue StandardError => e
      { "conduct unavailable" => e.class.to_s }
    end

    # Only the rules that can refuse a write. A list of 242 is a reference; a
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
      out = ["MASTER conduct in force (law/practice.rb):"]
      conduct.each { |name, text| out << "  #{name}: #{text.to_s.split(/(?<=\.)\s/).first}" }
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
