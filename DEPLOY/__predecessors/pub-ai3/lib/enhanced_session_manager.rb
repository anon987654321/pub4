# frozen_string_literal: true

require_relative 'cognitive_orchestrator'
require 'sqlite3'
require 'openssl'
require 'digest'
require 'securerandom'
require 'json'

# Enhanced Session Manager with Cognitive Load Awareness
# Implements LRU eviction with 7±2 working memory principles
class EnhancedSessionManager
  attr_accessor :sessions, :max_sessions, :eviction_strategy, :cognitive_monitor

  def initialize(max_sessions: 10, eviction_strategy: :cognitive_load_aware)
    @sessions = {}
    @max_sessions = max_sessions
    @eviction_strategy = eviction_strategy
    @cognitive_monitor = CognitiveOrchestrator.new
    @db = setup_database
    @cipher = OpenSSL::Cipher.new('AES-256-CBC')
  end

  # Create a new session with cognitive load tracking
  def create_session(user_id)
    evict_session if @sessions.size >= @max_sessions

    @sessions[user_id] = {
      context: {},
      timestamp: Time.now,
      cognitive_load: 0,
      concept_count: 0,
      flow_state: 'optimal',
      session_id: SecureRandom.hex(8)
    }

    store_session_to_db(user_id, @sessions[user_id])
    @sessions[user_id]
  end

  # Get or create session for user
  def get_session(user_id)
    @sessions[user_id] ||= load_session_from_db(user_id) || create_session(user_id)
  end

  # Update session with cognitive load assessment
  def update_session(user_id, new_context)
    session = get_session(user_id)

    # Assess cognitive complexity of new context
    cognitive_delta = @cognitive_monitor.assess_complexity(new_context.to_s)

    # Circuit breaker for cognitive overload
    if session[:cognitive_load] + cognitive_delta > 7
      preserve_flow_state(session)
      session[:context] = compress_context(session[:context])
      session[:cognitive_load] = 3 # Reset to manageable level
      puts "🧠 Cognitive load reset for session #{user_id}"
    end

    # Update session data with advanced context merging
    if new_context.is_a?(Hash)
      session[:context] = merge_context_intelligently(session[:context], new_context)
    end
    session[:timestamp] = Time.now
    session[:cognitive_load] += cognitive_delta
    session[:concept_count] = count_concepts(session[:context])

    # Update flow state
    session[:flow_state] = determine_flow_state(session[:cognitive_load])

    # Store updated session
    store_session_to_db(user_id, session)

    session
  end

  # Advanced context merging with merge! capabilities
  def merge_context_intelligently(existing_context, new_context)
    merged = existing_context.dup

    new_context.each do |key, value|
      if merged.key?(key)
        # Smart merging based on value types
        case [merged[key].class, value.class]
        when [Hash, Hash]
          merged[key] = merge_context_intelligently(merged[key], value)
        when [Array, Array]
          merged[key] = (merged[key] + value).uniq
        when [String, String]
          # Concatenate strings with separator if they're different
          merged[key] = merged[key] == value ? value : "#{merged[key]} | #{value}"
        else
          # Replace with new value for different types
          merged[key] = value
        end
      else
        merged[key] = value
      end
    end

    merged
  end

  # Store context with encryption
  def store_context(user_id, text)
    session = get_session(user_id)
    encrypted_text = encrypt_text(text)

    @db.execute(
      'INSERT INTO sessions (user_id, session_id, context, created_at) VALUES (?, ?, ?, ?)',
      [user_id, session[:session_id], encrypted_text, Time.now.to_i]
    )
  end

  # Get context with decryption
  def get_context(user_id, limit: 5)
    get_session(user_id)

    rows = @db.execute(
      'SELECT context FROM sessions WHERE user_id = ? ORDER BY created_at DESC LIMIT ?',
      [user_id, limit]
    )

    rows.map do |row|
      decrypt_text(row[0])
    end
  rescue StandardError => e
    puts "Session error: #{e.message}"
    []
  end

  # Remove specific session
  def remove_session(user_id)
    @sessions.delete(user_id)
    @db.execute('DELETE FROM sessions WHERE user_id = ?', [user_id])
  end

  # List all active session IDs
  def list_active_sessions
    @sessions.keys
  end

  # Clear all sessions for cognitive reset
  def clear_all_sessions
    @sessions.clear
    @db.execute('DELETE FROM sessions')
    @cognitive_monitor = CognitiveOrchestrator.new
  end

  # Get session count for cognitive load monitoring
  def session_count
    @sessions.size
  end

  # Get cognitive load percentage across all sessions
  def cognitive_load_percentage
    return 0 if @sessions.empty?

    total_load = @sessions.values.sum { |s| s[:cognitive_load] }
    max_load = @sessions.size * 7 # 7 is the cognitive limit per session

    (total_load / max_load * 100).round(2)
  end

  # Get detailed cognitive state
  def cognitive_state
    overloaded_sessions = @sessions.count { |_, s| s[:cognitive_load] > 7 }

    {
      total_sessions: @sessions.size,
      cognitive_load_percentage: cognitive_load_percentage,
      overloaded_sessions: overloaded_sessions,
      average_concept_count: average_concept_count,
      flow_state_distribution: flow_state_distribution,
      cognitive_health: determine_cognitive_health
    }
  end

  # Trigger cognitive break for all sessions
  def trigger_cognitive_break
    @sessions.each do |user_id, session|
      next unless session[:cognitive_load] > 5

      preserve_flow_state(session)
      session[:cognitive_load] = 3
      session[:context] = compress_context(session[:context])
      store_session_to_db(user_id, session)
    end

    puts '🌱 Cognitive break triggered for all overloaded sessions'
  end

  private

  # Setup SQLite database for session storage
  def setup_database
    db = SQLite3::Database.new('data/sessions.db')

    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        context TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    SQL

    db.execute 'CREATE INDEX IF NOT EXISTS idx_user_id ON sessions(user_id)'
    db.execute 'CREATE INDEX IF NOT EXISTS idx_created_at ON sessions(created_at)'

    db
  end

  # Encrypt text for secure storage
  def encrypt_text(text)
    @cipher.encrypt
    @cipher.key = Digest::SHA256.digest(ENV['SESSION_KEY'] || 'ai3_default_key')
    @cipher.iv = iv = @cipher.random_iv

    encrypted = @cipher.update(text) + @cipher.final
    (iv + encrypted).unpack1('H*')
  end

  # Decrypt text from storage
  def decrypt_text(hex_data)
    data = [hex_data].pack('H*')
    iv = data[0, 16]
    encrypted = data[16..-1]

    @cipher.decrypt
    @cipher.key = Digest::SHA256.digest(ENV['SESSION_KEY'] || 'ai3_default_key')
    @cipher.iv = iv

    @cipher.update(encrypted) + @cipher.final
  end

  # Store session to database
  def store_session_to_db(user_id, session)
    # Remove database handle and other non-serializable objects
    serializable_session = session.dup
    serializable_session.delete(:db)

    encrypted_session = encrypt_text(serializable_session.to_json)

    @db.execute(
      'INSERT OR REPLACE INTO sessions (user_id, session_id, context, created_at) VALUES (?, ?, ?, ?)',
      [user_id, session[:session_id], encrypted_session, Time.now.to_i]
    )
  end

  # Load session from database
  def load_session_from_db(user_id)
    rows = @db.execute(
      'SELECT context FROM sessions WHERE user_id = ? ORDER BY created_at DESC LIMIT 1',
      [user_id]
    )

    return nil if rows.empty?

    session_data = decrypt_text(rows[0][0])
    JSON.parse(session_data, symbolize_names: true)
  rescue StandardError
    nil
  end

  # Evict session based on strategy
  def evict_session
    case @eviction_strategy
    when :cognitive_load_aware
      remove_highest_load_session
    when :least_recently_used, :oldest
      remove_oldest_session
    else
      raise "Unknown eviction strategy: #{@eviction_strategy}"
    end
  end

  # Remove session with highest cognitive load
  def remove_highest_load_session
    return if @sessions.empty?

    highest_load_user = @sessions.max_by do |_user_id, session|
      session[:cognitive_load]
    end[0]

    puts "🧠 Evicting high cognitive load session: #{highest_load_user}"
    remove_session(highest_load_user)
  end

  # Remove the oldest session by timestamp
  def remove_oldest_session
    return if @sessions.empty?

    oldest_user_id = @sessions.min_by { |_user_id, session| session[:timestamp] }[0]
    remove_session(oldest_user_id)
  end

  # Preserve flow state before compression
  def preserve_flow_state(session)
    session[:flow_state_backup] = {
      key_concepts: extract_key_concepts(session[:context]),
      attention_focus: session[:context][:current_focus],
      preserved_at: Time.now
    }
  end

  # Compress context to reduce cognitive load
  def compress_context(context)
    return {} unless context.is_a?(Hash)

    # Preserve only the most relevant 3-5 concepts
    key_concepts = extract_key_concepts(context)

    {
      compressed: true,
      key_concepts: key_concepts,
      compression_timestamp: Time.now,
      original_size: context.keys.size
    }
  end

  # Extract key concepts from context
  def extract_key_concepts(context)
    return [] unless context.is_a?(Hash)

    # Simple key extraction - can be enhanced with NLP
    concepts = []
    context.each do |key, value|
      if value.is_a?(String) && value.length > 10
        concepts << { key: key, preview: value[0..50] }
      elsif value.is_a?(Hash)
        concepts << { key: key, type: 'nested_object' }
      end
    end

    concepts.take(5) # Keep top 5 concepts
  end

  # Count concepts in context
  def count_concepts(context)
    return 0 unless context.is_a?(Hash)

    count = context.keys.size
    context.each_value do |value|
      count += count_concepts(value) if value.is_a?(Hash)
    end

    count
  end

  # Determine flow state based on cognitive load
  def determine_flow_state(cognitive_load)
    case cognitive_load
    when 0..2
      'optimal'
    when 3..5
      'focused'
    when 6..7
      'challenged'
    else
      'overloaded'
    end
  end

  # Calculate average concept count across sessions
  def average_concept_count
    return 0 if @sessions.empty?

    total_concepts = @sessions.values.sum { |s| s[:concept_count] }
    (total_concepts.to_f / @sessions.size).round(2)
  end

  # Get flow state distribution
  def flow_state_distribution
    distribution = Hash.new(0)
    @sessions.each_value { |s| distribution[s[:flow_state]] += 1 }
    distribution
  end

  # Determine overall cognitive health
  def determine_cognitive_health
    return 'excellent' if @sessions.empty?

    overloaded_ratio = @sessions.count { |_, s| s[:cognitive_load] > 7 }.to_f / @sessions.size

    case overloaded_ratio
    when 0
      'excellent'
    when 0..0.2
      'good'
    when 0.2..0.5
      'fair'
    else
      'poor'
    end
  end
end
