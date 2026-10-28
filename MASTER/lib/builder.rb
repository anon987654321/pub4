# frozen_string_literal: true

require "fileutils"
require_relative "builder/boot_phases"
require_relative "builder/ai_boot"
require_relative "trace/ledger"

module Master
  module Builder
    MUTATING_TOOLS = %w[write_file str_replace ast_edit].freeze
    RING_SIZE = 1000
    # AskLlm must be constructed after Review::Agent exists, so ai_boot.rb
    # attaches it explicitly rather than through DEFAULT_TOOL_MAP.
    SPECIAL_TOOL_NAMES = %w[AskLlm].freeze
    TOOL_FIELDS = %w[
      name elevated visitor default description file_types required_context usage_rules error_recovery
    ].freeze
    REQUIRED_TOOL_FIELDS = %w[name elevated visitor default description].freeze

    # Default tool factories. data/tools.yml overrides them.
    DEFAULT_TOOL_MAP = {
      "ReadFile" => ->(r, i) {
        root = i.fetch(:workspace_root, r)
        Io::ReadFile.new(root:, undo: i[:undo], event_bus: i[:bus], ground_truth: i[:ground_truth])
      },
      "WriteFile" => ->(r, i) {
        root = i.fetch(:workspace_root, r)
        Io::WriteFile.new(root:, undo: i[:undo], governor: i[:governor],
          event_bus: i[:bus], diff_stager: i[:diff_stager], ground_truth: i[:ground_truth])
      },
      "DeletePath" => ->(r, i) {
        Io::DeletePath.new(root: i.fetch(:workspace_root, r), undo: i[:undo], governor: i[:governor], event_bus: i[:bus])
      },
      "StrReplace" => ->(r, i) {
        root = i.fetch(:workspace_root, r)
        Io::StrReplace.new(root:, undo: i[:undo], governor: i[:governor],
          event_bus: i[:bus], diff_stager: i[:diff_stager], ground_truth: i[:ground_truth])
      },
      "BatchReplace" => ->(r, i) {
        root = i.fetch(:workspace_root, r)
        Io::BatchReplace.new(root:, governor: i[:governor], event_bus: i[:bus])
      },
      "AstEdit" => ->(r, i) {
        root = i.fetch(:workspace_root, r)
        Io::AstEdit.new(root:, undo: i[:undo], governor: i[:governor], event_bus: i[:bus])
      },
      "MemoryRecord" => ->(r, i) { Io::MemoryRecord.new(memory: i[:memory], root: r, event_bus: i[:bus]) },
      "Tree" => ->(r, i) { Io::Tree.new(root: i.fetch(:workspace_root, r), event_bus: i[:bus]) },
      "ListDir" => ->(r, i) { Io::ListDir.new(root: i.fetch(:workspace_root, r), event_bus: i[:bus]) },
      "SearchFiles" => ->(r, i) { Io::SearchFiles.new(root: i.fetch(:workspace_root, r), event_bus: i[:bus]) },
      "SearchKnowledge" => ->(r, i) { Io::SearchKnowledge.new(root: r, event_bus: i[:bus]) },
      "SymbolLookup" => ->(r, i) { Io::SymbolLookup.new(code_index: i[:code_index], event_bus: i[:bus]) },
      "Shell" => ->(r, i) {
        Io::Shell.new(root: i.fetch(:workspace_root, r), governor: i[:governor], event_bus: i[:bus],
          library_verify: i[:library_verify])
      },
      "GitContext" => ->(r, i) { Io::GitContext.new(root: i.fetch(:workspace_root, r), event_bus: i[:bus]) },
      "WebFetch" => ->(r, i) { Io::WebFetch.new(governor: i[:governor], event_bus: i[:bus]) },
      "WebSearch" => ->(r, i) { Io::WebSearch.new(governor: i[:governor], event_bus: i[:bus]) },
      "HostFiles" => ->(_r, i) { Io::HostFiles.new(governor: i[:governor], event_bus: i[:bus]) },
      "WebBrowse" => ->(_r, i) { Io::WebBrowse.new(governor: i[:governor], event_bus: i[:bus]) },
      "ExternalAudit" => ->(r, i) {
        browser = Io::BrowserAgent.new(root: i.fetch(:workspace_root, r), governor: i[:governor], event_bus: i[:bus])
        Io::ExternalAudit.new(governor: i[:governor], event_bus: i[:bus], browser:)
      },
      "VulCheck" => ->(_r, i) { Io::VulCheck.new(governor: i[:governor], event_bus: i[:bus]) },
      "Nmap" => ->(r, i) { Io::Nmap.new(root: i.fetch(:workspace_root, r), governor: i[:governor], event_bus: i[:bus]) },
      "Browser" => ->(r, i) {
        Io::BrowserAgent.new(root: i.fetch(:workspace_root, r), governor: i[:governor], event_bus: i[:bus])
      },
      "CodePen" => ->(_r, i) { Io::CodePen.new(governor: i[:governor], event_bus: i[:bus]) },
      "Gist" => ->(_r, i) { Io::Gist.new(governor: i[:governor], event_bus: i[:bus]) },
      "YouTubeTranscript" => ->(_r, i) { Io::YoutubeTranscript.new(governor: i[:governor], event_bus: i[:bus]) },
      "GitHubRepoMiner" => ->(_r, i) { Io::GitHubRepoMiner.new(governor: i[:governor], event_bus: i[:bus]) },
      "ArxivResearch" => ->(_r, i) { Io::ArxivResearch.new(governor: i[:governor], event_bus: i[:bus]) },
      "PluginObserve" => ->(_r, i) { Io::PluginObserve.new(governor: i[:governor], event_bus: i[:bus]) },
      "AssistantTasks" => ->(r, i) { Io::AssistantTasks.new(root: r, governor: i[:governor], event_bus: i[:bus]) },
      "CapabilityCatalog" => ->(r, i) { Io::CapabilityCatalog.new(root: r, governor: i[:governor], event_bus: i[:bus]) },
      "Clean" => ->(r, i) { Io::Clean.new(root: i.fetch(:workspace_root, r), governor: i[:governor], event_bus: i[:bus]) },
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

    def workspace_root(root)
      path = File.expand_path(root)
      path == Master::ROOT ? Master::REPO_ROOT : path
    end

    def build(root: Dir.pwd)
      Ground::BootChecks.run(root:)
      Master.configure_providers!
      infra = build_infrastructure(root)
      ai = build_ai(root, infra)
      _pipeline, _gateway, runtime = build_runtime(root:, infra:, ai:)
      runtime
    end

    def warn_config_validation(config)
      return unless config.respond_to?(:validate) && !config.valid?

      config.fetch(:bus) { $stderr }.puts "config validation warnings: #{config.validate.join('; ')}"
    end

    def build_infrastructure(root)
      config = Ground::Config.new(root)
      config["model"] = Master.default_model if config["model"].to_s.empty? || config["model"] == Ground::Config::DEFAULTS["model"]
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
      workspace = workspace_root(root)
      renderer = Voice::Renderer.new(config:)
      output_check = Review::OutputCheck.load(root:)
      # The evidence contract on MASTER's own reply. Built here beside the other
      # output check rather than reached off the renderer, because a test that
      # hands the pipeline a stub renderer must still get a container it can run.
      output_guard = Voice::OutputGuard.new
      code_index = Review::CodeIndex.new(root: workspace, event_bus: bus, persist: true)
      code_index.build_async
      reference_graph = Review::ReferenceGraph.new(root: workspace, event_bus: bus)
      ecology = Review::RepoEcology.new(root: workspace, event_bus: bus, code_index:)
      subscribe_ecology_reindex(bus:, ecology:)
      diag = Trace::Diag.new(homeostat: loop_c[:homeostat], breaker: reach[:breaker], logging: trace[:logging], event_bus: bus)
      { renderer:, output_check:, output_guard:, code_index:, reference_graph:, ecology:, diag:, workspace_root: workspace }
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

    def build_tools(root:, infra:, definitions: nil)
      master_root = Master.master_root(root:)
      if definitions.nil?
        path = File.join(master_root, "data", "tools.yml")
        return [] unless File.file?(path)

        definitions = Master.tools_config(root: master_root)
      end
      validate_tool_catalogue!(definitions)

      registry = ::Master::Builder::DEFAULT_TOOL_MAP
      definitions.filter_map do |definition|
        next unless definition["default"] == true
        # This adapter needs the Agent instance created after the dependency
        # bundle; build_agent_bundle attaches it from SPECIAL_TOOL_NAMES.
        next if SPECIAL_TOOL_NAMES.include?(definition["name"])

        registry.fetch(definition.fetch("name")).call(root, infra)
      end
    end

    def validate_tool_catalogue!(definitions, registry: DEFAULT_TOOL_MAP, special_names: SPECIAL_TOOL_NAMES)
      errors = []
      unless definitions.is_a?(Array) && !definitions.empty?
        raise ArgumentError, "data/tools.yml must be a non-empty list of tool mappings"
      end

      rows = []
      definitions.each_with_index do |definition, index|
        unless definition.is_a?(Hash)
          errors << "row #{index + 1} must be a mapping"
          next
        end

        missing = REQUIRED_TOOL_FIELDS - definition.keys.map(&:to_s)
        errors << "row #{index + 1} is missing #{missing.join(', ')}" unless missing.empty?
        unknown = definition.keys.map(&:to_s) - TOOL_FIELDS
        errors << "row #{index + 1} has unknown field(s): #{unknown.join(', ')}" unless unknown.empty?

        raw_name = definition["name"]
        unless raw_name.is_a?(String) && raw_name.match?(/\A[A-Za-z][A-Za-z0-9]*\z/)
          errors << "row #{index + 1} has invalid name #{raw_name.inspect}"
          next
        end
        name = raw_name
        rows << [name, definition]
        %w[elevated visitor default].each do |field|
          errors << "#{name}.#{field} must be boolean" unless [true, false].include?(definition[field])
        end
        errors << "#{name}.description must be non-empty" unless definition["description"].is_a?(String) && !definition["description"].strip.empty?

        if definition.key?("file_types")
          file_types = definition["file_types"]
          unless file_types.is_a?(Array) && file_types.all? { |value| value.is_a?(String) && value.match?(/\A\.[A-Za-z0-9]+\z/) }
            errors << "#{name}.file_types must be a list of dotted extensions"
          end
        end
        %w[required_context error_recovery].each do |field|
          next unless definition.key?(field)

          errors << "#{name}.#{field} must be non-empty text" unless definition[field].is_a?(String) && !definition[field].strip.empty?
        end
        if definition.key?("usage_rules")
          rules = definition["usage_rules"]
          errors << "#{name}.usage_rules must be a list of non-empty strings" unless
            rules.is_a?(Array) && rules.all? { |rule| rule.is_a?(String) && !rule.strip.empty? }
        end
      end

      names = rows.map(&:first)
      duplicates = names.tally.select { |_name, count| count > 1 }.keys
      errors << "duplicate tool name(s): #{duplicates.sort.join(', ')}" unless duplicates.empty?

      available = (registry.keys + special_names).map(&:to_s).uniq
      unknown_names = names - available
      errors << "tools without a builder: #{unknown_names.sort.join(', ')}" unless unknown_names.empty?
      missing_names = available - names
      errors << "builder tools missing from data/tools.yml: #{missing_names.sort.join(', ')}" unless missing_names.empty?

      raise ArgumentError, "tool catalogue invalid:\n- #{errors.uniq.join("\n- ")}" unless errors.empty?

      true
    end

    def tool_enabled?(definitions, name, missing_default: false)
      row = Array(definitions).find { |entry| entry.is_a?(Hash) && entry["name"].to_s == name.to_s }
      row ? row["default"] == true : missing_default
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
