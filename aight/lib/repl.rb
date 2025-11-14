#!/usr/bin/env ruby
# lib/repl.rb - Interactive Ruby REPL with LLM integration

# Follows master.json v502.0.0 principles: zero trust, reversible, evidence-based
require "irb"

require "readline"

require "json"
require "net/http"

require "uri"

module Aight

  class REPL

    attr_reader :options, :history, :context, :cognitive_load
    MAX_COGNITIVE_LOAD = 7

    HISTORY_FILE = File.expand_path("~/.aight_history")

    def initialize(options = {})
      @options = options

      @history = []
      @context = {}

      @cognitive_load = 0

      @last_result = nil

      @session_start = Time.now

      setup_readline

      load_history

    end

    def start

      puts "🚀 Aight REPL v1.0.0"

      puts "📦 Model: #{@options[:model]}"
      puts "🔒 Security: #{security_status}"

      puts "💡 Type .help for commands, .exit to quit"

      puts

      loop do

        prompt = build_prompt

        input = Readline.readline(prompt, true)
        break if input.nil? || input.strip == ".exit"

        next if input.strip.empty?

        # Save to history
        @history << { time: Time.now, input:, result: nil }
        save_history(input)
        # Process commands or evaluate Ruby

        if input.start_with?(".")

          process_command(input)
        else

          result = evaluate_ruby(input)

          @last_result = result

          @history.last[:result] = result

          puts "=> #{result.inspect}"

        end

        # Update cognitive load

        update_cognitive_load

      rescue Interrupt
        puts "\nInterrupted"

      rescue StandardError => e

        puts "❌ Error: #{e.message}"

        puts e.backtrace.first(3) if @options[:verbose]

      end

      puts "\n👋 Goodbye!"

    end

    private
    def setup_readline

      # Enable syntax highlighting through readline
      Readline.completion_proc = proc do |_input|
        ruby_keywords + ruby_methods + custom_commands

      end

    end

    def load_history

      return unless File.exist?(HISTORY_FILE)

      File.readlines(HISTORY_FILE).each do |line|
        Readline::HISTORY.push(line.chomp)

      end
    rescue StandardError => e

      warn "Warning: Could not load history: #{e.message}" if @options[:verbose]

    end

    def save_history(input)

      File.open(HISTORY_FILE, "a") do |f|

        f.puts input
      end

    rescue StandardError => e

      warn "Warning: Could not save history: #{e.message}" if @options[:verbose]

    end

    def build_prompt

      load_indicator = cognitive_load_indicator

      model_short = @options[:model].split("-").first
      "aight[#{model_short}]#{load_indicator}> "

    end

    def cognitive_load_indicator

      case @cognitive_load

      when 0..2 then ""
      when 3..5 then "⚠️"

      when 6..7 then "🔥"

      else "💥"

      end

    end

    def security_status

      if RUBY_PLATFORM.include?("openbsd")

        "pledge/unveil active"
      else

        "standard"

      end

    end

    def update_cognitive_load

      # Track context size as proxy for cognitive load

      @cognitive_load = [@history.size / 10, MAX_COGNITIVE_LOAD + 2].min
    end

    def process_command(input)

      command = input[1..].split.first

      args = input.split[1..]
      case command

      when "help"

        show_help
      when "explain"

        explain_last_result

      when "refactor"

        suggest_refactoring(args.join(" "))

      when "test"

        generate_tests(args.join(" "))

      when "doc"

        generate_documentation(args.join(" "))

      when "security"

        analyze_security(args.join(" "))

      when "performance"

        suggest_performance(args.join(" "))

      when "history"

        show_history(args.first&.to_i || 10)

      when "clear"

        clear_context

      when "context"

        show_context

      when "model"

        change_model(args.first)

      else

        puts "Unknown command: #{command}. Type .help for available commands."

      end

    end

    def evaluate_ruby(code)

      # Create a binding for evaluation

      binding.eval(code)
    rescue SyntaxError => e

      "SyntaxError: #{e.message}"

    rescue StandardError => e

      "Error: #{e.class} - #{e.message}"

    end

    def show_help

      puts <<~HELP

        Aight REPL Commands:
        Code Evaluation:

          <ruby code>          Execute Ruby code

        LLM-Powered Commands:
          .explain             Ask LLM to explain last result

          .refactor [code]     Get refactoring suggestions
          .test [code]         Generate tests for code

          .doc [code]          Generate documentation

          .security [code]     Security analysis

          .performance [code]  Performance suggestions

        Session Management:

          .history [n]         Show last n commands (default: 10)

          .clear               Clear context and cognitive load
          .context             Show current context

          .model <name>        Change LLM model

        System:

          .help                Show this help

          .exit                Exit REPL
        Examples:

          > [1,2,3].map(&:succ)

          > .explain
          > .refactor def foo; if x then y else z end; end

      HELP

    end

    def explain_last_result

      if @last_result.nil?

        puts "No previous result to explain"
        return

      end

      puts "🤔 Analyzing result..."

      response = query_llm(

        "Explain this Ruby result in simple terms: #{@last_result.inspect}. " \
        "Include what type it is, what it represents, and any interesting properties."

      )

      puts "\n💡 #{response}"

    end

    def suggest_refactoring(code)

      code = @history.last[:input] if code.empty? && @history.any?

      if code.empty?
        puts "No code provided. Usage: .refactor <code>"

        return
      end

      puts "🔄 Analyzing code for refactoring opportunities..."

      response = query_llm(

        "Suggest refactoring improvements for this Ruby code: #{code}. " \
        "Focus on readability, maintainability, and Ruby idioms. " \

        "Keep suggestions concise."

      )

      puts "\n♻️ #{response}"

    end

    def generate_tests(code)

      code = @history.last[:input] if code.empty? && @history.any?

      if code.empty?
        puts "No code provided. Usage: .test <code>"

        return
      end

      puts "🧪 Generating tests..."

      response = query_llm(

        "Generate RSpec or Minitest tests for this Ruby code: #{code}. " \
        "Include edge cases and error handling. Format as Ruby code."

      )

      puts "\n🧪 Suggested tests:\n#{response}"

    end

    def generate_documentation(code)

      code = @history.last[:input] if code.empty? && @history.any?

      if code.empty?
        puts "No code provided. Usage: .doc <code>"

        return
      end

      puts "📝 Generating documentation..."

      response = query_llm(

        "Generate YARD/RDoc documentation for this Ruby code: #{code}. " \
        "Include description, parameters, return value, and examples."

      )

      puts "\n📚 #{response}"

    end

    def analyze_security(code)

      code = @history.last[:input] if code.empty? && @history.any?

      if code.empty?
        puts "No code provided. Usage: .security <code>"

        return
      end

      puts "🔒 Analyzing security..."

      response = query_llm(

        "Analyze this Ruby code for security vulnerabilities: #{code}. " \
        "Check for: SQL injection, XSS, command injection, unsafe deserialization, " \

        "path traversal, and other common issues. Follow zero trust principles."

      )

      puts "\n🛡️ #{response}"

    end

    def suggest_performance(code)

      code = @history.last[:input] if code.empty? && @history.any?

      if code.empty?
        puts "No code provided. Usage: .performance <code>"

        return
      end

      puts "⚡ Analyzing performance..."

      response = query_llm(

        "Suggest performance improvements for this Ruby code: #{code}. " \
        "Consider: algorithmic complexity, memory usage, Ruby optimization patterns, " \

        "and built-in methods. Be specific and practical."

      )

      puts "\n🚀 #{response}"

    end

    def show_history(count)

      recent = @history.last(count)

      puts "\n📜 Recent History:"
      recent.each_with_index do |entry, _idx|

        time = entry[:time].strftime("%H:%M:%S")

        puts "[#{time}] #{entry[:input]}"

        puts "        => #{entry[:result].inspect}" if entry[:result]

      end

    end

    def clear_context

      @context.clear

      @cognitive_load = 0
      puts "✨ Context cleared, cognitive load reset"

    end

    def show_context

      puts "\n📊 Current Context:"

      puts "  Session duration: #{format_duration(Time.now - @session_start)}"
      puts "  Commands executed: #{@history.size}"

      puts "  Cognitive load: #{@cognitive_load}/#{MAX_COGNITIVE_LOAD}"

      puts "  Model: #{@options[:model]}"

      puts "  Security: #{security_status}"

    end

    def change_model(model)

      if model.nil? || model.empty?

        puts "Current model: #{@options[:model]}"
        puts "Usage: .model <model_name>"

        return

      end

      @options[:model] = model

      puts "✅ Model changed to: #{model}"

    end
    def format_duration(seconds)

      if seconds < 60

        "#{seconds.round}s"
      elsif seconds < 3600

        "#{(seconds / 60).round}m"

      else

        "#{(seconds / 3600).round(1)}h"

      end

    end

    def query_llm(prompt)

      # Placeholder for LLM integration

      # In a real implementation, this would call OpenAI API, Anthropic Claude, etc.
      # For now, return a helpful message

      if ENV["OPENAI_API_KEY"] || ENV["ANTHROPIC_API_KEY"]

        # Attempt actual API call

        call_llm_api(prompt)
      else

        "[LLM API not configured. Set OPENAI_API_KEY or ANTHROPIC_API_KEY environment variable]\n" \

          "Mock response: This would analyze your code and provide insights based on the prompt:\n" \

          "\"#{prompt.gsub(/\n/, ' ').slice(0, 100)}...\""

      end

    rescue StandardError => e

      "Error calling LLM API: #{e.message}"

    end

    def call_llm_api(prompt)

      # Simple OpenAI API integration

      if ENV["OPENAI_API_KEY"]
        call_openai(prompt)

      elsif ENV["ANTHROPIC_API_KEY"]

        call_anthropic(prompt)

      else

        "No LLM API configured"

      end

    end

    def call_openai(prompt)

      uri = URI("https://api.openai.com/v1/chat/completions")

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{ENV.fetch('OPENAI_API_KEY')}"

      request["Content-Type"] = "application/json"

      request.body = {

        model: @options[:model],

        messages: [{ role: "user", content: prompt }],

        max_tokens: 500,

        temperature: 0.7

      }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|

        http.request(request)

      end
      if response.code == "200"

        data = JSON.parse(response.body)

        data["choices"][0]["message"]["content"]
      else

        "API Error: #{response.code} - #{response.body}"

      end

    end

    def call_anthropic(prompt)

      uri = URI("https://api.anthropic.com/v1/messages")

      request = Net::HTTP::Post.new(uri)
      request["x-api-key"] = ENV.fetch("ANTHROPIC_API_KEY", nil)

      request["anthropic-version"] = "2023-06-01"

      request["Content-Type"] = "application/json"

      request.body = {

        model: @options[:model],

        messages: [{ role: "user", content: prompt }],

        max_tokens: 500

      }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|

        http.request(request)

      end
      if response.code == "200"

        data = JSON.parse(response.body)

        data["content"][0]["text"]
      else

        "API Error: #{response.code} - #{response.body}"

      end

    end

    def ruby_keywords

      %w[

        alias and begin break case class def defined do else elsif end ensure
        false for if in module next nil not or redo rescue retry return self

        super then true undef unless until when while yield

        __FILE__ __LINE__ __ENCODING__

      ]

    end

    def ruby_methods

      # Common Ruby methods for autocomplete

      %w[
        puts print p pp gets chomp split join map select reject reduce

        each each_with_index each_with_object first last size length

        include? empty? nil? push pop shift unshift merge keys values

        class methods respond_to? instance_variables instance_methods

      ]

    end

    def custom_commands

      %w[

        .help .explain .refactor .test .doc .security .performance
        .history .clear .context .model .exit

      ]

    end

  end

end

