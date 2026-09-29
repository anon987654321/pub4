# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"

module Master
  module AI
    module OperatorContract
      VERSION = 1
      STYLE = "openbsd"
      LANGUAGE = "ruby"
      SHELL = "zsh"
      TREE_DEFAULT_DEPTH = 4
      TREE_DEFAULT_MAX_ENTRIES = 2_000

      module_function

      def prompt
        lines = [
          "MASTER operator ABI v#{VERSION}.",
          "style: #{STYLE}; implementation: #{LANGUAGE}; shell: #{SHELL}",
          "treat the repository like a Unix system: orient, inspect, act, verify",
          "each turn receives a compact live orientation frame; treat it as context, not proof",
          "broad or unfamiliar work: establish the source tree before selecting files",
          "tree is orientation, never proof of file understanding",
          "when the instruction is /fix, follow Master::Fix::Protocol; external agents can consume `MASTER/bin/master --fix-context <target>`",
          "read relevant source systematically; complete where practical, contiguous ranges for large files",
          "file/data parsing and rewriting: Ruby",
          "Ruby subprocesses: argv through Master::Io::Exec; avoid backticks and shell interpolation when argv is enough",
          "shell execution: zsh only; prefer zsh globs and builtins over GNU text pipelines",
          "keep commands readable; one meaningful operation per line; use && only for a real dependency",
          "never claim success without observable verification",
          "failure is explicit: unknown, unmeasured, blocked, and failed are distinct states",
          "human output has four layers: conversation, result, state, diagnostic; raw telemetry never masquerades as prose",
          "context has typed layers: conversation and task are primary; state and telemetry stay out of model context unless explicitly needed",
          "MASTER owns its constitution; RAILS and OPENBSD retain their own base-tree contracts and dialects",
          "child agents inherit the same contract and may not spawn recursively"
        ]
        banned = zsh_banned_commands
        lines << "banned zsh commands: #{banned.join(", ")}" unless banned.empty?
        lines.join("\n")
      rescue StandardError => e
        "MASTER operator ABI unavailable: #{e.class}: #{e.message}"
      end

      def zsh_banned_commands
        Array(Master.law("zsh").fetch("banned_commands", [])).map(&:to_s).sort
      rescue StandardError
        []
      end

      def manifest
        {
          "version" => VERSION,
          "style" => STYLE,
          "language" => LANGUAGE,
          "shell" => SHELL,
          "orientation" => "tree_first",
          "verification" => "evidence_before_completion",
          "subprocess" => "argv_via_Master::Io::Exec",
          "training" => {
            "teacher_distillation" => true,
            "supervised_finetuning" => true,
            "preference_learning" => true,
            "reinforcement_learning" => true
          }
        }
      end
    end

    module Orientation
      VERSION = 1
      DEFAULT_DEPTH = 2
      MAX_ENTRIES = 80
      SKIP = %w[.git .bundle vendor node_modules tmp log coverage storage .master knowledge output sockets pids cache].freeze

      module_function

      def render(root:, target: nil, depth: DEFAULT_DEPTH, max_entries: MAX_ENTRIES)
        root = File.realpath(root)
        repo_root = File.basename(root) == "MASTER" ? File.expand_path("..", root) : root
        parts = [
          "MASTER orientation v#{VERSION}",
          "repo: #{repo_root}",
          "target: #{target ? relative(target, repo_root) : relative(root, repo_root)}",
          "contract: orient → inspect → act → verify",
          "verification: evidence before completion",
          "trees: MASTER, RAILS, OPENBSD; STUDIO = MASTER/tools",
          "head: #{git_head(repo_root)}",
          "docs: #{key_docs(repo_root).join(", ")}",
        ]

        plan = active_plan(root)
        parts << "active plan: #{compact(plan)}" unless plan.to_s.empty?
        wishes = pending_wishes(root)
        parts << "pending wishes: #{wishes.join(", ")}" unless wishes.empty?
        parts << "tree:"
        parts.concat(tree_lines(root, depth:, max_entries:))
        parts.join("\n")
      rescue StandardError => e
        "MASTER orientation unavailable: #{e.class}: #{e.message}"
      end

      def tree_lines(root, depth:, max_entries:)
        seen = 0
        truncated = false
        lines = []
        walk = lambda do |dir, indent, level|
          return if level > depth || truncated

          Dir.children(dir).sort_by do |name|
            path = File.join(dir, name)
            [File.directory?(path) ? 0 : 1, name]
          end.each do |name|
            break if seen >= max_entries
            next if SKIP.include?(name)

            path = File.join(dir, name)
            seen += 1
            lines << "#{indent}#{name}#{File.directory?(path) ? "/" : ""}"
            walk.call(path, "#{indent}  ", level + 1) if File.directory?(path)
          end
          truncated = true if seen >= max_entries
        end

        lines << "#{File.basename(root)}/"
        walk.call(root, "", 0)
        lines << "... (orientation tree truncated)" if truncated
        lines
      end

      def active_plan(root)
        path = File.join(root, "runtime", "active_plan.md")
        return unless File.file?(path)
        File.read(path, encoding: "UTF-8")[0, 900].strip
      end

      def pending_wishes(root)
        path = File.join(root, "runtime", "wishlist.md")
        return [] unless File.file?(path)
        File.readlines(path, encoding: "UTF-8", chomp: true)
            .grep(/\A###? \d+\./)
            .first(5)
            .map { |line| line.sub(/\A###? /, "").strip }
      end

      def key_docs(repo_root)
        %w[CLAUDE.md TREE.md TODO.md].select { |name| File.file?(File.join(repo_root, name)) }
      end

      def git_head(repo_root)
        git = File.join(repo_root, ".git")
        head = if File.file?(git)
          git_dir = File.read(git).strip.sub(/\Agitdir:\s*/, "")
          File.read(File.expand_path("HEAD", File.join(File.dirname(git), git_dir)))
        elsif File.directory?(git)
          File.read(File.join(git, "HEAD"))
        end
        head.to_s.strip.delete_prefix("ref: ").split("/").last || "unknown"
      rescue StandardError
        "unknown"
      end

      def relative(path, repo_root)
        full = File.expand_path(path)
        return "." if full == repo_root
        return path.to_s unless full.start_with?("#{repo_root}/")
        full.delete_prefix("#{repo_root}/")
      end

      def compact(text, limit = 500)
        body = text.to_s.gsub(/\s+/, " ").strip
        body.length > limit ? "#{body[0, limit - 1]}…" : body
      end

      def digest(root:)
        Digest::SHA256.hexdigest(render(root:))[0, 16]
      end
    end

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
          BANNED_SHELL.any? { |word| command.match?(%r{(?:\A|\s|/)(?:#{Regexp.escape(word)})(?:\s|\z|-c\b)})
        end
      end

      module Dataset
        SCHEMA = "master.llm.sft/v1"

        module_function

        def export(input:, output:)
          FileUtils.mkdir_p(File.dirname(output))
          count = 0
          File.open(output, "w") do |out|
            File.foreach(input) do |line|
              next if line.strip.empty?
              record = JSON.parse(line)
              score = Benchmark.score(record)
              next unless score["verified"]
              out.puts(JSON.generate(
                "schema" => SCHEMA,
                "messages" => messages_for(record),
                "trajectory" => record["events"],
                "score" => score,
                "outcome" => record["outcome"]
              ))
              count += 1
            rescue JSON::ParserError
              next
            end
          end
          count
        end

        def export_preferences(input:, output:)
          records = File.foreach(input).filter_map do |line|
            next if line.strip.empty?
            JSON.parse(line)
          rescue JSON::ParserError
            nil
          end
          grouped = records.group_by { |record| record["task"].to_s }
          count = 0
          FileUtils.mkdir_p(File.dirname(output))
          File.open(output, "w") do |out|
            grouped.each_value do |group|
              chosen = group.find { |record| Benchmark.score(record)["verified"] }
              rejected = group.find { |record| !Benchmark.score(record)["verified"] }
              next unless chosen && rejected
              out.puts(JSON.generate(
                "schema" => "master.llm.preference/v1",
                "task" => chosen["task"],
                "chosen" => chosen["events"],
                "rejected" => rejected["events"]
              ))
              count += 1
            end
          end
          count
        end

        def messages_for(record)
          [
            { "role" => "system", "content" => Master::AI::OperatorContract.prompt },
            { "role" => "user", "content" => record["task"].to_s },
            { "role" => "assistant", "content" => JSON.generate(record["events"]) }
          ]
        end
      end

      class Record
        SCHEMA = "master.llm.trajectory/v1"
        REQUIRED = %w[task model events outcome verified].freeze
        attr_reader :data

        def initialize(data)
          @data = normalize(data)
          validate!
        end

        def normalize(value)
          hash = value.is_a?(Hash) ? value.dup : {}
          hash["schema"] = SCHEMA
          hash["task"] = hash.fetch("task", "").to_s
          hash["model"] = hash.fetch("model", "").to_s
          hash["events"] = Array(hash["events"]).map { |event| event.is_a?(Hash) ? stringify(event) : { "event" => event.to_s } }
          hash["outcome"] = hash.fetch("outcome", "unknown").to_s
          hash["verified"] = hash.fetch("verified", false) == true
          hash["recorded_at"] ||= Time.now.utc.iso8601
          hash
        end

        def validate!
          missing = REQUIRED.reject { |key| @data.key?(key) }
          raise ArgumentError, "trajectory record missing: #{missing.join(", ")}" unless missing.empty?
          raise ArgumentError, "trajectory task is empty" if @data["task"].empty?
          raise ArgumentError, "trajectory events are empty" if @data["events"].empty?
        end

        def score = Benchmark.score(@data)

        def append!(path)
          FileUtils.mkdir_p(File.dirname(path))
          File.open(path, "a") do |io|
            io.flock(File::LOCK_EX)
            io.puts(JSON.generate(@data))
            io.flush
            io.flock(File::LOCK_UN)
          end
          self
        end

        private

        def stringify(hash)
          hash.each_with_object({}) do |(key, value), out|
            out[key.to_s] = value.is_a?(Hash) ? stringify(value) : value
          end
        end
      end
    end
  end
end
