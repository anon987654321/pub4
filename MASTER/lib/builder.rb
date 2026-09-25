# frozen_string_literal: true

require "fileutils"
require_relative "builder/boot_phases"
require_relative "builder/ai_boot"
require_relative "fix/rollback"
require_relative "trace/ledger"

module Master
  module Builder
    MUTATING_TOOLS = %w[write_file str_replace ast_edit].freeze
    RING_SIZE = 1000

    # Default tool factories. data/tools.yml overrides them.
    DEFAULT_TOOL_MAP = {
      "ReadFile" => ->(r, i) {
        Io::ReadFile.new(root: r, undo: i[:undo], event_bus: i[:bus], ground_truth: i[:ground_truth])
      },
      "WriteFile" => ->(r, i) {
        Io::WriteFile.new(root: r, undo: i[:undo], governor: i[:governor],
          event_bus: i[:bus], diff_stager: i[:diff_stager], ground_truth: i[:ground_truth])
      },
      "StrReplace" => ->(r, i) {
        Io::StrReplace.new(root: r, undo: i[:undo], governor: i[:governor],
          event_bus: i[:bus], diff_stager: i[:diff_stager], ground_truth: i[:ground_truth])
      },
      "BatchReplace" => ->(r, i) { Io::BatchReplace.new(root: r, governor: i[:governor], event_bus: i[:bus]) },
      "AstEdit" => ->(r, i) {
        Io::AstEdit.new(root: r, undo: i[:undo], governor: i[:governor], event_bus: i[:bus])
      },
      "MemoryRecord" => ->(r, i) { Io::MemoryRecord.new(memory: i[:memory], root: r, event_bus: i[:bus]) },
      "Tree" => ->(r, i) { Io::Tree.new(root: r, event_bus: i[:bus]) },
      "ListDir" => ->(r, i) { Io::ListDir.new(root: r, event_bus: i[:bus]) },
      "SearchFiles" => ->(r, i) { Io::SearchFiles.new(root: r, event_bus: i[:bus]) },
      "SearchKnowledge" => ->(r, i) { Io::SearchKnowledge.new(root: r, event_bus: i[:bus]) },
      "SymbolLookup" => ->(r, i) { Io::SymbolLookup.new(code_index: i[:code_index], event_bus: i[:bus]) },
      "Shell" => ->(r, i) {
        Io::Shell.new(root: r, governor: i[:governor], event_bus: i[:bus], library_verify: i[:library_verify])
      },
      "GitContext" => ->(r, i) { Io::GitContext.new(root: r, event_bus: i[:bus]) },
      "WebFetch" => ->(r, i) { Io::WebFetch.new(governor: i[:governor], event_bus: i[:bus]) },
      "WebSearch" => ->(r, i) { Io::WebSearch.new(governor: i[:governor], event_bus: i[:bus]) },
      "PluginObserve" => ->(_r, i) { Io::PluginObserve.new(governor: i[:governor], event_bus: i[:bus]) },
      "Clean" => ->(r, i) { Io::Clean.new(root: r, governor: i[:governor], event_bus: i[:bus]) },
      "FeedbackRecord" => ->(r, i) { Io::FeedbackRecord.new(learnings: i[:learnings]) },
      "SubdomainOrchestrator" => ->(r, i) {
        Io::SubdomainOrchestrator.new(root: r, event_bus: i[:bus],
          web_fetch: Io::WebFetch.new(governor: i[:governor], event_bus: i[:bus]))
      },
      "DynamicHttp" => ->(_r, i) {
        Io::DynamicHttp.new(governor: i[:governor], event_bus: i[:bus])
      },
    }.freeze

    module_function

    def build(root: Dir.pwd)
      Ground::BootChecks.run(root:)
      Master.configure_providers!
      infra = build_infrastructure(root)
      ai = build_ai(root, infra)
      _pipeline, _gateway, runtime = build_runtime(root:, infra:, ai:)
      runtime
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
      output_guard = Voice::OutputGuard.new
      scanner = build_scanner(root:, bus:)
      code_index = Review::CodeIndex.new(root:, event_bus: bus)
      ai = { scanner:, code_index: }
      infra = trace.merge(config:, boot_config:, renderer:, output_check:, output_guard:, root:)
      commands = CLI::CommandRegistry.build_fast(infra:, ai:, root:)
      agent = fast_agent_stub
      ai[:agent] = agent
      runtime = infra.merge(ai).merge(commands:, scanner:, root:)
      pipeline = CLI::Pipeline::Turn.new(container: runtime)
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
      reach = boot_reach(root:, config:, bus: trace[:bus], governor: loop_c[:governor])
      ground = boot_ground(root:, config:, homeostat: loop_c[:homeostat])
      services = build_analysis_services(root:, config:, trace:, loop_c:, reach:)

      { config:, boot_config: }.merge(services)
        .merge(trace).merge(loop_c).merge(reach).merge(ground)
    end

    def build_analysis_services(root:, config:, trace:, loop_c:, reach:)
      bus = trace[:bus]
      renderer = Voice::Renderer.new(config:)
      output_check = Review::OutputCheck.load(root:)
      # The evidence contract on MASTER's own reply. Built here beside the other
      # output gate rather than reached off the renderer, because a test that
      # hands the pipeline a stub renderer must still get a container it can run.
      output_guard = Voice::OutputGuard.new
      code_index = Review::CodeIndex.new(root:, event_bus: bus)
      code_index.build_async
      reference_graph = Review::ReferenceGraph.new(root:, event_bus: bus)
      ecology = Review::RepoEcology.new(root:, event_bus: bus, code_index:)
      subscribe_ecology_reindex(bus:, ecology:)
      diag = Trace::Diag.new(homeostat: loop_c[:homeostat], breaker: reach[:breaker], logging: trace[:logging], event_bus: bus)
      { renderer:, output_check:, output_guard:, code_index:, reference_graph:, ecology:, diag: }
    end

    def subscribe_ecology_reindex(bus:, ecology:)
      bus.subscribe("tool:after") do |ev|
        next unless ev[:path] && MUTATING_TOOLS.include?(ev[:tool].to_s)
        ecology.reindex(ev[:path])
      end
    end

    def boot_trace(root:, config:)
      TraceBoot.new(root:, config:).call
    end

    def boot_loop(root:, config:, bus:)
      LoopBoot.new(root:, config:, bus:).call
    end

    def boot_reach(root:, config:, bus:, governor:)
      ReachBoot.new(root:, config:, bus:, governor:).call
    end

    def boot_ground(root:, config:, homeostat:)
      GroundBoot.new(root:, config:, homeostat:).call
    end

    def build_tools(root:, infra:)
      path = File.join(root, "data", "tools.yml")
      defs = Master.load_yaml(path)
      return [] unless defs.is_a?(Array)

      registry = ::Master::Builder::DEFAULT_TOOL_MAP
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
      pipeline = CLI::Pipeline::Turn.new(container: runtime)
      runtime = runtime.merge(pipeline:)
      gateway = Io::Gateway.new(pipeline:, session: infra[:session], event_bus: bus, container: runtime)
      commands["gateway"] = ->(_ctx) { gateway.channels }
      runtime = runtime.merge(gateway:)
      [pipeline, gateway, runtime]
    end
  end
end
