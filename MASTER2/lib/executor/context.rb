# frozen_string_literal: true

module MASTER
  # ExecutionContext - extracted from Executor::Context for module-level access
  module ExecutionContext
    SIMPLE_SECTIONS = %w[personality capabilities architecture environment shell_patterns behavior].freeze
    LABELED_SECTIONS = {
      "task_workflow" => "TASK WORKFLOW",
      "safety" => "SAFETY",
      "critical_axioms" => "CORE AXIOMS",
      "anti_simulation" => "EVIDENCE RULES",
    }.freeze

    # Class-level depth: :shallow (default) | :own | :deep | :full
    # Set to :own before evolve/selftest/chamber for grounded context.
    @current_depth = :shallow
    def self.current_depth; @current_depth; end
    def self.current_depth=(d); @current_depth = d; end

    def self.system_prompt_config
      @system_prompt_config ||= if File.exist?(MASTER::Executor::SYSTEM_PROMPT_FILE)
                                  begin
                                    YAML.safe_load_file(MASTER::Executor::SYSTEM_PROMPT_FILE)
                                  rescue StandardError => err
                                    if defined?(MASTER::Logging)
                                      MASTER::Logging.warn("executor.context",
                                                           "Failed to load system prompt: #{err.message}")
                                    end
                                    {}
                                  end
                                else
                                  {}
                                end
    end

    # Build comprehensive system message with all YAML sections + persona
    # depth: :shallow (default) | :own | :deep | :full -- controls source injection
    def self.build_system_message(include_commands: true, depth: :shallow)
      config = system_prompt_config

      # Identity (interpolated)
      identity = if config["identity"]
                   begin
                     format(config["identity"], version: MASTER::VERSION, platform: RUBY_PLATFORM, ruby_version: RUBY_VERSION,
                                                working_dir: Dir.pwd, hypervisor: PlatformCheck.hypervisor,
                                                provider: PlatformCheck.provider,
                                                openbsd_version: PlatformCheck.openbsd_version || RUBY_PLATFORM)
                   rescue KeyError, ArgumentError
                     config["identity"]
                   end
                 else
                   "You are MASTER v#{MASTER::VERSION}, an autonomous coding assistant."
                 end

      sections = [identity]

      # Add simple sections
      SIMPLE_SECTIONS.each { |key| sections << config[key] if config[key] }

      # Add labeled sections
      LABELED_SECTIONS.each do |key, label|
        sections << "#{label}:\n#{config[key]}" if config[key]
      end

      # Commands (optional)
      if include_commands
        commands = config["commands"] || <<~CMD
          YOU ARE INSIDE THE MASTER2 REPL. Type: ask, scan, fix, refactor, evolve, hunt, model, help, exit
          NEVER suggest shell flags like --apply or --exec. You are already inside master.
        CMD
        sections << commands
      end

      # Check for active persona
      if defined?(LLM) && LLM.respond_to?(:persona_prompt)
        persona_prompt = LLM.persona_prompt
        sections << "\nACTIVE PERSONA:\n#{persona_prompt}" if persona_prompt && !persona_prompt.empty?
      end

      # Inject user-pinned context note (set via `context pin <text>`)
      if defined?(Session)
        pin = Session.current.metadata_value(:context_pin)
        sections << "PINNED CONTEXT:\n#{pin}" if pin && !pin.empty?
      end

      # Inject working directory file tree (depth 2, compact)
      tree = dir_snapshot(Dir.pwd, max_depth: 2)
      sections << "WORKING DIRECTORY:\n#{tree}" unless tree.empty?

      # Check for project-specific MASTER.md
      master_md = File.join(Dir.pwd, "MASTER.md")
      sections << "PROJECT CONTEXT (from MASTER.md):\n#{File.read(master_md)[0..2000]}" if File.exist?(master_md)

      # Persistent project memory -- goal, stack, recent decisions across all sessions/models
      if defined?(ProjectMemory)
        mem = ProjectMemory.inject(root: Dir.pwd)
        sections << mem unless mem.empty?
      end

      # Gist #9: Inject detected project conventions so LLM mimics existing style
      conventions = begin
        ConventionExtractor.extract(root: MASTER.root)
      rescue StandardError
        ""
      end
      sections << conventions unless conventions.empty?

      # Inject top-5 highest-priority axioms so every LLM call has them on the hot path
      if defined?(MASTER::Review::Constitution)
        begin
          top_axioms = MASTER::Review::Constitution.axioms
                         .select { |a| (a["id"] || a["name"]) && (a["statement"] || a["description"]) }
                         .sort_by { |a| -(a["priority"] || 5) }
                         .first(10)
          unless top_axioms.empty?
            axiom_lines = top_axioms.map { |a| "#{a['id'] || a['name']}: #{a['statement'] || a['description']}" }.join("\n")
            sections << "ACTIVE AXIOMS (highest priority):\n#{axiom_lines}"
          end
        rescue StandardError
          nil
        end
      end

      # Inject full platform.yml so OpenBSD rules are always present
      platform_file = Paths.data_file("platform.yml")
      if File.exist?(platform_file)
        sections << "PLATFORM RULES (OpenBSD):\n#{File.read(platform_file)}"
      end

      # Inject violated axioms from previous response so LLM self-corrects
      if (violated_ids = Thread.current[:last_axiom_violations])&.any? && defined?(MASTER::Review::Constitution)
        begin
          all_axioms = MASTER::Review::Constitution.axioms
          texts = violated_ids.filter_map do |id|
            all_axioms.find { |a| (a["id"] || a["name"]) == id }
          end
          if texts.any?
            detail = texts.map { |a| "#{a['id'] || a['name']}: #{a['statement'] || a['description']}" }.join("\n")
            sections << "VIOLATED AXIOMS (self-correct in your next response):\n#{detail}"
          end
        rescue StandardError
          nil
        end
      end

      # Zsh native patterns: forbid legacy forks in shell code
      sections << ZshPatternInjector.prompt_section

      # Strunk & White -- every LLM system message
      sections << <<~SW
        PROSE STYLE -- ELEMENTS OF STYLE (Strunk & White):
        Omit needless words. Every identifier, comment, error message, and string earns its place or is cut.
        Name things by what they ARE: axiom_list not data; violation_count not value; model_name not info.
        Use the active voice: "Enforcer rejected X" not "X was rejected". Methods are active verbs: enforce, scan, reflow.
        Never use: basically, essentially, actually, simply, really, quite, very in prose.
        Comments explain WHY, never WHAT. Error messages: [actor] [verb] [noun]: [specific detail].
        Read-aloud test: mentally read your output. If it flows as natural English, it is well-structured.
      SW

      # Exemplars -- positive models from the registry
      if defined?(BeautyScorer)
        ex = BeautyScorer.exemplars_prompt(max: 3)
        sections << ex unless ex.empty?
      end

      # Grounded source injection -- depth :own/:deep/:full loads real source files
      if depth != :shallow && defined?(GroundedContext)
        grounded = GroundedContext.build(depth: depth, root: MASTER.root)
        sections << grounded unless grounded.empty?
      end

      sections.join("\n\n")
    end

    # Build task context (tools + format + history) -- template loaded from data/prompts/react.yml
    def build_task_context(goal)
      history_text = @history.map do |h|
        obs = h[:observation]&.[](0..400)
        # Mark tool results as untrusted to prevent prompt injection via tool output
        obs_line = obs ? "[Tool Result - Untrusted] #{obs}" : nil
        "Step #{h[:step]}:\nThought: #{h[:thought]}\nAction: #{h[:action]}#{"\nObservation: #{obs_line}" if obs_line}"
      end.join("\n\n")

      tool_list   = Executor.tool_list_text
      tool_format = Executor::TOOLS.map { |_k, v| "- #{v[:usage]}" }.join("\n")
      history_section = history_text.empty? ? "" : "PREVIOUS STEPS:\n#{history_text}\n"

      Executor::Prompts.get(:react, :task_context,
        goal: goal,
        tool_list: tool_list,
        tool_format: tool_format,
        history_section: history_section)
    end

    # Build context as messages array with system/user separation.
    # Injects prior conversation history from Session so the LLM has continuity.
    def build_context_messages(goal)
      @cached_system_message ||= ExecutionContext.build_system_message(include_commands: true, depth: ExecutionContext.current_depth)
      hist_max = Session.current.metadata_value(:context_history_max) || 12
      prior = Session.current.context_for_llm(max_messages: hist_max)
      # prior already contains role/content pairs; drop any stale user msg that
      # duplicates the current goal to avoid sending the same turn twice.
      prior = prior.reject { |m| m[:role].to_s == "user" && m[:content].to_s.strip == goal.strip }
      [{ role: "system", content: @cached_system_message }] + prior +
        [{ role: "user", content: build_task_context(goal) }]
    end

    # Compact file tree for system prompt injection
    def self.dir_snapshot(root, max_depth: 2, depth: 0, exclude: %w[.git vendor tmp node_modules var])
      return "" if depth >= max_depth

      begin
        entries = Dir.children(root).sort.reject { |e| exclude.include?(e) || e.start_with?(".") }
      rescue SystemCallError
        return ""
      end
      lines = []
      entries.each do |entry|
        path = File.join(root, entry)
        indent = "  " * depth
        if File.directory?(path)
          lines << "#{indent}#{entry}/"
          lines << dir_snapshot(path, max_depth: max_depth, depth: depth + 1, exclude: exclude)
        else
          lines << "#{indent}#{entry}"
        end
      end
      lines.join("\n")
    end

    def parse_response(text)
      thought = text[/Thought:\s*(.+?)(?=Action:|ANSWER:|DONE:|$)/mi, 1]&.strip || "Continuing"
      action = text[/Action:\s*(.+?)(?=Observation:|Thought:|$)/mi, 1]&.strip ||
               text[/(ANSWER|DONE|COMPLETE):\s*(.+)/mi, 0]&.strip ||
               "ask_llm \"#{text[0..Executor::MAX_PARSE_FALLBACK_LENGTH]}\""

      { thought: thought, action: action }
    end
  end
end
