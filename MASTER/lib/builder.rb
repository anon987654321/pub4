# frozen_string_literal: true

require "fileutils"
require_relative "builder/boot_phases"
require_relative "builder/ai_boot"
require_relative "loop/rollback"
require_relative "trace/feedback_ledger"
require_relative "trace/reflexion_ledger"

module Master
  module Builder
    MUTATING_TOOLS = %w[write_file str_replace ast_edit].freeze
    RING_SIZE          = 1000
    SNAPSHOT_MAX_BYTES = 50_000
    SNAPSHOT_DIRS      = %w[bin lib data].freeze

    TOOL_MAP = {
      "ReadFile" => ->(r, i) {
        Reach::ReadFile.new(root: r, undo: i[:undo], event_bus: i[:bus], ground_truth: i[:ground_truth])
      },
      "WriteFile" => ->(r, i) {
        Reach::WriteFile.new(root: r, undo: i[:undo], governor: i[:governor],
          event_bus: i[:bus], diff_stager: i[:diff_stager])
      },
      "StrReplace" => ->(r, i) {
        Reach::StrReplace.new(root: r, undo: i[:undo], governor: i[:governor],
          event_bus: i[:bus], diff_stager: i[:diff_stager])
      },
      "BatchReplace" => ->(r, i) {
        Reach::BatchReplace.new(root: r, governor: i[:governor], event_bus: i[:bus])
      },
      "AstEdit" => ->(r, i) {
        Reach::AstEdit.new(root: r, undo: i[:undo], governor: i[:governor], event_bus: i[:bus])
      },
      "Tree" => ->(r, i) { Reach::Tree.new(root: r, event_bus: i[:bus]) },
      "ListDir" => ->(r, i) { Reach::ListDir.new(root: r, event_bus: i[:bus]) },
      "SearchFiles" => ->(r, i) { Reach::SearchFiles.new(root: r, event_bus: i[:bus]) },
      "SearchKnowledge" => ->(r, i) { Reach::SearchKnowledge.new(root: r, event_bus: i[:bus]) },
      "SymbolLookup" => ->(r, i) {
        Reach::SymbolLookup.new(code_index: i[:code_index], event_bus: i[:bus])
      },
      "Shell" => ->(r, i) { Reach::Shell.new(root: r, governor: i[:governor], event_bus: i[:bus]) },
      "GitContext" => ->(r, i) { Reach::GitContext.new(root: r, event_bus: i[:bus]) },
      "WebFetch" => ->(r, i) { Reach::WebFetch.new(governor: i[:governor], event_bus: i[:bus]) },
      "WebSearch" => ->(r, i) { Reach::WebSearch.new(governor: i[:governor], event_bus: i[:bus]) },
      "Clean" => ->(r, i) { Reach::Clean.new(root: r, governor: i[:governor], event_bus: i[:bus]) },
      "FeedbackRecord" => ->(r, i) { Reach::FeedbackRecord.new(learnings: i[:learnings]) },
      "MemoryRecord" => ->(r, i) {
        Reach::MemoryRecord.new(memory: i[:memory], root: r, event_bus: i[:bus])
      },
    }.freeze

    module_function

    def build(root: Dir.pwd)
      Master.configure_providers!
      infra = build_infrastructure(root)
      ai    = build_ai(root, infra)
      pipeline, gateway = build_pipeline(root: root, infra: infra, ai: ai)
      infra.merge(ai).merge(pipeline:, gateway:, root:)
    end

    def build_scan_only(root: Dir.pwd)
      config = Ground::Config.new(root)
      boot_config = config.freeze_boot
      trace = boot_trace(root:, config:)
      bus = trace[:bus]
      code_index = Judge::CodeIndex.new(root:, event_bus: bus)
      scanner = build_scanner(root:, bus:)
      trace.merge(config:, boot_config:, code_index:, scanner:, root:)
    end

    def build_infrastructure(root)
      config = Ground::Config.new(root)
      config["model"] ||= Master.default_model
      boot_config = config.freeze_boot
      trace = boot_trace(root:, config:)
      loop_c = boot_loop(root:, config:, bus: trace[:bus])
      reach = boot_reach(root:, config:, bus: trace[:bus])
      ground = boot_ground(root:, config:, homeostat: loop_c[:homeostat])

      bus = trace[:bus]
      renderer = Voice::Renderer.new(config:)
      code_index = Judge::CodeIndex.new(root:, event_bus: bus)
      code_index.build_async
      reference_graph = Judge::ReferenceGraph.new(root:, event_bus: bus)
      ecology = Judge::RepoEcology.new(root:, event_bus: bus, code_index:)
      bus.subscribe("tool:after") do |ev|
        next unless ev[:path] && MUTATING_TOOLS.include?(ev[:tool].to_s)
        ecology.reindex(ev[:path])
      end
      diag = Trace::Diag.new(homeostat: loop_c[:homeostat], breaker: reach[:breaker], logging: trace[:logging], event_bus: bus)
      pressure = PressureEngine.new(event_bus: bus)
      bus.subscribe("*") do |ev|
        event_name = ev[:event] || ev["event"] || ev[:type] || ev["type"] || "event"
        next if event_name.to_s.start_with?("pressure:")
        pressure.ingest(event: event_name, payload: ev)
      rescue StandardError => e
        Ground::Swallow.log(e, context: "builder.pressure_engine", event_bus: bus)
      end

      { config:, boot_config:, renderer:, code_index:, reference_graph:, ecology:, diag:, pressure: }
        .merge(trace).merge(loop_c).merge(reach).merge(ground)
    end

    def boot_trace(root:, config:)
      TraceBoot.new(root: root, config: config).call
    end

    def boot_loop(root:, config:, bus:)
      LoopBoot.new(root: root, config: config, bus: bus).call
    end

    def boot_reach(root:, config:, bus:)
      ReachBoot.new(root: root, config: config, bus: bus).call
    end

    def boot_ground(root:, config:, homeostat:)
      GroundBoot.new(root: root, config: config, homeostat: homeostat).call
    end

    def build_tools(root:, infra:)
      path = File.join(root, "data", "tools.yml")
      defs = Master.load_yaml(path)
      return [] unless defs.is_a?(Array)

      defs.filter_map do |defn|
        next unless defn["default"] == true
        factory = TOOL_MAP[defn["name"].to_s]
        unless factory
          infra[:bus]&.publish("builder:tool_skipped", tool: defn["name"])
          next
        end
        factory.call(root, infra)
      end
    end

    def build_pipeline(root:, infra:, ai:)
      config = infra[:config]
      bus = infra[:bus]
      commands = Now::CommandRegistry.build(infra:, ai:, root:)
      stages = [
        Now::Stages::Intake.new,
        Now::Stages::Enhance.new(agent: ai[:agent], event_bus: bus, skills: ai[:skills]),
        Now::Stages::Infer.new(bus:, session: infra[:session]),
        Now::Stages::Route.new(commands:, agent: ai[:agent], bus:),
        Now::Stages::Guard.new(governor: infra[:governor], injection_guard: ai[:guard]),
        Now::Stages::Deliberate.new(agent: ai[:agent], config:),
        Now::Stages::Execute.new,
        Now::Pipeline::SkipOnPressure.new(
          Now::Stages::Review.new(council: ai[:council_stage], scanner: ai[:scanner], config:, root:, event_bus: bus),
          bus:
        ),
        Now::Stages::Memory.new(memory: infra[:memory], event_bus: bus),
        Now::Stages::Render.new(renderer: infra[:renderer]),
      ]
      pipeline = Now::Pipeline.new(stages, bus:, trace: config["trace_pipeline"] == true, root:, scanner: ai[:scanner])
      ai[:standing].wire_pipeline(pipeline)
      gateway = Reach::Gateway.new(pipeline:, session: infra[:session], event_bus: bus)
      commands["gateway"] = ->(_ctx) { gateway.channels }
      [pipeline, gateway]
    end

    def boot_snapshot(container)
      root = container[:root]
      files = Dir[*SNAPSHOT_DIRS.map { |d| File.join(root, d, "**", "*") }]
        .select { |f| File.file?(f) && File.size(f) < SNAPSHOT_MAX_BYTES }
        .reject { |f| f.include?("/knowledge/") || f.include?("/vendor/") }
        .sort
      out = File.join(root, ".master", "snapshot.md")
      public_out = File.join(root, "snapshot.md")
      if snapshot_current?(files, out, public_out)
        container[:bus]&.publish("boot:snapshot_skipped", files: files.size)
        return
      end
      body = files.flat_map do |f|
        rel = f.delete_prefix("#{root}/")
        lang = Master::FILE_LANGUAGE_MAP.fetch(File.extname(f).downcase, "text")
        src = File.read(f, encoding: "UTF-8", invalid: :replace)
        ["## #{rel}", "```#{lang}", src.rstrip, "```", ""]
      rescue StandardError => e
        Ground::Swallow.log(e, context: "builder.snapshot_file", path: f)
        []
      end
      header = ["# MASTER Snapshot", "Generated: #{Time.now.utc.iso8601}", "Files: #{files.size}", ""]
      root_snapshots = snapshot_artifacts(root)
      content = (header + root_snapshots + body).join("\n")
      FileUtils.mkdir_p(File.dirname(out))
      File.write(out, content)
      File.write(public_out, content)
      container[:bus]&.publish("boot:snapshot", files: files.size)
    rescue StandardError => e
      container[:bus]&.publish("boot:snapshot_error", error: e.message)
    end

    def snapshot_artifacts(root)
      paths = %w[MASTER_snapshot.md DEPLOY_snapshot.md].filter_map do |name|
        path = File.join(root, name)
        next unless File.file?(path)
        "- `#{name}` (#{File.size(path)} bytes, updated #{File.mtime(path).utc.iso8601})"
      end
      return [] if paths.empty?

      ["## Root snapshot artifacts", *paths, ""]
    end

    def snapshot_current?(files, *outputs)
      return false if files.empty?
      return false unless outputs.all? { |path| File.exist?(path) }

      newest_source = files.map { |path| File.mtime(path) }.max
      oldest_output = outputs.map { |path| File.mtime(path) }.min
      oldest_output >= newest_source
    rescue StandardError
      false
    end
  end
end
