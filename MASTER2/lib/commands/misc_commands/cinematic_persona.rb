# frozen_string_literal: true

module MASTER
  module Commands
    module MiscCommands
      # Cinematic AI Pipeline Commands

      def cinematic(args)
        parts = args&.split || []
        return show_cinematic_help if parts.empty?

        command = parts.first
        case command
        when 'list'
          list_cinematic_presets
        when 'apply'
          apply_cinematic_preset(parts[1], parts[2])
        when 'discover'
          discover_cinematic_styles(parts[1], samples: (parts[2] || 10).to_i)
        when 'build'
          build_cinematic_pipeline
        else
          show_cinematic_help
        end
      end

      private

      def show_cinematic_help
        puts <<~HELP

          Cinematic AI Pipeline Commands:

            cinematic list                     List available presets
            cinematic apply <preset> <input>   Apply preset to image
            cinematic discover <input> [n]     Discover new styles (n samples)
            cinematic build                    Interactive pipeline builder

          Presets: blade-runner, wes-anderson, noir, golden-hour, teal-orange

        HELP
      end

      def list_cinematic_presets
        result = Cinematic.list_presets
        return puts "  Error: #{result.error}" if result.err?

        puts "Cinematic Presets"
        result.value[:presets].each do |preset|
          source = preset[:source] == 'builtin' ? '[builtin]' : '[custom]'
          puts "  * #{preset[:name]} #{source} #{preset[:description]}"
        end
      end

      def apply_cinematic_preset(preset_name, input_path)
        unless preset_name && input_path
          return puts "  Usage: cinematic apply <preset> <input>"
        end

        unless File.exist?(input_path)
          return puts "  Error: File not found: #{input_path}"
        end

        puts "  Applying preset '#{preset_name}' to #{input_path}..."

        result = Cinematic.apply_preset(input_path, preset_name)

        if result.ok?
          output = result.value[:final]
          puts "pipeline: complete -> #{output}"
        else
          puts "  - Pipeline failed: #{result.error}"
        end
      end

      def discover_cinematic_styles(input_path, samples: 10)
        unless input_path
          return puts "  Usage: cinematic discover <input> [samples]"
        end

        unless File.exist?(input_path)
          return puts "  Error: File not found: #{input_path}"
        end

        result = Cinematic.discover_style(input_path, samples: samples)

        if result.ok?
          discoveries = result.value[:discoveries]
          puts "  + Discovered #{discoveries.size} styles!"

          discoveries.each_with_index do |d, i|
            puts "  #{i + 1}. Score: #{d[:score].round(2)} | #{d[:pipeline].stages.size} stages"
          end
        else
          puts "  - Discovery failed: #{result.error}"
        end
      end

      def build_cinematic_pipeline
        puts "pipeline: interactive builder (coming soon)"
        puts "  pipeline = MASTER::Cinematic::Pipeline.new; pipeline.chain('stability-ai/sdxl', { prompt: 'cinematic' }); result = pipeline.execute(input)"
      end

      # Persona management commands
      def manage_persona(args)
        parts = args&.split || []
        return show_persona_help if parts.empty?

        command = parts[0]
        name = parts[1]

        case command
        when "activate"
          return puts "  Usage: persona activate <name>" unless name

          if defined?(Personas)
            result = Personas.activate(name)
            if result.err?
              puts "  Error: #{result.error}"
            end
          else
            puts "  Personas module not available"
          end
        when "deactivate"
          if defined?(Personas)
            Personas.deactivate
          else
            puts "  Personas module not available"
          end
        when "list"
          list_personas
        else
          show_persona_help
        end
      end

      def list_personas
        return puts "  Personas module not available" unless defined?(Personas)

        personas = Personas.list
        if personas.empty?
          puts "  No personas available"
        else
          puts "\nAvailable Personas:"
          personas.each do |name|
            active_marker = defined?(Personas.active) && Personas.active&.dig(:name) == name ? " *" : ""
            puts "  * #{name}#{active_marker}"
          end
        end
      end

      def show_persona_help
        puts <<~HELP

          Persona Commands:

            persona activate <name>    Activate a persona
            persona deactivate         Deactivate current persona
            persona list               List available personas

        HELP
      end
    end
  end
end
