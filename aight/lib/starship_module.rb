#!/usr/bin/env ruby
# lib/starship_module.rb - Starship prompt integration for aight

# Follows master.json v502.0.0 principles
require "fileutils"

require "json"

module Aight
  module StarshipModule

    CONFIG_DIR = File.expand_path("~/.config/starship")
    COMPLETION_DIR = File.expand_path("~/.zsh/completions")

    def self.generate_config

      puts "🌟 Generating Starship configuration for aight..."

      # Ensure config directory exists
      FileUtils.mkdir_p(CONFIG_DIR)

      # Read template
      template_path = File.join(__dir__, "../config/starship.toml")

      if File.exist?(template_path)
        template = File.read(template_path)

        # Write to user's starship config
        config_path = File.join(CONFIG_DIR, "starship.toml")

        if File.exist?(config_path)
          puts "⚠️  Starship config already exists at #{config_path}"

          print "Append aight module? [y/N]: "
          response = gets.chomp.downcase

          if response == "y"

            File.open(config_path, "a") do |f|

              f.puts "\n# Aight REPL integration"
              f.puts template

            end

            puts "✅ Aight module appended to Starship config"

          else

            puts "❌ Cancelled"

          end

        else

          File.write(config_path, template)

          puts "✅ Starship config created at #{config_path}"

        end

      else

        puts "⚠️  Template not found at #{template_path}"

        puts "Creating basic configuration..."

        create_basic_config

      end

      puts "\n📝 To use the aight module, ensure this is in your shell config:"

      puts "   export AIGHT_MODEL=\"gpt-4\""

      puts "   eval \"$(starship init zsh)\""
    end

    def self.create_basic_config

      config_path = File.join(CONFIG_DIR, "starship.toml")

      config = <<~TOML
        # Aight REPL Starship Module

        # Displays current LLM model and cognitive load
        [custom.aight]

        command = "echo -n '🤖'"

        when = 'test -n "$AIGHT_SESSION"'
        format = "[$output]($style) "

        style = "bold blue"

        description = "Aight REPL active"

        [custom.aight_model]

        command = "echo -n $AIGHT_MODEL"

        when = 'test -n "$AIGHT_MODEL"'
        format = "[$output]($style) "

        style = "cyan"

        description = "Current LLM model"

        [custom.aight_load]

        command = "test -f ~/.aight_load && cat ~/.aight_load || echo ''"

        when = 'test -f ~/.aight_load'
        format = "[$output]($style) "

        style = "yellow"

        description = "Cognitive load indicator"

      TOML

      File.write(config_path, config)

      puts "✅ Basic Starship config created at #{config_path}"

    end
    def self.install_completions

      puts "📦 Installing zsh completions for aight..."

      # Ensure completion directory exists
      FileUtils.mkdir_p(COMPLETION_DIR)

      # Read completion file
      completion_source = File.join(__dir__, "../completions/_aight")

      completion_dest = File.join(COMPLETION_DIR, "_aight")
      if File.exist?(completion_source)

        FileUtils.cp(completion_source, completion_dest)

        puts "✅ Completions installed to #{completion_dest}"
        puts "\n📝 Add this to your .zshrc:"

        puts "   fpath=(~/.zsh/completions $fpath)"

        puts "   autoload -Uz compinit && compinit"

      else

        puts "⚠️  Completion file not found at #{completion_source}"

        puts "Creating basic completions..."

        create_basic_completions(completion_dest)

      end

    end

    def self.create_basic_completions(dest_path)

      completions = <<~ZSH

        #compdef aight
        # Zsh completions for aight

        _aight() {

          local -a commands

          commands=(
            'repl:Start interactive REPL (default)'

            'starship:Generate Starship configuration'

            'completions:Install zsh completions'

          )

        #{'  '}

          local -a options

          options=(

            '-r[Start interactive REPL]'

            '--repl[Start interactive REPL]'

            '-s[Generate Starship configuration]'

            '--starship[Generate Starship configuration]'

            '-c[Install zsh completions]'

            '--completions[Install zsh completions]'

            '-m[Set LLM model]:model:'

            '--model[Set LLM model]:model:'

            '-v[Enable verbose output]'

            '--verbose[Enable verbose output]'

            '-h[Show help message]'

            '--help[Show help message]'

          )

        #{'  '}

          _arguments -s -S $options

        }

        _aight "$@"

      ZSH

      File.write(dest_path, completions)
      puts "✅ Basic completions created at #{dest_path}"

    end
    # Runtime methods for REPL integration

    def self.update_session_info(model:, load:, status:)

      # Update environment for Starship to pick up
      ENV["AIGHT_SESSION"] = "1"

      ENV["AIGHT_MODEL"] = model

      # Write load to file for Starship custom command

      load_file = File.expand_path("~/.aight_load")

      load_indicator = case load
                       when 0..2 then ""

                       when 3..5 then "⚠️"

                       when 6..7 then "🔥"

                       else "💥"

                       end

      File.write(load_file, load_indicator)

    rescue StandardError => e

      warn "Warning: Could not update session info: #{e.message}"
    end

    def self.clear_session_info

      ENV.delete("AIGHT_SESSION")

      load_file = File.expand_path("~/.aight_load")
      FileUtils.rm_f(load_file)

    rescue StandardError => e

      warn "Warning: Could not clear session info: #{e.message}"

    end

  end

end

