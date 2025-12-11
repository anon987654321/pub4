#!/usr/bin/env ruby
# frozen_string_literal: true

# Claude CLI - Interactive Claude API client with streaming, sessions, and validation
# Version: 1.0.0
# Zero external dependencies - stdlib only
# OpenBSD optimizations: pledge, native TLS

require "net/http"
require "json"
require "yaml"
require "fileutils"
require "digest"
require "uri"
require "readline"

# OpenBSD pledge support via Fiddle (if available)
begin
  require "fiddle"
  PLEDGE_AVAILABLE = RUBY_PLATFORM.include?("openbsd")
rescue LoadError
  PLEDGE_AVAILABLE = false
end

module Claude
  VERSION = "1.0.0"
  
  # Constants
  API_TIMEOUT = 60
  API_CONNECT_TIMEOUT = 10
  MAX_RETRIES = 3
  RETRY_BASE_DELAY = 1.0
  RETRY_MAX_DELAY = 16.0
  
  # Known Claude models for validation
  KNOWN_MODELS = [
    "claude-3-5-sonnet-20241022",
    "claude-3-5-sonnet-20240620", 
    "claude-3-5-haiku-20241022",
    "claude-3-opus-20240229",
    "claude-3-sonnet-20240229",
    "claude-3-haiku-20240307",
    "claude-sonnet-4-20250514"
  ].freeze
  
  # Default configuration
  DEFAULT_CONFIG = {
    "api_key" => nil,
    "api_base" => "https://api.anthropic.com",
    "model" => "claude-3-5-sonnet-20241022",
    "max_tokens" => 4096,
    "temperature" => 1.0,
    "stream" => true,
    "debug" => false
  }.freeze
  
  # Configuration manager
  class Config
    attr_reader :path, :data
    
    def initialize(path = nil)
      @path = path || File.join(Dir.home, ".claude", "config.yml")
      @data = load_config
    end
    
    def load_config
      return DEFAULT_CONFIG.dup unless File.exist?(@path)
      
      loaded = YAML.load_file(@path)
      DEFAULT_CONFIG.merge(loaded)
    rescue => e
      warn "Warning: Failed to load config from #{@path}: #{e.message}"
      DEFAULT_CONFIG.dup
    end
    
    def save
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, YAML.dump(@data))
      File.chmod(0600, @path) # Secure permissions
      true
    rescue => e
      warn "Error: Failed to save config: #{e.message}"
      false
    end
    
    def get(key)
      @data[key]
    end
    
    def set(key, value)
      # Validate before setting
      case key
      when "model"
        unless KNOWN_MODELS.include?(value)
          warn "Warning: '#{value}' is not a known Claude model"
          warn "Known models: #{KNOWN_MODELS.join(', ')}"
        end
      when "temperature"
        value = value.to_f
        unless value >= 0.0 && value <= 1.0
          raise ArgumentError, "Temperature must be between 0.0 and 1.0"
        end
      when "max_tokens"
        value = value.to_i
        unless value > 0 && value <= 200_000
          raise ArgumentError, "max_tokens must be between 1 and 200,000"
        end
      when "api_base"
        uri = URI.parse(value)
        unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
          raise ArgumentError, "api_base must be a valid HTTP(S) URL"
        end
      when "stream"
        value = ["true", "1", "yes", true].include?(value)
      when "debug"
        value = ["true", "1", "yes", true].include?(value)
      end
      
      @data[key] = value
    end
    
    def validate
      errors = []
      
      unless @data["api_key"]
        errors << "API key not set. Use: claude config set api_key YOUR_KEY"
      end
      
      unless KNOWN_MODELS.include?(@data["model"])
        errors << "Unknown model: #{@data["model"]}"
      end
      
      unless @data["temperature"].between?(0.0, 1.0)
        errors << "Temperature must be between 0.0 and 1.0"
      end
      
      unless @data["max_tokens"].positive?
        errors << "max_tokens must be positive"
      end
      
      errors
    end
  end
  
  # Master.yml validator
  class MasterValidator
    REQUIRED_FIELDS = {
      "meta" => ["version"],
      "principles" => ["critical"]
    }.freeze
    
    DEPRECATED_FIELDS = [].freeze
    
    def initialize(path)
      @path = path
      @data = nil
      @errors = []
      @warnings = []
    end
    
    def validate
      unless File.exist?(@path)
        @errors << "master.yml not found at #{@path}"
        return false
      end
      
      begin
        @data = YAML.load_file(@path)
      rescue => e
        @errors << "Failed to parse YAML: #{e.message}"
        return false
      end
      
      check_required_fields
      check_deprecated_fields
      
      @errors.empty?
    end
    
    def checksum
      return nil unless @data
      Digest::SHA256.hexdigest(File.read(@path))
    end
    
    def report
      puts "\n=== Master.yml Validation ==="
      
      if @errors.any?
        puts "\nErrors:"
        @errors.each { |e| puts "  ✗ #{e}" }
      end
      
      if @warnings.any?
        puts "\nWarnings:"
        @warnings.each { |w| puts "  ⚠ #{w}" }
      end
      
      if @errors.empty? && @warnings.empty?
        puts "  ✓ All checks passed"
        puts "  Checksum: #{checksum}"
      end
    end
    
    private
    
    def check_required_fields
      REQUIRED_FIELDS.each do |section, fields|
        unless @data.key?(section)
          @errors << "Missing required section: #{section}"
          next
        end
        
        fields.each do |field|
          unless @data[section].is_a?(Hash) && @data[section].key?(field)
            @errors << "Missing required field: #{section}.#{field}"
          end
        end
      end
    end
    
    def check_deprecated_fields
      DEPRECATED_FIELDS.each do |field_path|
        parts = field_path.split(".")
        current = @data
        
        parts.each do |part|
          break unless current.is_a?(Hash)
          if current.key?(part)
            current = current[part]
            if parts.last == part
              @warnings << "Deprecated field found: #{field_path}"
            end
          else
            break
          end
        end
      end
    end
  end
  
  # HTTP client for Claude API
  class APIClient
    attr_reader :config
    
    def initialize(config)
      @config = config
    end
    
    def test_connection
      uri = URI.join(@config.get("api_base"), "/v1/messages")
      request = build_request(uri, "POST", {
        model: @config.get("model"),
        max_tokens: 1,
        messages: [{ role: "user", content: "test" }]
      })
      
      response = execute_request(uri, request, retries: 0)
      response.is_a?(Net::HTTPSuccess) || response.code.to_i < 500
    rescue => e
      debug "Connection test failed: #{e.message}"
      false
    end
    
    def send_message(messages, stream: nil)
      stream = @config.get("stream") if stream.nil?
      
      uri = URI.join(@config.get("api_base"), "/v1/messages")
      payload = {
        model: @config.get("model"),
        max_tokens: @config.get("max_tokens"),
        temperature: @config.get("temperature"),
        messages: messages,
        stream: stream
      }
      
      request = build_request(uri, "POST", payload)
      
      if stream
        stream_request(uri, request)
      else
        standard_request(uri, request)
      end
    end
    
    private
    
    def build_request(uri, method, payload)
      request_class = Object.const_get("Net::HTTP::#{method.capitalize}")
      request = request_class.new(uri)
      
      request["Content-Type"] = "application/json"
      request["anthropic-version"] = "2023-06-01"
      request["x-api-key"] = @config.get("api_key")
      
      request.body = JSON.generate(payload) if payload
      request
    end
    
    def execute_request(uri, request, retries: MAX_RETRIES)
      attempt = 0
      last_error = nil
      
      loop do
        begin
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = API_CONNECT_TIMEOUT
          http.read_timeout = API_TIMEOUT
          
          response = http.request(request)
          
          # Handle rate limiting with retry
          if response.code.to_i == 429 && attempt < retries
            delay = calculate_retry_delay(attempt)
            debug "Rate limited (429), retrying in #{delay}s..."
            sleep delay
            attempt += 1
            next
          end
          
          # Handle server errors with retry
          if response.code.to_i >= 500 && attempt < retries
            delay = calculate_retry_delay(attempt)
            debug "Server error (#{response.code}), retrying in #{delay}s..."
            sleep delay
            attempt += 1
            next
          end
          
          return response
        rescue Net::OpenTimeout, Net::ReadTimeout => e
          last_error = e
          if attempt < retries
            delay = calculate_retry_delay(attempt)
            debug "Timeout error, retrying in #{delay}s..."
            sleep delay
            attempt += 1
          else
            raise TimeoutError, "Request timed out after #{attempt + 1} attempts. Try again later."
          end
        rescue => e
          last_error = e
          if attempt < retries && transient_error?(e)
            delay = calculate_retry_delay(attempt)
            debug "Transient error, retrying in #{delay}s..."
            sleep delay
            attempt += 1
          else
            raise
          end
        end
        
        break if attempt >= retries
      end
      
      raise last_error if last_error
    end
    
    def calculate_retry_delay(attempt)
      delay = RETRY_BASE_DELAY * (2**attempt)
      [delay, RETRY_MAX_DELAY].min
    end
    
    def transient_error?(error)
      error.is_a?(Errno::ECONNRESET) ||
        error.is_a?(Errno::ECONNREFUSED) ||
        error.is_a?(EOFError)
    end
    
    def standard_request(uri, request)
      response = execute_request(uri, request)
      
      unless response.is_a?(Net::HTTPSuccess)
        handle_error_response(response)
      end
      
      JSON.parse(response.body)
    end
    
    def stream_request(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = API_CONNECT_TIMEOUT
      http.read_timeout = API_TIMEOUT
      
      buffer = ""
      full_content = ""
      
      http.request(request) do |response|
        unless response.is_a?(Net::HTTPSuccess)
          # Read full error response
          error_body = response.read_body
          handle_error_response_with_body(response, error_body)
        end
        
        response.read_body do |chunk|
          buffer += chunk
          
          # Process complete SSE events
          while buffer.include?("\n\n")
            event, buffer = buffer.split("\n\n", 2)
            
            event.lines.each do |line|
              next unless line.start_with?("data: ")
              
              data_json = line[6..-1].strip
              next if data_json == "[DONE]"
              
              begin
                data = JSON.parse(data_json)
                
                case data["type"]
                when "content_block_delta"
                  if data.dig("delta", "type") == "text_delta"
                    text = data.dig("delta", "text")
                    print text
                    $stdout.flush
                    full_content += text
                  end
                when "message_stop"
                  puts # New line after stream completes
                when "error"
                  raise APIError, "Streaming error: #{data['error']['message']}"
                end
              rescue JSON::ParserError => e
                debug "Failed to parse SSE data: #{e.message}"
              end
            end
          end
        end
      end
      
      { "content" => full_content }
    rescue => e
      raise StreamError, "Streaming failed: #{e.message}"
    end
    
    def handle_error_response(response)
      body = JSON.parse(response.body) rescue {}
      handle_error_response_with_body(response, body)
    end
    
    def handle_error_response_with_body(response, body)
      error_msg = body.is_a?(Hash) ? body.dig("error", "message") : body.to_s
      code = response.code.to_i
      
      case code
      when 401
        raise AuthenticationError, "Invalid API key. Run: claude config set api_key YOUR_KEY"
      when 403
        raise AuthenticationError, "Access forbidden. Check your API key permissions."
      when 429
        raise RateLimitError, "Rate limit exceeded. Please wait and try again."
      when 400..499
        raise ClientError, "Client error (#{code}): #{error_msg}"
      when 500..599
        raise ServerError, "Server error (#{code}): #{error_msg}. Try again later."
      else
        raise APIError, "API error (#{code}): #{error_msg}"
      end
    end
    
    def debug(msg)
      return unless @config.get("debug")
      warn "[DEBUG] #{msg}"
    end
  end
  
  # Session management with SQLite
  class SessionManager
    attr_reader :db_path
    
    def initialize(db_path = nil)
      @db_path = db_path || File.join(Dir.home, ".claude", "sessions.db")
      ensure_database
    end
    
    def ensure_database
      require "sqlite3"
      
      FileUtils.mkdir_p(File.dirname(@db_path))
      
      db = SQLite3::Database.new(@db_path)
      db.execute <<-SQL
        CREATE TABLE IF NOT EXISTS sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          total_tokens INTEGER DEFAULT 0,
          total_cost REAL DEFAULT 0.0,
          response_times TEXT DEFAULT '[]',
          master_checksum TEXT,
          tags TEXT DEFAULT '[]',
          messages TEXT NOT NULL
        )
      SQL
      db.close
      
      File.chmod(0600, @db_path) # Secure permissions
    rescue LoadError
      warn "Warning: sqlite3 gem not available. Sessions will not be persisted."
      @db_path = nil
    end
    
    def create_session(master_checksum: nil, tags: [])
      return nil unless @db_path
      
      db = SQLite3::Database.new(@db_path)
      now = Time.now.utc.iso8601
      
      db.execute(
        "INSERT INTO sessions (created_at, updated_at, master_checksum, tags, messages) VALUES (?, ?, ?, ?, ?)",
        now, now, master_checksum, JSON.generate(tags), JSON.generate([])
      )
      
      session_id = db.last_insert_row_id
      db.close
      session_id
    rescue => e
      warn "Warning: Failed to create session: #{e.message}"
      nil
    end
    
    def update_session(session_id, messages:, tokens: 0, cost: 0.0, response_time: nil)
      return unless @db_path && session_id
      
      db = SQLite3::Database.new(@db_path)
      
      # Get current values
      row = db.get_first_row("SELECT total_tokens, total_cost, response_times FROM sessions WHERE id = ?", session_id)
      return unless row
      
      total_tokens = row[0].to_i + tokens
      total_cost = row[1].to_f + cost
      response_times = JSON.parse(row[2])
      response_times << response_time if response_time
      
      db.execute(
        "UPDATE sessions SET updated_at = ?, messages = ?, total_tokens = ?, total_cost = ?, response_times = ? WHERE id = ?",
        Time.now.utc.iso8601,
        JSON.generate(messages),
        total_tokens,
        total_cost,
        JSON.generate(response_times),
        session_id
      )
      db.close
    rescue => e
      warn "Warning: Failed to update session: #{e.message}"
    end
    
    def get_session(session_id)
      return nil unless @db_path
      
      db = SQLite3::Database.new(@db_path)
      db.results_as_hash = true
      row = db.get_first_row("SELECT * FROM sessions WHERE id = ?", session_id)
      db.close
      
      return nil unless row
      
      {
        id: row["id"],
        created_at: row["created_at"],
        updated_at: row["updated_at"],
        total_tokens: row["total_tokens"],
        total_cost: row["total_cost"],
        avg_response_time: calculate_avg_response_time(row["response_times"]),
        master_checksum: row["master_checksum"],
        tags: JSON.parse(row["tags"]),
        messages: JSON.parse(row["messages"])
      }
    rescue => e
      warn "Warning: Failed to get session: #{e.message}"
      nil
    end
    
    def list_sessions(limit: 20)
      return [] unless @db_path
      
      db = SQLite3::Database.new(@db_path)
      db.results_as_hash = true
      rows = db.execute("SELECT id, created_at, updated_at, tags FROM sessions ORDER BY updated_at DESC LIMIT ?", limit)
      db.close
      
      rows.map do |row|
        {
          id: row["id"],
          created_at: row["created_at"],
          updated_at: row["updated_at"],
          tags: JSON.parse(row["tags"])
        }
      end
    rescue => e
      warn "Warning: Failed to list sessions: #{e.message}"
      []
    end
    
    def search_sessions(query)
      return [] unless @db_path
      
      db = SQLite3::Database.new(@db_path)
      db.results_as_hash = true
      rows = db.execute(
        "SELECT id, created_at, updated_at, tags FROM sessions WHERE messages LIKE ? OR tags LIKE ? ORDER BY updated_at DESC LIMIT 50",
        "%#{query}%", "%#{query}%"
      )
      db.close
      
      rows.map do |row|
        {
          id: row["id"],
          created_at: row["created_at"],
          updated_at: row["updated_at"],
          tags: JSON.parse(row["tags"])
        }
      end
    rescue => e
      warn "Warning: Failed to search sessions: #{e.message}"
      []
    end
    
    def add_tag(session_id, tag)
      return false unless @db_path && session_id
      
      db = SQLite3::Database.new(@db_path)
      row = db.get_first_row("SELECT tags FROM sessions WHERE id = ?", session_id)
      return false unless row
      
      tags = JSON.parse(row[0])
      unless tags.include?(tag)
        tags << tag
        db.execute(
          "UPDATE sessions SET tags = ?, updated_at = ? WHERE id = ?",
          JSON.generate(tags),
          Time.now.utc.iso8601,
          session_id
        )
      end
      db.close
      true
    rescue => e
      warn "Warning: Failed to add tag: #{e.message}"
      false
    end
    
    private
    
    def calculate_avg_response_time(response_times_json)
      times = JSON.parse(response_times_json)
      return 0.0 if times.empty?
      times.sum / times.size.to_f
    end
  end
  
  # Main CLI interface
  class CLI
    attr_reader :config, :client, :session_manager, :messages, :session_id
    
    def initialize
      @config = Config.new
      @client = APIClient.new(@config)
      @session_manager = SessionManager.new
      @messages = []
      @session_id = nil
      @stream_enabled = @config.get("stream")
      
      setup_pledge if PLEDGE_AVAILABLE
    end
    
    def setup_pledge
      # OpenBSD pledge: restrict system operations for security
      # Allow stdio, rpath (read files), wpath (write files), cpath (create files),
      # inet (network), dns (DNS lookups), tty (terminal I/O)
      begin
        libc = Fiddle::Handle.new(nil)
        pledge = Fiddle::Function.new(
          libc["pledge"],
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
          Fiddle::TYPE_INT
        )
        
        promises = "stdio rpath wpath cpath inet dns tty"
        result = pledge.call(Fiddle::Pointer[promises], nil)
        
        if result == 0
          puts "OpenBSD pledge activated: #{promises}"
        end
      rescue => e
        warn "Warning: Failed to setup pledge: #{e.message}"
      end
    end
    
    def run
      print_banner
      
      # Validate configuration
      errors = @config.validate
      if errors.any?
        puts "\nConfiguration errors:"
        errors.each { |e| puts "  ✗ #{e}" }
        puts "\nFix configuration errors before continuing."
        return
      end
      
      # Test API connection if key is set
      if @config.get("api_key")
        print "Testing API connection... "
        if @client.test_connection
          puts "OK"
        else
          puts "FAILED"
          puts "Warning: Could not connect to API. Check your configuration."
        end
      end
      
      # Start new session
      master_checksum = get_master_checksum
      @session_id = @session_manager.create_session(master_checksum: master_checksum)
      
      puts "\nType your message or use slash commands (/help for list)"
      puts "Press Ctrl+D or type /quit to exit\n\n"
      
      # Main interaction loop
      loop do
        begin
          input = Readline.readline("You: ", true)
          break if input.nil? # Ctrl+D
          
          input = input.strip
          next if input.empty?
          
          # Handle slash commands
          if input.start_with?("/")
            handle_command(input)
            next
          end
          
          # Send message to Claude
          send_message(input)
        rescue Interrupt
          puts "\nUse /quit to exit"
        rescue => e
          puts "\nError: #{e.message}"
          puts "Stack trace:" if @config.get("debug")
          puts e.backtrace.join("\n") if @config.get("debug")
        end
      end
      
      puts "\nGoodbye!"
    end
    
    def print_banner
      puts "=" * 60
      puts "Claude CLI v#{VERSION}"
      puts "=" * 60
      puts "Model: #{@config.get('model')}"
      puts "Streaming: #{@stream_enabled ? 'enabled' : 'disabled'}"
      puts "=" * 60
    end
    
    def handle_command(input)
      parts = input.split(/\s+/, 2)
      command = parts[0][1..-1] # Remove leading /
      args = parts[1] || ""
      
      case command
      when "help"
        print_help
      when "quit", "exit"
        exit 0
      when "stream"
        toggle_stream
      when "config"
        handle_config_command(args)
      when "master"
        handle_master_command(args)
      when "session"
        handle_session_command(args)
      when "clear"
        @messages = []
        puts "Conversation cleared"
      when "model"
        if args.empty?
          puts "Current model: #{@config.get('model')}"
        else
          begin
            @config.set("model", args.strip)
            puts "Model set to: #{args.strip}"
          rescue => e
            puts "Error: #{e.message}"
          end
        end
      when "tokens"
        if args.empty?
          puts "Current max_tokens: #{@config.get('max_tokens')}"
        else
          begin
            @config.set("max_tokens", args.strip.to_i)
            puts "max_tokens set to: #{args.strip.to_i}"
          rescue => e
            puts "Error: #{e.message}"
          end
        end
      when "temp", "temperature"
        if args.empty?
          puts "Current temperature: #{@config.get('temperature')}"
        else
          begin
            @config.set("temperature", args.strip.to_f)
            puts "Temperature set to: #{args.strip.to_f}"
          rescue => e
            puts "Error: #{e.message}"
          end
        end
      else
        puts "Unknown command: /#{command}"
        puts "Type /help for list of commands"
      end
    end
    
    def print_help
      puts <<~HELP
        
        Available Commands:
        
        Message Commands:
          /clear              Clear conversation history
          
        Streaming:
          /stream             Toggle streaming on/off
          
        Configuration:
          /config list        Show current configuration
          /config get <key>   Get configuration value
          /config set <key> <value>  Set configuration value
          /config save        Save configuration to disk
          /config validate    Validate configuration
          
        Model Settings:
          /model [name]       Show or set model
          /tokens [number]    Show or set max_tokens
          /temp [number]      Show or set temperature (0.0-1.0)
          
        Master.yml:
          /master validate    Validate master.yml schema
          
        Sessions:
          /session info       Show current session info
          /session list       List recent sessions
          /session load <id>  Load a previous session
          /session search <query>  Search sessions
          /session tag <tag>  Add tag to current session
          
        Other:
          /help               Show this help
          /quit, /exit        Exit the CLI
        
      HELP
    end
    
    def toggle_stream
      @stream_enabled = !@stream_enabled
      puts "Streaming #{@stream_enabled ? 'enabled' : 'disabled'}"
    end
    
    def handle_config_command(args)
      parts = args.split(/\s+/, 2)
      subcommand = parts[0]
      
      case subcommand
      when "list"
        puts "\nCurrent Configuration:"
        @config.data.each do |key, value|
          display_value = key == "api_key" && value ? "#{value[0..7]}..." : value
          puts "  #{key}: #{display_value}"
        end
      when "get"
        key = parts[1]
        if key
          value = @config.get(key)
          display_value = key == "api_key" && value ? "#{value[0..7]}..." : value
          puts "#{key}: #{display_value}"
        else
          puts "Usage: /config get <key>"
        end
      when "set"
        key_value = parts[1]
        if key_value && key_value.include?(" ")
          key, value = key_value.split(/\s+/, 2)
          begin
            @config.set(key, value)
            puts "Configuration updated: #{key} = #{value}"
            
            # Test connection if API credentials were changed
            if key == "api_key" || key == "api_base"
              print "Testing API connection... "
              if @client.test_connection
                puts "OK"
              else
                puts "FAILED"
              end
            end
          rescue => e
            puts "Error: #{e.message}"
          end
        else
          puts "Usage: /config set <key> <value>"
        end
      when "save"
        if @config.save
          puts "Configuration saved to #{@config.path}"
        else
          puts "Failed to save configuration"
        end
      when "validate"
        errors = @config.validate
        if errors.any?
          puts "\nConfiguration errors:"
          errors.each { |e| puts "  ✗ #{e}" }
        else
          puts "✓ Configuration is valid"
        end
      else
        puts "Usage: /config [list|get|set|save|validate]"
      end
    end
    
    def handle_master_command(args)
      case args.strip
      when "validate"
        master_path = find_master_yml
        if master_path
          validator = MasterValidator.new(master_path)
          validator.validate
          validator.report
        else
          puts "master.yml not found in standard locations"
        end
      else
        puts "Usage: /master validate"
      end
    end
    
    def handle_session_command(args)
      parts = args.split(/\s+/, 2)
      subcommand = parts[0]
      
      case subcommand
      when "info"
        if @session_id
          session = @session_manager.get_session(@session_id)
          puts "\nSession Info:"
          puts "  ID: #{session[:id]}"
          puts "  Created: #{session[:created_at]}"
          puts "  Updated: #{session[:updated_at]}"
          puts "  Total tokens: #{session[:total_tokens]}"
          puts "  Total cost: $#{format('%.4f', session[:total_cost])}"
          puts "  Avg response time: #{format('%.2f', session[:avg_response_time])}s"
          puts "  Master checksum: #{session[:master_checksum] || 'N/A'}"
          puts "  Tags: #{session[:tags].join(', ')}" if session[:tags].any?
          puts "  Messages: #{session[:messages].size}"
        else
          puts "No active session"
        end
      when "list"
        sessions = @session_manager.list_sessions
        if sessions.any?
          puts "\nRecent Sessions:"
          sessions.each do |s|
            tags_str = s[:tags].any? ? " [#{s[:tags].join(', ')}]" : ""
            puts "  #{s[:id]}: #{s[:updated_at]}#{tags_str}"
          end
        else
          puts "No sessions found"
        end
      when "load"
        session_id = parts[1].to_i
        session = @session_manager.get_session(session_id)
        if session
          @session_id = session[:id]
          @messages = session[:messages]
          puts "Loaded session #{session_id} with #{@messages.size} messages"
        else
          puts "Session not found: #{session_id}"
        end
      when "search"
        query = parts[1]
        if query
          sessions = @session_manager.search_sessions(query)
          if sessions.any?
            puts "\nSearch Results for '#{query}':"
            sessions.each do |s|
              tags_str = s[:tags].any? ? " [#{s[:tags].join(', ')}]" : ""
              puts "  #{s[:id]}: #{s[:updated_at]}#{tags_str}"
            end
          else
            puts "No sessions found matching '#{query}'"
          end
        else
          puts "Usage: /session search <query>"
        end
      when "tag"
        tag = parts[1]
        if tag && @session_id
          if @session_manager.add_tag(@session_id, tag)
            puts "Tag '#{tag}' added to session"
          else
            puts "Failed to add tag"
          end
        else
          puts "Usage: /session tag <tag>"
        end
      else
        puts "Usage: /session [info|list|load|search|tag]"
      end
    end
    
    def send_message(user_input)
      @messages << { role: "user", content: user_input }
      
      print "Claude: " unless @stream_enabled
      
      start_time = Time.now
      
      begin
        response = @client.send_message(@messages, stream: @stream_enabled)
        
        response_time = Time.now - start_time
        
        # Extract response content
        content = if @stream_enabled
          response["content"]
        else
          text = response.dig("content", 0, "text") || ""
          puts text
          text
        end
        
        # Add assistant response to messages
        @messages << { role: "assistant", content: content }
        
        # Update session with token usage
        tokens = response.dig("usage", "total_tokens") || 0
        cost = calculate_cost(tokens)
        
        @session_manager.update_session(
          @session_id,
          messages: @messages,
          tokens: tokens,
          cost: cost,
          response_time: response_time
        )
        
        puts if @stream_enabled # Extra newline after streaming
      rescue AuthenticationError, ClientError, ServerError, RateLimitError, TimeoutError => e
        puts "\n#{e.class.name}: #{e.message}"
        @messages.pop # Remove failed message
      end
    end
    
    def calculate_cost(tokens)
      # Rough cost estimation (would need actual pricing per model)
      # Claude 3.5 Sonnet: ~$3/$15 per million tokens (input/output)
      # Using average of $9 per million tokens as rough estimate
      tokens * 0.000009
    end
    
    def find_master_yml
      paths = [
        File.join(Dir.pwd, "master.yml"),
        File.join(Dir.home, "pub", "master.yml"),
        "G:/pub/master.yml"
      ]
      
      paths.find { |p| File.exist?(p) }
    end
    
    def get_master_checksum
      master_path = find_master_yml
      return nil unless master_path
      
      validator = MasterValidator.new(master_path)
      validator.checksum
    end
  end
  
  # Custom exceptions
  class APIError < StandardError; end
  class AuthenticationError < APIError; end
  class ClientError < APIError; end
  class ServerError < APIError; end
  class RateLimitError < APIError; end
  class StreamError < APIError; end
  class TimeoutError < APIError; end
end

# Run CLI if executed directly
if __FILE__ == $PROGRAM_NAME
  Claude::CLI.new.run
end
