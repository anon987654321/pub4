require 'json'
require_relative 'voice'
require_relative 'html_view'
require_relative 'smart_suggest'

module MASTER
  # Multimodal - Unified interface for voice, text, and visual interactions
  # Coordinates between different modalities and maintains context
  class Multimodal
    attr_reader :context, :mode, :handlers

    def initialize(options = {})
      @mode = options[:mode] || :text
      @context = {}
      @handlers = {
        voice: [],
        text: [],
        file_upload: [],
        html_render: []
      }
      @voice = Voice.new
      @html_view = HTMLView.new
    end

    # Start multimodal interface
    def self.start(options = {}, &block)
      interface = new(options)
      interface.start(&block)
    end

    def start(&block)
      puts "🌐 Starting multimodal interface"
      puts "   Mode: #{@mode}"
      puts ""

      # Setup handlers from block
      block.call(self) if block_given?

      # Start main loop
      loop do
        case @mode
        when :voice
          handle_voice_mode
        when :text
          handle_text_mode
        when :dashboard
          handle_dashboard_mode
        else
          handle_text_mode
        end
        
        break if @context[:exit]
      end

      puts "👋 Multimodal interface stopped"
    end

    # Register handler for voice commands
    def on_voice(&block)
      @handlers[:voice] << block
    end

    # Register handler for text commands
    def on_text(&block)
      @handlers[:text] << block
    end

    # Register handler for file uploads
    def on_file_upload(&block)
      @handlers[:file_upload] << block
    end

    # Render HTML view
    def render_html(content)
      @handlers[:html_render].each { |handler| handler.call(content) }
    end

    # Switch mode
    def switch_mode(new_mode)
      old_mode = @mode
      puts "🔄 Switching to #{new_mode} mode"
      @mode = new_mode
      update_context(:mode_switched, { from: old_mode, to: new_mode })
    end

    # Update context
    def update_context(key, value)
      @context[key] = value
      @context[:updated_at] = Time.now
    end

    # Get context
    def get_context(key = nil)
      key ? @context[key] : @context
    end

    private

    def handle_voice_mode
      puts "🎤 Voice mode active"
      print "Command (or 'switch text' to change mode): "
      
      input = gets.chomp
      return if input.empty?
      
      if input.downcase.start_with?('switch')
        new_mode = input.split[1]&.to_sym || :text
        switch_mode(new_mode)
        return
      end
      
      if input.downcase == 'exit'
        @context[:exit] = true
        return
      end

      # Process voice command
      result = process_voice(input)
      
      # Trigger handlers
      @handlers[:voice].each { |handler| handler.call(input, result) }
      
      # Update context
      update_context(:last_command, input)
      update_context(:last_result, result)
    end

    def handle_text_mode
      print "master> "
      
      input = gets.chomp
      return if input.empty?
      
      if input.downcase.start_with?('switch')
        new_mode = input.split[1]&.to_sym || :voice
        switch_mode(new_mode)
        return
      end
      
      if input.downcase == 'exit'
        @context[:exit] = true
        return
      end

      # Process text command
      result = process_text(input)
      
      # Trigger handlers
      @handlers[:text].each { |handler| handler.call(input, result) }
      
      # Update context
      update_context(:last_command, input)
      update_context(:last_result, result)
    end

    def handle_dashboard_mode
      puts "📊 Dashboard mode"
      puts "   View dashboard at: http://localhost:4567"
      puts "   Type 'switch text' to return to text mode"
      puts ""
      
      # Generate and serve dashboard
      dashboard_html = @html_view.generate_dashboard('lib/')
      
      # In production, this would start a web server
      # For now, just save to file
      dashboard_file = File.join(MASTER.root, 'dashboard.html')
      File.write(dashboard_file, dashboard_html)
      
      puts "   Dashboard saved to: #{dashboard_file}"
      puts "   Open in browser to view"
      puts ""
      
      # Wait for mode switch
      print "Command: "
      input = gets.chomp
      
      if input.downcase.start_with?('switch')
        new_mode = input.split[1]&.to_sym || :text
        switch_mode(new_mode)
      elsif input.downcase == 'exit'
        @context[:exit] = true
      end
    end

    def process_voice(command)
      intent = VoiceNLU.parse(command)
      execute_command(intent)
    end

    def process_text(command)
      # Parse text command
      case command
      when /^refactor\s+(.+)/
        file = $1
        refactor_file(file)
      when /^analyze\s+(.+)/
        file = $1
        analyze_file(file)
      when /^suggest\s+(.+)/
        path = $1
        suggest_improvements(path)
      when /^dashboard\s+(.+)/
        path = $1
        generate_dashboard(path)
      when /^help$/
        show_help
      else
        { success: false, message: "Unknown command: #{command}" }
      end
    end

    def execute_command(intent)
      case intent[:action]
      when :refactor
        refactor_file(intent[:target])
      when :analyze
        analyze_file(intent[:target])
      when :suggest
        suggest_improvements(intent[:target])
      else
        { success: false, message: "Unknown action: #{intent[:action]}" }
      end
    end

    def refactor_file(file)
      return { success: false, message: "File not found: #{file}" } unless File.exist?(file)
      
      # Require engine lazily to avoid circular dependency
      require_relative 'engine' unless defined?(MASTER::Engine)
      
      engine = Engine.new
      code = File.read(file)
      result = engine.refactor(code)
      
      if result[:success]
        File.write(file, result[:code])
        puts "✓ Refactored #{file}"
        { success: true, message: "Refactored successfully" }
      else
        puts "✗ Failed to refactor #{file}: #{result[:error]}"
        { success: false, message: result[:error] }
      end
    rescue => e
      { success: false, message: e.message }
    end

    def analyze_file(file)
      return { success: false, message: "File not found: #{file}" } unless File.exist?(file)
      
      # Require engine lazily to avoid circular dependency
      require_relative 'engine' unless defined?(MASTER::Engine)
      
      engine = Engine.new
      code = File.read(file)
      result = engine.analyze(code)
      
      puts "Analysis results:"
      puts JSON.pretty_generate(result)
      
      { success: true, message: "Analysis complete", data: result }
    rescue => e
      { success: false, message: e.message }
    end

    def suggest_improvements(path)
      suggester = SmartSuggest.new
      suggestions = suggester.batch_analyze([path])
      
      puts "Found #{suggestions.size} suggestions:"
      suggestions.take(10).each do |s|
        puts s.to_s
        puts ""
      end
      
      { success: true, message: "Found #{suggestions.size} suggestions", data: suggestions }
    rescue => e
      { success: false, message: e.message }
    end

    def generate_dashboard(path)
      dashboard_html = @html_view.generate_dashboard(path)
      dashboard_file = File.join(MASTER.root, 'dashboard.html')
      File.write(dashboard_file, dashboard_html)
      
      puts "✓ Dashboard generated: #{dashboard_file}"
      
      { success: true, message: "Dashboard generated", file: dashboard_file }
    rescue => e
      { success: false, message: e.message }
    end

    def show_help
      help_text = <<~HELP
        MASTER Multimodal Interface
        ===========================
        
        Commands:
          refactor <file>     - Refactor a file
          analyze <file>      - Analyze a file
          suggest <path>      - Get improvement suggestions
          dashboard <path>    - Generate HTML dashboard
          switch <mode>       - Switch mode (voice, text, dashboard)
          help                - Show this help
          exit                - Exit
        
        Modes:
          text       - Text command interface (default)
          voice      - Voice command interface
          dashboard  - HTML dashboard interface
      HELP
      
      puts help_text
      { success: true, message: "Help displayed" }
    end
  end
end
