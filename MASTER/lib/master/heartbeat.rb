# frozen_string_literal: true

require "yaml"

module Master
  # Heartbeat — autonomous scheduled task runner.
  # Reads heartbeat.yml for periodic jobs (sweep, model check, prune, self-test).
  # Each job has an interval_seconds and a last_run timestamp persisted in .master/heartbeat_state.yml.
  class Heartbeat
    DATA_PATH  = File.join(Master::ROOT, "data", "heartbeat.yml").freeze
    STATE_PATH = ".master/heartbeat_state.yml".freeze

    def initialize(root:, agent: nil, scanner: nil, memory: nil, event_bus: nil)
      @root    = root
      @agent   = agent
      @scanner = scanner
      @memory  = memory
      @bus     = event_bus
      @jobs    = load_jobs
      @state   = load_state
      @thread  = nil
    end

    def start!
      return if @jobs.empty?

      @thread = Thread.new do
        loop do
          run_due!
          sleep 60
        end
      rescue StandardError => e
        @bus&.publish("heartbeat:error", message: e.message)
      end
    end

    def stop!
      @thread&.kill
      @thread = nil
    end

    def run_due!
      now = Time.now.to_i
      results = []

      @jobs.each do |job|
        name     = job["name"]
        interval = job["interval_seconds"].to_i
        last_run = @state.dig(name, "last_run").to_i

        next unless now - last_run >= interval

        @bus&.publish("heartbeat:run", job: name)
        result = execute_job(job)
        @state[name] = { "last_run" => now, "result" => result.to_s[0, 200] }
        results << { name: name, result: result }
      end

      persist_state unless results.empty?
      results
    end

    def list
      @jobs.map do |job|
        last = @state.dig(job["name"], "last_run").to_i
        ago  = last.zero? ? "never" : "#{(Time.now.to_i - last) / 60}m ago"
        "#{job["name"]}: every #{job["interval_seconds"] / 60}m, last: #{ago}"
      end.join("\n")
    end

    private

    def execute_job(job)
      case job["action"]
      when "prune_memory"
        @memory&.consolidate!(agent: @agent) || "no memory"
      when "check_models"
        check_model_availability
      when "self_test"
        run_self_test
      when "prune_undo"
        prune_undo_journal
      when "snapshot"
        generate_snapshot
      else
        "unknown action: #{job["action"]}"
      end
    rescue StandardError => e
      "error: #{e.message}"
    end

    def check_model_availability
      models_path = File.join(@root, "data", "models.yml")
      return "no models.yml" unless File.exist?(models_path)

      data    = YAML.safe_load_file(models_path, aliases: true)
      tiers   = data["models"] || {}
      ids     = tiers.values.flatten.map { |m| m["id"] }.compact
      alive   = ids.select { |id| model_reachable?(id) }
      "models: #{alive.size}/#{ids.size} reachable"
    end

    def model_reachable?(model_id)
      RubyLLM.chat(model: model_id).ask("ping")
      true
    rescue StandardError
      false
    end

    def run_self_test
      return "no scanner" unless @scanner

      target = File.join(@root, "lib")
      result = @scanner.scan_dir(target, depth: :standard)
      return "scan failed" unless result.respond_to?(:ok?) && result.ok?

      count = result.value!.sum { |_, fr| fr.respond_to?(:ok?) && fr.ok? ? fr.value!.size : 0 }
      @bus&.publish("heartbeat:self_test", violations: count)
      "self-test: #{count} violations"
    end

    def prune_undo_journal
      journal_path = File.join(@root, ".master", "undo.jsonl")
      return "no journal" unless File.exist?(journal_path)

      lines = File.readlines(journal_path)
      return "journal empty" if lines.empty?

      keep = [lines.size / 2, 50].max
      File.write(journal_path, lines.last(keep).join)
      "pruned undo: kept #{keep}/#{lines.size} entries"
    end

    def generate_snapshot
      stamp = Time.now.strftime("%Y%m%d_%H%M%S")
      out   = File.join(@root, ".master", "snapshot.md")
      dirs  = %w[exe lib/master data].map { |d| File.join(@root, d) }
      files = dirs.flat_map { |d| Dir.glob(File.join(d, "**", "*")) }
                  .select { |f| File.file?(f) && File.size(f) < 50_000 }
                  .reject { |f| f.include?("/knowledge/") || f.include?("/vendor/") }
                  .sort
      lines = ["# MASTER Snapshot", "Generated: #{Time.now.utc.iso8601}", "Files: #{files.size}", ""]
      files.each do |f|
        rel  = f.sub("#{@root}/", "")
        lang = Master::FILE_LANGUAGE_MAP.fetch(File.extname(f).downcase, "text")
        src  = File.read(f, encoding: "UTF-8", invalid: :replace)
        lines << "## #{rel}" << "```#{lang}" << src.rstrip << "```" << ""
      rescue StandardError
        next
      end
      File.write(out, lines.join("\n"))
      "snapshot: #{files.size} files -> #{out}"
    end

    def load_jobs
      path = File.join(@root, "data", "heartbeat.yml")
      return default_jobs unless File.exist?(path)

      YAML.safe_load_file(path) || default_jobs
    rescue StandardError
      default_jobs
    end

    def default_jobs
      [
        { "name" => "prune_memory",  "action" => "prune_memory",  "interval_seconds" => 3600 },
        { "name" => "self_test",     "action" => "self_test",     "interval_seconds" => 7200 },
        { "name" => "prune_undo",    "action" => "prune_undo",    "interval_seconds" => 86_400 },
        { "name" => "snapshot",      "action" => "snapshot",      "interval_seconds" => 14_400 }
      ]
    end

    def load_state
      path = File.join(@root, STATE_PATH)
      return {} unless File.exist?(path)

      YAML.safe_load_file(path) || {}
    rescue StandardError
      {}
    end

    def persist_state
      path = File.join(@root, STATE_PATH)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, @state.to_yaml)
    end
  end
end
