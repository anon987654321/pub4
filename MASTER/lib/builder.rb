# frozen_string_literal: true

require "fileutils"
require_relative "builder/boot_phases"
require_relative "builder/ai_boot"
require_relative "fix/rollback"
require_relative "trace/ledger/feedback"
require_relative "trace/ledger/reflexion"
require_relative "trace/snapshot/publisher"

module Master
  module Builder
    MUTATING_TOOLS = %w[write_file str_replace ast_edit].freeze
    RING_SIZE = 1000

    # Default tool factories. Override via data/tools.yml or register_tool().
    DEFAULT_TOOL_MAP = {
      "ReadFile"        => ->(r, i) {
        Io::ReadFile.new(root: r, undo: i[:undo], event_bus: i[:bus], ground_truth: i[:ground_truth])
      },
      "WriteFile"       => ->(r, i) {
        Io::WriteFile.new(root: r, undo: i[:undo], governor: i[:governor],
          event_bus: i[:bus], diff_stager: i[:diff_stager])
      },
      "StrReplace"      => ->(r, i) {
        Io::StrReplace.new(root: r, undo: i[:undo], governor: i[:governor],
          event_bus: i[:bus], diff_stager: i[:diff_stager])
      },
      "BatchReplace"    => ->(r, i) { Io::BatchReplace.new(root: r, governor: i[:governor], event_bus: i[:bus]) },
      "AstEdit"         => ->(r, i) {
        Io::AstEdit.new(root: r, undo: i[:undo], governor: i[:governor], event_bus: i[:bus])
      },
      "MemoryRecord"    => ->(r, i) { Io::MemoryRecord.new(memory: i[:memory], root: r, event_bus: i[:bus]) },
      "Tree"            => ->(r, i) { Io::Tree.new(root: r, event_bus: i[:bus]) },
      "ListDir"         => ->(r, i) { Io::ListDir.new(root: r, event_bus: i[:bus]) },
      "SearchFiles"     => ->(r, i) { Io::SearchFiles.new(root: r, event_bus: i[:bus]) },
      "SearchKnowledge" => ->(r, i) { Io::SearchKnowledge.new(root: r, event_bus: i[:bus]) },
      "SymbolLookup"    => ->(r, i) { Io::SymbolLookup.new(code_index: i[:code_index], event_bus: i[:bus]) },
      "Shell"           => ->(r, i) {
        Io::Shell.new(root: r, governor: i[:governor], event_bus: i[:bus], library_verify: i[:library_verify])
      },
      "GitContext"      => ->(r, i) { Io::GitContext.new(root: r, event_bus: i[:bus]) },
      "WebFetch"        => ->(r, i) { Io::WebFetch.new(governor: i[:governor], event_bus: i[:bus]) },
      "WebSearch"       => ->(r, i) { Io::WebSearch.new(governor: i[:governor], event_bus: i[:bus]) },
      "Clean"           => ->(r, i) { Io::Clean.new(root: r, governor: i[:governor], event_bus: i[:bus]) },
      "FeedbackRecord"  => ->(r, i) { Io::FeedbackRecord.new(learnings: i[:learnings]) },
      "SubdomainOrchestrator" => ->(r, i) {
        Io::SubdomainOrchestrator.new(root: r, event_bus: i[:bus],
          web_fetch: Io::WebFetch.new(governor: i[:governor], event_bus: i[:bus]))
      },
      "DynamicHttp" => ->(_r, i) {
        Io::DynamicHttp.new(governor: i[:governor], event_bus: i[:bus])
      },
    }.freeze

    @tool_registry = DEFAULT_TOOL_MAP.dup
    @registry_mutex = Mutex.new

    class << self
      # Register a custom tool factory at runtime. Thread-safe.
      def register_tool(name, factory)
        @registry_mutex.synchronize do
          @tool_registry[name.to_s] = factory
        end
      end

      # Unregister a tool. Returns the removed factory or nil.
      def unregister_tool(name)
        @registry_mutex.synchronize do
          @tool_registry.delete(name.to_s)
        end
      end

      def tool_map
        @registry_mutex.synchronize { @tool_registry.dup.freeze }
      end

      # Reset to defaults (useful in tests).
      def reset_tools!
        @registry_mutex.synchronize { @tool_registry = DEFAULT_TOOL_MAP.dup }
      end
    end

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
      code_index = Review::CodeIndex.new(root:, event_bus: bus)
      scanner = build_scanner(root:, bus:)
      trace.merge(config:, boot_config:, code_index:, scanner:, root:)
    end

    def build_fast(root: Dir.pwd)
      Ground::BootChecks.run(root:)
      config = Ground::Config.new(root)
      warn_config_validation(config)
      boot_config = config.freeze_boot
      trace = boot_trace(root:, config:)
      bus = trace[:bus]
      renderer = Voice::Renderer.new(config:)
      output_check = Review::OutputCheck.load(root:)
      scanner = build_scanner(root:, bus:)
      code_index = Review::CodeIndex.new(root:, event_bus: bus)
      ai = { scanner:, code_index: }
      infra = trace.merge(config:, boot_config:, renderer:, output_check:, root:)
      commands = CLI::CommandRegistry.build_fast(infra:, ai:, root:)
      agent = fast_agent_stub
      ai[:agent] = agent
      runtime = infra.merge(ai).merge(commands:, scanner:, root:)
      pipeline = CLI::TurnPipeline.new(container: runtime)
      runtime.merge(pipeline:)
    end

    def warn_config_validation(config)
      return unless config.respond_to?(:validate) && !config.valid?

      config.fetch(:bus) { $stderr }.puts "config validation warnings: #{config.validate.join('; ')}"
    end

    def fast_agent_stub
      Object.new.tap do |stub|
        stub.define_singleton_method(:call) do |_ctx|
          Master::Result.err("fast mode: /status /help only", category: :validation)
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
      services = build_analysis_services(root:, config:, trace:, loop_c:, reach:)

      { config:, boot_config: }.merge(services)
        .merge(trace).merge(loop_c).merge(reach).merge(ground)
    end

    def build_analysis_services(root:, config:, trace:, loop_c:, reach:)
      bus = trace[:bus]
      renderer = Voice::Renderer.new(config:)
      output_check = Review::OutputCheck.load(root:)
      code_index = Review::CodeIndex.new(root:, event_bus: bus)
      code_index.build_async
      reference_graph = Review::ReferenceGraph.new(root:, event_bus: bus)
      ecology = Review::RepoEcology.new(root:, event_bus: bus, code_index:)
      subscribe_ecology_reindex(bus:, ecology:)
      diag = Trace::Diag.new(homeostat: loop_c[:homeostat], breaker: reach[:breaker], logging: trace[:logging], event_bus: bus)
      pressure = PressureEngine.new(event_bus: bus)
      subscribe_pressure_ingest(bus:, pressure:)
      { renderer:, output_check:, code_index:, reference_graph:, ecology:, diag:, pressure: }
    end

    def subscribe_ecology_reindex(bus:, ecology:)
      bus.subscribe("tool:after") do |ev|
        next unless ev[:path] && MUTATING_TOOLS.include?(ev[:tool].to_s)
        ecology.reindex(ev[:path])
      end
    end

    def subscribe_pressure_ingest(bus:, pressure:)
      bus.subscribe("*") do |ev|
        event_name = ev[:event] || ev["event"] || ev[:type] || ev["type"] || "event"
        next if event_name.to_s.start_with?("pressure:")
        pressure.ingest(event: event_name, payload: ev)
      rescue StandardError => e
        Ground::Swallow.log(e, context: "builder.pressure_engine", event_bus: bus)
      end
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

      registry = ::Master::Builder.tool_map
      defs.filter_map do |defn|
        next unless defn["default"] == true
        factory = registry[defn["name"].to_s]
        unless factory
          infra[:bus]&.publish("builder:tool_skipped", tool: defn["name"])
          next
        end
        factory.call(root, infra)
      end
    end

    def build_runtime(root:, infra:, ai:)
      bus = infra[:bus]
      commands = CLI::CommandRegistry.build(infra:, ai:, root:)
      runtime = infra.merge(ai).merge(commands:, root:)
      ai[:standing].wire_container(runtime)
      pipeline = CLI::TurnPipeline.new(container: runtime)
      runtime = runtime.merge(pipeline:)
      gateway = Io::Gateway.new(pipeline:, session: infra[:session], event_bus: bus, container: runtime)
      commands["gateway"] = ->(_ctx) { gateway.channels }
      runtime = runtime.merge(gateway:)
      [pipeline, gateway, runtime]
    end

    def boot_snapshot(container)
      root = container[:root]
      pub = Trace::Snapshot::Publisher
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
