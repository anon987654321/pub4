# frozen_string_literal: true

module MASTER
  module ToolProtocol
    # ToolProtocol -- self-registering typed tool manifest system
    # Replaces the case/when regex dispatch in ToolDispatch with a governed registry.
    # Each tool declares what it needs; the constitution gates every call.
    # Pattern: MASTER3 Federated Tool Protocol (gistfile10 §1)

    Registration = Struct.new(
      :name,
      :description,
      :usage,
      :required_permissions, # Array of Symbols: [:file_read, :network, :shell]
      :axiom_tags,             # Array of Strings: axioms that govern this tool
      :risk_tier,              # :safe | :guarded | :dangerous
      keyword_init: true,
    )

    @registry = {}
    @registry_mutex = Mutex.new

    class << self
      # Register a tool manifest. Called at require time.
      def register(name, manifest)
        reg = Registration.new(**manifest, name: name.to_sym)
        @registry_mutex.synchronize { @registry[name.to_sym] = reg }
        Logging.dmesg_log("tool0", message: "registered name=#{name} risk=#{reg.risk_tier}") if defined?(Logging)
      end

      # List all registered tool names.
      def tool_names
        @registry_mutex.synchronize { @registry.keys }
      end

      # Get manifest for a tool.
      def manifest(name)
        @registry_mutex.synchronize { @registry[name.to_sym] }
      end

      # Human-readable tool list for LLM system prompts.
      def tool_list_text
        @registry_mutex.synchronize do
          @registry.map { |k, v| "  #{k}: #{v.description} (#{v.risk_tier})" }.join("\n")
        end
      end

      # All tools tagged with a given axiom.
      def tools_for_axiom(axiom_tag)
        @registry_mutex.synchronize do
          @registry.select { |_, v| v.axiom_tags.include?(axiom_tag.to_s) }
        end
      end
    end

    # Register the built-in tools
    [
      [:ask_llm,
       { description: "Ask the LLM a sub-question", usage: 'ask_llm "prompt"', required_permissions: [],
         axiom_tags: ["GUARD_EXPENSIVE"], risk_tier: :guarded }],
      [:web_search,
       { description: "Search the web via DuckDuckGo",     usage: 'web_search "query"',
         required_permissions: [:network], axiom_tags: ["GUARD_EXPENSIVE"], risk_tier: :guarded }],
      [:browse_page,
       { description: "Fetch and read a URL",              usage: 'browse_page "https://..."',
         required_permissions: [:network], axiom_tags: ["GUARD_EXPENSIVE"], risk_tier: :guarded }],
      [:file_read,
       { description: "Read a file",                       usage: 'file_read "path"',
         required_permissions: [:file_read], axiom_tags: ["GUARD", "FAIL_VISIBLY"], risk_tier: :safe }],
      [:file_write,
       { description: "Write content to a file",           usage: 'file_write "path" "content"',
         required_permissions: [:file_write], axiom_tags: ["GUARD", "PRESERVE_THEN_IMPROVE_NEVER_BREAK"], risk_tier: :guarded }],
      [:analyze_code,
       { description: "Analyze Ruby code for issues",      usage: 'analyze_code "path"',
         required_permissions: [:file_read], axiom_tags: ["FAIL_VISIBLY"], risk_tier: :safe }],
      [:fix_code,
       { description: "Auto-fix axiom violations in file", usage: 'fix_code "path"',
         required_permissions: [:file_read, :file_write], axiom_tags: ["PRESERVE_THEN_IMPROVE_NEVER_BREAK"], risk_tier: :guarded }],
      [:shell_command,
       { description: "Run a shell command",               usage: 'shell_command "cmd"',
         required_permissions: [:shell], axiom_tags: ["GUARD", "FAIL_VISIBLY"], risk_tier: :dangerous }],
      [:code_execution,
       { description: "Execute sandboxed Ruby code",       usage: 'code_execution "code"',
         required_permissions: [:shell], axiom_tags: ["GUARD"], risk_tier: :dangerous }],
      [:council_review,
       { description: "Run multi-persona council review",  usage: 'council_review "text"',      required_permissions: [],
         axiom_tags: ["SELF_APPLY"], risk_tier: :guarded }],
      [:memory_search,
       { description: "Search session memories",           usage: 'memory_search "query"',      required_permissions: [],
         axiom_tags: [], risk_tier: :safe }],
      [:self_test,
       { description: "Run introspection/self-test",       usage: "self_test",                  required_permissions: [],
         axiom_tags: ["SELF_APPLY"], risk_tier: :safe }],
    ].each { |name, manifest| register(name, manifest) }
  end
end
