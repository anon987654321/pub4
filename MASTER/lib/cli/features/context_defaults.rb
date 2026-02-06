# frozen_string_literal: true

module MASTER
  class CLI
    module Features
      module ContextDefaults
        # Context-aware defaults for file, directory, and LLM tier
        
        # Smart defaults - infer missing arguments from context
        def default_file(arg = nil)
          return arg if arg && !arg.empty?
          return @last_file if @last_file && File.exist?(@last_file)
          
          # Find most recently modified .rb file in current dir
          Dir.glob(File.join(@root, '*.rb')).max_by { |f| File.mtime(f) }
        end
        
        def default_dir(arg = nil)
          return arg if arg && !arg.empty?
          return @last_dir if @last_dir && Dir.exist?(@last_dir)
          @root
        end
        
        def default_target(arg = nil)
          return arg if arg && !arg.empty?
          return @last_file if @last_file
          return @last_dir if @last_dir
          @root
        end
        
        def default_llm_tier
          # Use cheaper tier for simple queries, expensive for refactoring
          @last_command_type ||= :standard
          
          case @last_command_type
          when :refactor, :review, :audit
            :premium  # claude-opus, gpt-4
          when :scan, :smells, :lint
            :standard # claude-sonnet, gpt-3.5
          else
            :fast     # claude-haiku, gpt-3.5-turbo
          end
        end
        
        def remember_file(path)
          @last_file = File.expand_path(path, @root) if path
        end
        
        def remember_dir(path)
          @last_dir = File.expand_path(path, @root) if path && Dir.exist?(File.expand_path(path, @root))
        end
        
        def remember_command_type(type)
          @last_command_type = type
        end
      end
    end
  end
end
