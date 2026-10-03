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

require_relative "../lib/fix/protocol"

module Operator
  module AgentContext
    MASTER_DIR = File.expand_path("..", __dir__)
    REPO_ROOT = File.expand_path("..", MASTER_DIR)
    BLOCKING = %i[veto critical error].freeze
    TREE_DEFAULT_DEPTH = 4
    TREE_DEFAULT_MAX_ENTRIES = 2_000
    TREE_SKIP = %w[.git .bundle vendor node_modules tmp log coverage storage .master knowledge output sockets pids cache].freeze

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

    def shell_contract
      load_master
      Master::AI::OperatorContract.prompt.lines.map { |line| "  #{line.rstrip}" }
    end

    # Canonical context for an external model asked to execute /fix.
    def fix_context(target: REPO_ROOT, full: false)
      load_master
      target = File.expand_path(target, Dir.pwd)
      Master::Fix::Protocol.context(root: REPO_ROOT, target:, full:)
    rescue StandardError => e
      "MASTER /fix context unavailable: #{e.class}: #{e.message}"
    end

    def fix_context_args(argv)
      marker = argv.index("--fix-context")
      return unless marker

      target = REPO_ROOT
      full = false
      argv[(marker + 1)..].to_a.each do |arg|
        case arg
        when "--full"
          full = true
        else
          target = File.expand_path(arg, Dir.pwd) if !arg.start_with?("--") && target == REPO_ROOT
        end
      end
      [target, full]
    end

    def tree_args(argv)
      args = argv.dup
      marker = args.index("--tree")
      return unless marker

      depth = TREE_DEFAULT_DEPTH
      max_entries = TREE_DEFAULT_MAX_ENTRIES
      root = REPO_ROOT

      i = marker + 1
      if args[i] && !args[i].start_with?("--")
        root = File.expand_path(args[i], Dir.pwd)
      end

      args[i..].to_a.each do |arg|
        case arg
        when /\A--depth=(\d+)\z/
          depth = Regexp.last_match(1).to_i
        when /\A--max-entries=(\d+)\z/
          max_entries = Regexp.last_match(1).to_i
        end
      end

      [root, depth.clamp(0, 12), max_entries.clamp(1, 20_000)]
    end

    def render_tree(root: REPO_ROOT, max_depth: TREE_DEFAULT_DEPTH, max_entries: TREE_DEFAULT_MAX_ENTRIES)
      root = File.realpath(root)
      raise "tree root is not a directory: #{root}" unless Dir.exist?(root)

      lines = []
      seen = 0
      truncated = false

      walk = lambda do |dir, indent, depth|
        return if depth > max_depth || truncated

        entries = Dir.children(dir).sort_by do |name|
          path = File.join(dir, name)
          [File.directory?(path) ? 0 : 1, name]
        end

        entries.each do |name|
          break if seen >= max_entries
          next if TREE_SKIP.include?(name)

          path = File.join(dir, name)
          stat = File.lstat(path)
          seen += 1
          suffix = stat.symlink? ? "@" : stat.directory? ? "/" : ""
          lines << "#{indent}+-- #{name}#{suffix}"

          if stat.directory? && !stat.symlink?
            if depth < max_depth
              walk.call(path, "#{indent}|   ", depth + 1)
            else
              lines << "#{indent}|   +-- ... (depth limit)"
              seen += 1
            end
          end
        end

        truncated = true if seen >= max_entries
      end

      lines << "#{File.basename(root)}/"
      walk.call(root, "", 0)
      lines << "+-- ... (max entries reached)" if truncated

      header = [
        "source_tree: #{root}",
        "depth: #{max_depth}",
        "entries shown: #{seen}",
        "skips: #{TREE_SKIP.join(", ")}"
      ]
      (header + [""] + lines).join("\n")
    rescue SystemCallError => e
      "source_tree: unavailable: #{e.class}: #{e.message}"
    end

    def render(query = nil)
      out = ["MASTER conduct in force (law/practice.rb):"]
      conduct.each { |name, text| out << "  #{name}: #{text.to_s.split(/(?<=\.)\s/).first}" }
      out << ""
      out << "Rules that can refuse a write (#{blocking_rules.size}): #{blocking_rules.join(', ')}"
      out << "Coverage: #{coverage}"
      out << ""
      out.concat(shell_contract)
      matched = lessons(query)
      out << "Lessons matching this prompt: #{matched.map { |p| File.basename(p, '.yml') }.join(', ')}" if matched.any?
      out.join("\n")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if (options = Operator::AgentContext.fix_context_args(ARGV))
    target, full = options
    puts Operator::AgentContext.fix_context(target:, full:)
  elsif (options = Operator::AgentContext.tree_args(ARGV))
    root, depth, max_entries = options
    puts Operator::AgentContext.render_tree(root:, max_depth: depth, max_entries:)
  else
    puts Operator::AgentContext.render(ARGV.first)
  end
end
