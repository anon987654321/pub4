# frozen_string_literal: true

require 'sqlite3'
require 'digest'
require 'json'
require 'fileutils'

# RAG Engine with Vector Storage and Cognitive Integration
class RAGEngine
  attr_reader :vector_db, :embedding_cache, :cognitive_monitor

  def initialize(db_path: 'data/vector_store.db')
    @db_path = db_path
    @vector_db = setup_vector_database
    @embedding_cache = {}
    @cognitive_monitor = nil
    @chunk_size = 500
    @overlap_size = 50
  end

  # Set cognitive monitor for load-aware processing
  def set_cognitive_monitor(monitor)
    @cognitive_monitor = monitor
  end

  # Add documents to vector store
  def add_documents(documents, collection: 'default')
    documents.each do |doc|
      add_document(doc, collection: collection)
    end
  end

  # Add single document with chunking
  def add_document(document, collection: 'default')
    # Check cognitive load before processing
    if @cognitive_monitor&.cognitive_overload?
      puts '🧠 Cognitive overload detected, deferring document indexing'
      return false
    end

    chunks = chunk_document(document)
    doc_id = generate_document_id(document)

    chunks.each_with_index do |chunk, index|
      embedding = generate_embedding(chunk[:text])

      @vector_db.execute(
        'INSERT INTO vectors (doc_id, chunk_id, collection, content, embedding, metadata, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          doc_id,
          index,
          collection,
          chunk[:text],
          embedding.to_json,
          chunk[:metadata].to_json,
          Time.now.to_i
        ]
      )
    end

    puts "📚 Added document #{doc_id} with #{chunks.size} chunks to collection '#{collection}'"
    true
  end

  # Search documents with cognitive load awareness
  def search(query, collection: 'default', limit: 5, similarity_threshold: 0.7)
    # Assess query complexity
    if @cognitive_monitor
      complexity = @cognitive_monitor.assess_complexity(query)
      if complexity > 5
        puts '🧠 High complexity query detected, applying cognitive optimization'
        limit = [limit, 3].min # Reduce results for high complexity
      end
    end

    query_embedding = generate_embedding(query)

    # Get all vectors from collection
    rows = @vector_db.execute(
      'SELECT doc_id, chunk_id, content, embedding, metadata FROM vectors WHERE collection = ? ORDER BY created_at DESC',
      [collection]
    )

    # Calculate similarities
    similarities = []
    rows.each do |row|
      doc_id, chunk_id, content, embedding_json, metadata_json = row
      stored_embedding = JSON.parse(embedding_json)

      similarity = cosine_similarity(query_embedding, stored_embedding)

      next unless similarity >= similarity_threshold

      similarities << {
        doc_id: doc_id,
        chunk_id: chunk_id,
        content: content,
        similarity: similarity,
        metadata: JSON.parse(metadata_json)
      }
    end

    # Sort by similarity and return top results
    results = similarities.sort_by { |r| -r[:similarity] }.take(limit)

    # Update cognitive load if monitor is available
    if @cognitive_monitor
      @cognitive_monitor.add_concept('RAG_SEARCH', 1.0)
      results.each { |r| @cognitive_monitor.add_concept(r[:content][0..50], 0.5) }
    end

    results
  end

  # Enhanced search with context
  def search_with_context(query, context: {}, collection: 'default', limit: 5)
    # Enhance query with context
    enhanced_query = enhance_query_with_context(query, context)

    results = search(enhanced_query, collection: collection, limit: limit)

    # Add context relevance scoring
    results.map do |result|
      result[:context_relevance] = calculate_context_relevance(result, context)
      result
    end.sort_by { |r| -((r[:similarity] * 0.7) + (r[:context_relevance] * 0.3)) }
  end

  # Get collections
  def collections
    rows = @vector_db.execute('SELECT DISTINCT collection FROM vectors ORDER BY collection')
    rows.map { |row| row[0] }
  end

  # Get collection stats
  def collection_stats(collection = nil)
    if collection
      rows = @vector_db.execute(
        'SELECT COUNT(*) as count, COUNT(DISTINCT doc_id) as docs FROM vectors WHERE collection = ?',
        [collection]
      )
      { collection: collection, chunks: rows[0][0], documents: rows[0][1] }
    else
      stats = {}
      collections.each do |coll|
        stats[coll] = collection_stats(coll)
      end
      stats
    end
  end

  # Clear collection
  def clear_collection(collection)
    @vector_db.execute('DELETE FROM vectors WHERE collection = ?', [collection])
    puts "🗑️ Cleared collection '#{collection}'"
  end

  # Get similar documents
  def get_similar_documents(doc_id, limit: 5)
    # Get the document's chunks
    doc_chunks = @vector_db.execute(
      'SELECT embedding FROM vectors WHERE doc_id = ?',
      [doc_id]
    )

    return [] if doc_chunks.empty?

    # Calculate average embedding for the document
    embeddings = doc_chunks.map { |row| JSON.parse(row[0]) }
    avg_embedding = calculate_average_embedding(embeddings)

    # Find similar documents
    all_docs = @vector_db.execute(
      'SELECT DISTINCT doc_id FROM vectors WHERE doc_id != ?',
      [doc_id]
    )

    similarities = []
    all_docs.each do |row|
      other_doc_id = row[0]
      other_chunks = @vector_db.execute(
        'SELECT embedding FROM vectors WHERE doc_id = ?',
        [other_doc_id]
      )

      other_embeddings = other_chunks.map { |r| JSON.parse(r[0]) }
      other_avg = calculate_average_embedding(other_embeddings)

      similarity = cosine_similarity(avg_embedding, other_avg)
      similarities << { doc_id: other_doc_id, similarity: similarity }
    end

    similarities.sort_by { |s| -s[:similarity] }.take(limit)
  end

  private

  # Setup vector database
  def setup_vector_database
    # Ensure data directory exists
    FileUtils.mkdir_p(File.dirname(@db_path))

    db = SQLite3::Database.new(@db_path)

    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS vectors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        doc_id TEXT NOT NULL,
        chunk_id INTEGER NOT NULL,
        collection TEXT NOT NULL DEFAULT 'default',
        content TEXT NOT NULL,
        embedding TEXT NOT NULL,
        metadata TEXT NOT NULL DEFAULT '{}',
        created_at INTEGER NOT NULL
      )
    SQL

    # Create indexes for better performance
    db.execute 'CREATE INDEX IF NOT EXISTS idx_doc_id ON vectors(doc_id)'
    db.execute 'CREATE INDEX IF NOT EXISTS idx_collection ON vectors(collection)'
    db.execute 'CREATE INDEX IF NOT EXISTS idx_created_at ON vectors(created_at)'

    db
  end

  # Chunk document into smaller pieces
  def chunk_document(document)
    content = document.is_a?(Hash) ? document[:content] || document['content'] || document.to_s : document.to_s
    title = document.is_a?(Hash) ? document[:title] || document['title'] : nil

    chunks = []

    # Simple chunking by character count
    start_pos = 0
    chunk_id = 0

    while start_pos < content.length
      end_pos = [start_pos + @chunk_size, content.length].min

      # Try to break at word boundary
      if end_pos < content.length
        last_space = content.rindex(' ', end_pos)
        end_pos = last_space if last_space && last_space > start_pos + (@chunk_size * 0.8)
      end

      chunk_text = content[start_pos...end_pos].strip
      next if chunk_text.empty?

      chunks << {
        text: chunk_text,
        metadata: {
          chunk_id: chunk_id,
          start_pos: start_pos,
          end_pos: end_pos,
          title: title,
          length: chunk_text.length
        }
      }

      chunk_id += 1
      start_pos = end_pos - @overlap_size
      start_pos = [start_pos, 0].max
    end

    chunks
  end

  # Generate simple document ID
  def generate_document_id(document)
    content = document.is_a?(Hash) ? document.to_json : document.to_s
    Digest::SHA256.hexdigest(content)[0..15]
  end

  # Generate simple embedding (TF-IDF style)
  def generate_embedding(text)
    # Simple word-based embedding - can be enhanced with proper embeddings
    words = text.downcase.scan(/\w+/)
    word_counts = Hash.new(0)

    words.each { |word| word_counts[word] += 1 }

    # Create a simple vector based on word frequencies
    # In a real implementation, this would use a proper embedding model
    vocabulary = get_vocabulary

    embedding = Array.new(vocabulary.size, 0.0)
    word_counts.each do |word, count|
      next unless (index = vocabulary.index(word))

      # Simple TF-IDF approximation
      tf = count.to_f / words.size
      idf = Math.log(1000.0 / (count + 1)) # Simplified IDF
      embedding[index] = tf * idf
    end

    # Normalize vector
    magnitude = Math.sqrt(embedding.sum { |x| x * x })
    magnitude > 0 ? embedding.map { |x| x / magnitude } : embedding
  end

  # Get simplified vocabulary (in practice, this would be much larger)
  def get_vocabulary
    @vocabulary ||= %w[
      the and for are but not you all can had her was one our out day get has him
      his how man new now old see two who its did yes his been more very what know just
      first also after back other many family over right during national history american
      while where much place these give what why ask turn thought help away again play
      small found still between name right change here why ask turn thought help
      computer technology data science machine learning artificial intelligence
      business market financial economic social political cultural health medical
      science research development innovation create build design implement system
      process method approach solution problem challenge opportunity goal objective
      strategy plan project management organization team collaboration communication
      information knowledge understanding analysis evaluation assessment measurement
      quality performance efficiency effectiveness improvement optimization
    ]
  end

  # Calculate cosine similarity between two vectors
  def cosine_similarity(vec1, vec2)
    return 0.0 if vec1.size != vec2.size

    dot_product = vec1.zip(vec2).sum { |a, b| a * b }
    magnitude1 = Math.sqrt(vec1.sum { |x| x * x })
    magnitude2 = Math.sqrt(vec2.sum { |x| x * x })

    return 0.0 if magnitude1 == 0 || magnitude2 == 0

    dot_product / (magnitude1 * magnitude2)
  end

  # Enhance query with context
  def enhance_query_with_context(query, context)
    enhanced_parts = [query]

    enhanced_parts << "related to #{context[:domain]}" if context[:domain]

    enhanced_parts << "for #{context[:user_intent]}" if context[:user_intent]

    enhanced_parts << "considering #{context[:previous_topics].join(', ')}" if context[:previous_topics]

    enhanced_parts.join(' ')
  end

  # Calculate context relevance
  def calculate_context_relevance(result, context)
    relevance = 0.0

    # Domain matching
    relevance += 0.3 if context[:domain] && result[:content].downcase.include?(context[:domain].downcase)

    # Intent matching
    relevance += 0.4 if context[:user_intent] && result[:content].downcase.include?(context[:user_intent].downcase)

    # Topic matching
    if context[:previous_topics]
      matching_topics = context[:previous_topics].count do |topic|
        result[:content].downcase.include?(topic.downcase)
      end
      relevance += (matching_topics.to_f / context[:previous_topics].size) * 0.3
    end

    [relevance, 1.0].min
  end

  # Calculate average embedding from multiple embeddings
  def calculate_average_embedding(embeddings)
    return [] if embeddings.empty?

    size = embeddings.first.size
    avg_embedding = Array.new(size, 0.0)

    embeddings.each do |embedding|
      embedding.each_with_index do |value, index|
        avg_embedding[index] += value
      end
    end

    avg_embedding.map { |value| value / embeddings.size }
  end
end
