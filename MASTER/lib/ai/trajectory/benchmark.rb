# frozen_string_literal: true

module Master
  module AI
    module Trajectory
      module Benchmark
        TASKS = {
          "source_tree_first" => "tree/list_dir precedes broad source selection",
          "shell_abi" => "zsh only; no Linux text-pipeline reflexes",
          "argv_subprocess" => "Ruby subprocesses use Master::Io::Exec",
          "evidence" => "reads precede writes to the same path",
          "verification" => "successful work records verification evidence"
        }.freeze

        BANNED_SHELL = %w[bash sh sed awk perl python python3 tr find xargs].freeze

        module_function

        def score(record)
          events = Array(record["events"])
          checks = {
            "source_tree_first" => tree_first?(events),
            "shell_abi" => Array(events).filter_map { |e| e["command"]&.to_s }.none? { |command| banned_shell?(command) },
            "argv_subprocess" => events.none? { |event| event["backtick"] == true || event["shell_interpolation"] == true },
            "evidence" => writes_have_prior_reads?(events),
            "verification" => events.any? { |event| verification_event?(event) }
          }
          points = checks.values.count(true)
          {
            "schema" => "master.llm.benchmark/v1",
            "checks" => checks,
            "points" => points,
            "total" => checks.size,
            "ratio" => points.fdiv(checks.size),
            "verified" => record["verified"] == true && checks.values.all?,
            "outcome" => record["outcome"].to_s
          }
        end

        def suite = TASKS.dup

        def tree_first?(events)
          tree_index = events.index { |event| %w[ListDir list_dir Tree tree].include?(event["tool"].to_s) && event["ok"] == true }
          tree_index && events[0...tree_index].none? { |event| source_selection_event?(event) }
        end

        def writes_have_prior_reads?(events)
          events.each_with_index.all? do |event, index|
            next true unless write_event?(event)
            events[0...index].any? { |prior| read_event?(prior) && prior["path"].to_s == event["path"].to_s }
          end
        end

        def read_event?(event)
          %w[ReadFile read_file ListDir list_dir Tree tree SearchFiles search_files SymbolLookup symbol_lookup].include?(event["tool"].to_s)
        end

        def write_event?(event)
          %w[WriteFile write_file StrReplace str_replace AstEdit ast_edit atomic_write].include?(event["tool"].to_s)
        end

        def source_selection_event?(event)
          %w[ReadFile read_file SearchFiles search_files SymbolLookup symbol_lookup].include?(event["tool"].to_s)
        end

        def verification_event?(event)
          tool = event["tool"].to_s
          return true if %w[test scan verify council_call].include?(tool)
          event["command"].to_s.match?(/(?:ruby\s+-c|rake\s+test|bundle\s+exec\s+rake|bin\/check|\/fix\b)/)
        end

        def banned_shell?(command)
          BANNED_SHELL.any? { |word| command.match?(%r{(?:\A|\s|/)(?:#{Regexp.escape(word)})(?:\s|\z|-c\b)}) }
        end
      end
    end
  end
end
