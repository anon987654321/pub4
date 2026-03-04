# frozen_string_literal: true

require "yaml"

module MASTER
  # Personas - Character persona management system
  # Loads personas from consolidated YAML for behavioral modes
  # Ported from MASTER v1, adapted for MASTER2's architecture
  class Personas
    PERSONAS_FILE = File.join(Paths.data, "personas.yml")
    SUPPORTED_PERSONAS = %i[ronin lawyer hacker architect sysadmin trader medic].freeze

    class << self
      def supported_list
        SUPPORTED_PERSONAS
      end

      def load_all
        return [] unless File.exist?(PERSONAS_FILE)

        data = load_personas_data
        personas_hash = data["personas"] || data[:personas]
        return [] unless personas_hash

        personas_hash.map do |key, persona|
          normalize_persona(key, persona)
        end
      end

      def load(name)
        return nil unless File.exist?(PERSONAS_FILE)

        data = load_personas_data
        personas_hash = data["personas"] || data[:personas]
        return nil unless personas_hash

        # Try both string and symbol keys
        persona = personas_hash[name] || personas_hash[name.to_s] || personas_hash[name.to_sym]
        return nil unless persona

        normalize_persona(name, persona)
      end

      # List all available persona names
      def list
        return [] unless File.exist?(PERSONAS_FILE)

        data = load_personas_data
        personas_hash = data["personas"] || data[:personas]
        return [] unless personas_hash

        personas_hash.keys.map(&:to_s).sort
      end

      # Check if persona exists
      def exists?(name)
        list.include?(name.to_s)
      end

      # Get persona system prompt for LLM
      def system_prompt(name)
        persona = load(name)
        return nil unless persona

        persona[:system_prompt] || build_system_prompt(persona)
      end

      # Clear cache (useful for testing)
      def clear_cache
        @personas_cache = nil
      end

      private

      def load_personas_data
        @load_personas_data ||= begin
          YAML.safe_load_file(PERSONAS_FILE, symbolize_names: true)
        rescue ArgumentError
          # Fallback for older YAML versions or different parameter order
          YAML.safe_load_file(PERSONAS_FILE)
        end
      end

      def normalize_persona(key, persona)
        {
          name: persona["name"] || persona[:name] || key.to_s.capitalize,
          description: persona["description"] || persona[:description],
          greeting: persona["greeting"] || persona[:greeting],
          traits: normalize_array(persona["traits"] || persona[:traits]),
          style: persona["style"] || persona[:style],
          focus: normalize_array(persona["focus"] || persona[:focus]),
          sources: normalize_array(persona["sources"] || persona[:sources]),
          rules: normalize_array(persona["rules"] || persona[:rules]),
          voice: persona["voice"] || persona[:voice],
          system_prompt: persona["system_prompt"] || persona[:system_prompt],
        }
      end

      def normalize_array(value)
        return [] if value.nil?
        return value if value.is_a?(Array)

        [value]
      end

      def build_system_prompt(persona)
        parts = []
        parts << "You are #{persona[:name]}."
        parts << persona[:description] if persona[:description]

        parts << "Traits: #{persona[:traits].join(', ')}" if persona[:traits] && !persona[:traits].empty?

        parts << "Style: #{persona[:style]}" if persona[:style]

        parts << "Focus: #{persona[:focus].join(', ')}" if persona[:focus] && !persona[:focus].empty?

        parts.join(" ")
      end
    end

    # Instance methods for working with a specific persona
    attr_reader :name, :data

    def initialize(name)
      @name = name
      @data = self.class.load(name)
      raise ArgumentError, "Persona '#{name}' not found" unless @data
    end

    def description
      @data[:description]
    end

    def greeting
      @data[:greeting]
    end

    def traits
      @data[:traits]
    end

    def style
      @data[:style]
    end

    def focus
      @data[:focus]
    end

    def sources
      @data[:sources]
    end

    def rules
      @data[:rules]
    end

    def voice
      @data[:voice]
    end

    def system_prompt
      @data[:system_prompt] || self.class.send(:build_system_prompt, @data)
    end

    def to_h
      @data
    end
  end

  # Class-level activation methods
  class Personas
    class << self
      @active_persona = nil

      # Activate a persona with proactive behaviors
      def activate(name)
        persona = load(name)
        return Result.err("Persona '#{name}' not found") unless persona

        @active_persona = persona

        # Set LLM system prompt via proper accessor
        LLM.persona_prompt = persona[:system_prompt] if defined?(LLM) && persona[:system_prompt]

        # Register behavior hooks
        register_behaviors(persona) if persona[:behaviors]

        puts UI.green("+ Activated persona: #{persona[:name]}")
        puts UI.dim("  #{persona[:description]}")

        Result.ok(persona)
      end

      def deactivate
        @active_persona = nil
        LLM.persona_prompt = nil if defined?(LLM)
        unregister_behaviors

        puts UI.dim("Persona deactivated")
        Result.ok(true)
      end

      def active
        @active_persona
      end

      def active?
        !@active_persona.nil?
      end

      private

      def register_behaviors(persona)
        return unless persona[:behaviors]

        # Register "find gaps" behavior
        if persona[:behaviors].include?("Identify missing features without being asked") && defined?(Hooks) && defined?(Hooks)
          Hooks.register(:after_phase, ->(data) {
            # Check for common gaps after implement phase
            check_for_gaps(data) if data[:phase] == :implement
          })
        end

        # Register "research similar" behavior
        if persona[:behaviors].include?("Research similar projects for inspiration") && defined?(Hooks) && defined?(Hooks)
          Hooks.register(:before_phase, ->(data) {
            suggest_research(data) if data[:phase] == :ideate
          })
        end
      end

      def unregister_behaviors
        # Clear behavior hooks
        Hooks.clear_handlers if defined?(Hooks)
      end

      def check_for_gaps(_data)
        puts UI.dim("\n[Persona] Checking for common gaps...")

        gaps = detect_project_gaps

        if gaps.any?
          puts UI.yellow("  Found gaps: #{gaps.join(', ')}")
          puts UI.dim("  Should I add these?")
        end
      end

      def detect_project_gaps
        root = defined?(Paths) ? Paths.root : Dir.pwd
        test_dirs = %w[test spec]
        readme_files = %w[README.md README.rst README.txt README]

        gaps = []
        gaps << "No tests found" unless test_dirs.any? { |dir| File.directory?(File.join(root, dir)) }
        gaps << "No README" unless readme_files.any? { |name| File.file?(File.join(root, name)) }
        gaps << "No .gitignore" unless File.file?(File.join(root, ".gitignore"))
        gaps
      end

      def suggest_research(_data)
        puts UI.dim("\n[Persona] Consider researching similar projects for inspiration")
      end
    end
  end
end
