# frozen_string_literal: true

require "fileutils"
require_relative "builder/boot_phases"
require_relative "builder/ai_boot"
require_relative "loop/rollback"
require_relative "trace/feedback_ledger"
require_relative "trace/reflexion_ledger"
require_relative "trace/snapshot_publisher"

module Master
  module Builder
    MUTATING_TOOLS = %w[write_file str_replace ast_edit].freeze
    RING_SIZE          = 1000

    TOOL_MAP = {
      "ReadFile"        => ->(r, i) {
        Reach::ReadFile.new(root: r, undo: i[:undo], event_bus: i[:bus], ground_truth: i[:ground_truth])
      },
      "WriteFile"       => ->(r, i) {
        Reach::WriteFile.new(root: r, undo: i[:undo], governor: i[:governor],
          event_bus: i[:bus], diff_stager: i[:diff_stager])
      },
      "StrReplace"      => ->(r, i) {
        Reach::StrReplace.new(root: r, undo: i[:undo], governor: i[:governor],
          event_bus: i[:bus], diff_stager: i[:diff_stager])
      },
      "BatchReplace"    => ->(r, i) { Reach::BatchReplace.new(root: r, governor: i[:governor], event_bus: i[:bus]) },
      "AstEdit"         => ->(r, i) {
        Reach::AstEdit.new(root: r, undo: i[:undo], governor: i[:governor], event_bus: i[:bus])
      },
      "MemoryRecord"    => ->(r, i) { Reach::MemoryRecord.new(memory: i[:memory], root: r, event_bus: i[:bus]) },
      "Tree"            => ->(r, i) { Reach::Tree.new(root: r, event_bus: i[:bus]) },
      "ListDir"         => ->(r, i) { Reach::ListDir.new(root: r, event_bus: i[:bus]) },
      "SearchFiles"     => ->(r, i) { Reach::SearchFiles.new(root: r, event_bus: i[:bus]) },
      "SearchKnowledge" => ->(r, i) { Reach::SearchKnowledge.new(root: r, event_bus: i[:bus]) },
      "SymbolLookup"    => ->(r, i) { Reach::SymbolLookup.new(code_index: i[:code_index], event_bus: i[:bus]) },
      "Shell"           => ->(r, i) {
        Reach::Shell.new(root: r, governor: i[:governor], event_bus: i[:bus], library_verify: i[:library_verify])
      },
      "GitContext"      => ->(r, i) { Reach::GitContext.new(root: r, event_bus: i[:bus]) },
      "WebFetch"        => ->(r, i) { Reach::WebFetch.new(governor: i[:governor], event_bus: i[:bus]) },
      "WebSearch"       => ->(r, i) { Reach::WebSearch.new(governor: i[:governor], event_bus: i[:bus]) },
      "Clean"           => ->(r, i) { Reach::Clean.new(root: r, governor: i[:governor], event_bus: i[:bus]) },
      "FeedbackRecord"  => ->(r, i) { Reach::FeedbackRecord.new(learnings: i[:learnings]) },
      "SubdomainOrchestrator" => ->(r, i) {
        Reach::SubdomainOrchestrator.new(root: r, event_bus: i[:bus],
          web_fetch: Reach::WebFetch.new(governor: i[:governor], event_bus: i[:bus]))
      },
    }.freeze

    module_function

    def build(root: Dir.pwd)
      Ground::BootChecks.run(root:)
      Master.configure_providers!
      infra = build_infrastructure(root)
      ai    = build_ai(root, infra)
      _pipeline, _gateway, runtime = build_runtime(root:, infra:, ai:)
      runtime
    end

    def build_scan_only(root: Dir.pwd)
      Ground::BootChecks.run(root:)
      config = Ground::Config.new(root)
      boot_config = config.freeze_boot
      trace = boot_trace(root:, config:)
      bus = trace[:bus]
      code_index = Judge::CodeIndex.new(root:, event_bus: bus)
      scanner = build_scanner(root:, bus:)
      trace.merge(config:, boot_config:, code_index:, scanner:, root:)
    end

    def build_fast(root: Dir.pwd)
      Ground::BootChecks.run(root:)
      config = Ground::Config.new(root)
      boot_config = config.freeze_boot
      trace = boot_trace(root:, config:)
      bus = trace[:bus]
      renderer = Voice::Renderer.new(config:)
      output_check = Judge::OutputCheck.load(root:)
      scanner = build_scanner(root:, bus:)
      code_index = Judge::CodeIndex.new(root:, event_bus: bus)
      ai = { scanner:, code_index: }
      infra = trace.merge(config:, boot_config:, renderer:, output_check:, root:)
      commands = Now::CommandRegistry.build_fast(infra:, ai:, root:)
      agent = fast_agent_stub
      ai[:agent] = agent
      runtime = infra.merge(ai).merge(commands:, scanner:, root:)
      pipeline = Now::TurnPipeline.new(container: runtime)
      runtime.merge(pipeline:)
    end

    def fast_agent_stub
      Object.new.tap do |stub|
        stub.define_singleton_method(:call) do |_ctx|
          Master::Result.err("fast mode: /status /orient /tools /help only", category: :validation)
        end
        stub.define_singleton_method(:model) { "fast" }
      end
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
      output_check = Judge::OutputCheck.load(root:)
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

      { config:, boot_config:, renderer:, output_check:, code_index:, reference_graph:, ecology:, diag:, pressure: }
        .merge(trace).merge(loop_c).merge(reach).merge(ground)
    end

    def boot_trace(root:, config:)
      TraceBoot.new(root:, config:).call
    end

    def boot_loop(root:, config:, bus:)
      LoopBoot.new(root:, config:, bus:).call
    end

    def boot_reach(root:, config:, bus:)
      ReachBoot.new(root:, config:, bus:).call
    end

    def boot_ground(root:, config:, homeostat:)
      GroundBoot.new(root:, config:, homeostat:).call
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

    def build_runtime(root:, infra:, ai:)
      bus = infra[:bus]
      commands = Now::CommandRegistry.build(infra:, ai:, root:)
      runtime = infra.merge(ai).merge(commands:, root:)
      ai[:standing].wire_container(runtime)
      pipeline = Now::TurnPipeline.new(container: runtime)
      runtime = runtime.merge(pipeline:)
      gateway = Reach::Gateway.new(pipeline:, session: infra[:session], event_bus: bus, container: runtime)
      commands["gateway"] = ->(_ctx) { gateway.channels }
      runtime = runtime.merge(gateway:)
      [pipeline, gateway, runtime]
    end

    def boot_snapshot(container)
      root = container[:root]
      pub = Trace::SnapshotPublisher
      out = File.join(root, ".master", "snapshot.md")
      if pub.boot_current?(root, out)
        container[:bus]&.publish("boot:snapshot_skipped")
        return
      end
      content = pub.boot_light(root)
      FileUtils.mkdir_p(File.dirname(out))
      File.write(out, content)
      container[:bus]&.publish("boot:snapshot")
    rescue StandardError => e
      container[:bus]&.publish("boot:snapshot_error", error: e.message)
    end
  end
end
