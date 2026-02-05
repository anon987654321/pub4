# frozen_string_literal: true

require 'readline'
require 'fileutils'

module MASTER
  class CLI
    attr_reader :llm

    def initialize
      @llm = LLM.new
      @server = nil
      @root = Dir.pwd
    end

    def run
      start_server
      repl
    end

    def process_input(input)
      input = input.to_s.strip
      return nil if input.empty?

      result = handle(input)
      broadcast(result) if result
      result
    end

    private

    def start_server
      @server = Server.new(self)
      @server.start
    end

    def broadcast(text)
      @server&.push(text)
    end

    def repl
      loop do
        input = Readline.readline(build_prompt, true)
        break unless input

        input = input.strip
        next if input.empty?
        break if %w[exit quit q].include?(input)

        result = with_spinner { process_input(input) }
        puts result if result
      end

      @server&.stop
      puts 'Goodbye.'
    end

    def build_prompt
      persona = @llm.persona&.dig(:name) || 'default'
      cost = format('$%.4f', @llm.total_cost)
      dir = File.basename(@root)
      "#{dir} [#{persona}] #{cost} > "
    end

    def with_spinner
      frames = %w[- \\ | /]
      done = false
      result = nil

      spinner = Thread.new do
        i = 0
        until done
          print "\r#{frames[i % 4]} "
          i += 1
          sleep 0.1
        end
        print "\r  \r"
      end

      result = yield
      done = true
      spinner.join
      result
    end

    def handle(input)
      cmd, *args = input.split(/\s+/, 2)
      arg = args.first

      case cmd
      when 'help', '?'
        help_text

      when 'cd'
        change_dir(arg)

      when 'ls', 'tree'
        show_tree

      when 'cat', 'view'
        view_file(arg)

      when 'edit'
        edit_file(arg)

      when 'clean'
        clean_file(arg)

      when 'scan'
        scan_path(arg || '.')

      when 'smells'
        detect_smells(arg || '.')

      when 'ask', 'chat'
        chat(arg)

      when 'clear'
        @llm.clear_history
        'History cleared.'

      when 'cost'
        format('$%.6f', @llm.total_cost)

      when 'persona'
        switch_persona(arg)

      when 'personas'
        list_personas

      when 'principles'
        list_principles

      when 'web'
        browse_web(arg)

      when 'image'
        generate_image(arg)

      when 'describe'
        describe_image(arg)

      when 'version'
        "MASTER v#{VERSION}"

      when 'status'
        status_info

      else
        # Default: send to LLM
        chat(input)
      end
    end

    def help_text
      <<~HELP
        Commands:
          ask <msg>      Chat with LLM
          cat <file>     View file
          cd <dir>       Change directory
          clean <file>   Clean file (CRLF, whitespace)
          clear          Clear chat history
          cost           Show LLM cost
          describe <img> Describe image (Replicate)
          edit <file>    Edit file
          help           Show this help
          image <prompt> Generate image (Replicate)
          ls             List files
          persona <name> Switch persona
          personas       List personas
          principles     List principles
          scan <path>    Scan for issues
          smells <path>  Detect code smells
          status         Show status
          version        Show version
          web <url>      Browse URL
          exit           Quit
      HELP
    end

    def change_dir(path)
      return 'Usage: cd <path>' unless path

      full = File.expand_path(path, @root)
      if Dir.exist?(full)
        @root = full
        Dir.chdir(full)
        "Changed to #{full}"
      else
        "Not found: #{path}"
      end
    end

    def show_tree
      ignore = %w[. .. .git node_modules vendor tmp .bundle]
      files = []

      Dir.glob(File.join(@root, '**', '*'), File::FNM_DOTMATCH).each do |path|
        next if ignore.any? { |i| path.include?("/#{i}/") || path.end_with?("/#{i}") }
        next if File.basename(path).start_with?('.')
        next unless File.file?(path)

        files << path.sub(@root + '/', '')
      end

      files.sort.join("\n")
    end

    def view_file(path)
      return 'Usage: cat <file>' unless path

      full = File.expand_path(path, @root)
      return "Not found: #{path}" unless File.exist?(full)

      File.read(full)
    end

    def edit_file(path)
      return 'Usage: edit <file>' unless path

      editor = ENV['EDITOR'] || 'vi'
      system("#{editor} #{File.expand_path(path, @root)}")
      'Done.'
    end

    def clean_file(path)
      return 'Usage: clean <file>' unless path

      full = File.expand_path(path, @root)
      return "Not found: #{path}" unless File.exist?(full)

      content = File.read(full)
      original = content.dup

      # CRLF -> LF
      content.gsub!("\r\n", "\n")
      # Trailing whitespace
      content.gsub!(/[ \t]+$/, '')
      # Multiple blank lines -> single
      content.gsub!(/\n{3,}/, "\n\n")
      # Ensure final newline
      content << "\n" unless content.end_with?("\n")

      if content != original
        File.write(full, content)
        'Cleaned.'
      else
        'Already clean.'
      end
    end

    def scan_path(path)
      result = Engine.scan(File.expand_path(path, @root))
      return result.error if result.err?

      issues = result.value
      return 'No issues found.' if issues.empty?

      issues.map { |i| "#{i[:file]}: #{i[:type]} (#{i[:lines] || i[:message]})" }.join("\n")
    end

    def detect_smells(path)
      scan_path(path)
    end

    def chat(message)
      return 'Usage: ask <message>' unless message

      result = @llm.chat(message)
      result.ok? ? result.value : "Error: #{result.error}"
    end

    def switch_persona(name)
      return "Available: #{Persona.list.join(', ')}" unless name

      result = @llm.switch_persona(name)
      result.ok? ? "Switched to #{name}" : result.error
    end

    def list_personas
      Persona.list.join("\n")
    end

    def list_principles
      Principle.load_all.map { |p| "#{p[:filename]}: #{p[:name]}" }.join("\n")
    end

    def browse_web(url)
      return 'Usage: web <url>' unless url

      begin
        require_relative 'web'
        Web.browse(url)
      rescue LoadError
        'Web module not available'
      end
    end

    def generate_image(prompt)
      return 'Usage: image <prompt>' unless prompt

      begin
        require_relative 'replicate'
        Replicate.generate_image(prompt)
      rescue LoadError
        'Replicate module not available'
      end
    end

    def describe_image(path)
      return 'Usage: describe <image>' unless path

      begin
        require_relative 'replicate'
        Replicate.describe_image(File.expand_path(path, @root))
      rescue LoadError
        'Replicate module not available'
      end
    end

    def status_info
      <<~STATUS
        MASTER v#{VERSION}
        Root: #{@root}
        Persona: #{@llm.persona&.dig(:name) || 'default'}
        Cost: $#{format('%.6f', @llm.total_cost)}
        Server: #{@server&.url || 'stopped'}
      STATUS
    end
  end
end
