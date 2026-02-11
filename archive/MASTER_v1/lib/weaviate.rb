# frozen_string_literal: true

require 'net/http'
require 'json'

module MASTER
  # Weaviate vector database wrapper
  # Semantic memory, similarity search, concept storage
  class Weaviate
    DEFAULT_HOST = ENV.fetch('WEAVIATE_HOST', 'localhost')
    DEFAULT_PORT = ENV.fetch('WEAVIATE_PORT', '8080').to_i
    BATCH_SIZE = 100
    TIMEOUT = 30

    def initialize(host: DEFAULT_HOST, port: DEFAULT_PORT, api_key: nil)
      @host = host
      @port = port
      @api_key = api_key || ENV['WEAVIATE_API_KEY']
      @base_url = "http://#{@host}:#{@port}/v1"
    end

    # Health check
    def healthy?
      get('/meta')
      true
    rescue StandardError
      false
    end

    # Create schema class for storing objects
    def create_class(name, properties: [], vectorizer: 'none')
      payload = {
        class: name,
        vectorizer: vectorizer,
        properties: properties.map do |prop|
          { name: prop[:name], dataType: [prop[:type] || 'text'] }
        end
      }
      post('/schema', payload)
    end

    # Delete schema class
    def delete_class(name)
      delete("/schema/#{name}")
    end

    # List all classes
    def list_classes
      response = get('/schema')
      response['classes']&.map { |c| c['class'] } || []
    end

    # Add object with optional vector
    def add(class_name, properties, vector: nil, id: nil)
      payload = { class: class_name, properties: properties }
      payload[:vector] = vector if vector
      payload[:id] = id if id
      post('/objects', payload)
    end

    # Batch add objects
    def batch_add(class_name, objects)
      objects.each_slice(BATCH_SIZE) do |batch|
        payload = {
          objects: batch.map do |obj|
            { class: class_name, properties: obj[:properties], vector: obj[:vector] }
          end
        }
        post('/batch/objects', payload)
      end
    end

    # Get object by ID
    def get_object(class_name, id)
      get("/objects/#{class_name}/#{id}")
    end

    # Delete object by ID
    def delete_object(class_name, id)
      delete("/objects/#{class_name}/#{id}")
    end

    # Vector similarity search
    def search(class_name, vector:, limit: 10, fields: ['*'])
      query = {
        query: graphql_near_vector(class_name, vector, limit, fields)
      }
      response = post('/graphql', query)
      extract_results(response, class_name)
    end

    # Semantic search with text (requires text2vec module)
    def semantic_search(class_name, text:, limit: 10, fields: ['*'])
      query = {
        query: graphql_near_text(class_name, text, limit, fields)
      }
      response = post('/graphql', query)
      extract_results(response, class_name)
    end

    # Hybrid search (vector + keyword)
    def hybrid_search(class_name, query:, vector: nil, limit: 10, fields: ['*'], alpha: 0.5)
      gql = graphql_hybrid(class_name, query, vector, limit, fields, alpha)
      response = post('/graphql', { query: gql })
      extract_results(response, class_name)
    end

    # Count objects in class
    def count(class_name)
      query = {
        query: "{ Aggregate { #{class_name} { meta { count } } } }"
      }
      response = post('/graphql', query)
      response.dig('data', 'Aggregate', class_name, 0, 'meta', 'count') || 0
    end

    # Store code snippet with embedding
    def store_code(code, metadata = {})
      ensure_code_class
      properties = {
        content: code[0..10_000],
        language: metadata[:language] || 'ruby',
        file: metadata[:file] || 'unknown',
        timestamp: Time.now.iso8601
      }
      add('CodeSnippet', properties, vector: metadata[:vector])
    end

    # Store principle for semantic matching
    def store_principle(name, description, examples = [])
      ensure_principles_class
      properties = {
        name: name,
        description: description,
        examples: examples.join("\n")
      }
      add('Principle', properties)
    end

    # Store memory/context for sessions
    def store_memory(content, session_id:, type: 'context')
      ensure_memory_class
      properties = {
        content: content[0..50_000],
        session_id: session_id,
        type: type,
        timestamp: Time.now.iso8601
      }
      add('Memory', properties)
    end

    # Find similar code
    def find_similar_code(vector, limit: 5)
      search('CodeSnippet', vector: vector, limit: limit, fields: %w[content language file])
    end

    # Find relevant principles
    def find_principles(text, limit: 5)
      semantic_search('Principle', text: text, limit: limit, fields: %w[name description examples])
    end

    # Retrieve session memories
    def recall_memories(session_id, limit: 20)
      query = {
        query: <<~GQL
          {
            Get {
              Memory(
                where: { path: ["session_id"], operator: Equal, valueText: "#{session_id}" }
                limit: #{limit}
              ) { content type timestamp }
            }
          }
        GQL
      }
      response = post('/graphql', query)
      extract_results(response, 'Memory')
    end

    private

    def ensure_code_class
      return if list_classes.include?('CodeSnippet')
      create_class('CodeSnippet', properties: [
        { name: 'content', type: 'text' },
        { name: 'language', type: 'text' },
        { name: 'file', type: 'text' },
        { name: 'timestamp', type: 'text' }
      ])
    end

    def ensure_principles_class
      return if list_classes.include?('Principle')
      create_class('Principle', properties: [
        { name: 'name', type: 'text' },
        { name: 'description', type: 'text' },
        { name: 'examples', type: 'text' }
      ])
    end

    def ensure_memory_class
      return if list_classes.include?('Memory')
      create_class('Memory', properties: [
        { name: 'content', type: 'text' },
        { name: 'session_id', type: 'text' },
        { name: 'type', type: 'text' },
        { name: 'timestamp', type: 'text' }
      ])
    end

    def graphql_near_vector(class_name, vector, limit, fields)
      <<~GQL
        {
          Get {
            #{class_name}(
              nearVector: { vector: #{vector.to_json} }
              limit: #{limit}
            ) { #{fields.join(' ')} _additional { distance } }
          }
        }
      GQL
    end

    def graphql_near_text(class_name, text, limit, fields)
      <<~GQL
        {
          Get {
            #{class_name}(
              nearText: { concepts: #{[text].to_json} }
              limit: #{limit}
            ) { #{fields.join(' ')} _additional { distance } }
          }
        }
      GQL
    end

    def graphql_hybrid(class_name, query, vector, limit, fields, alpha)
      vector_part = vector ? ", vector: #{vector.to_json}" : ''
      <<~GQL
        {
          Get {
            #{class_name}(
              hybrid: { query: #{query.to_json}, alpha: #{alpha}#{vector_part} }
              limit: #{limit}
            ) { #{fields.join(' ')} _additional { score } }
          }
        }
      GQL
    end

    def extract_results(response, class_name)
      response.dig('data', 'Get', class_name) || []
    end

    def get(path)
      request(Net::HTTP::Get, path)
    end

    def post(path, body)
      request(Net::HTTP::Post, path, body)
    end

    def delete(path)
      request(Net::HTTP::Delete, path)
    end

    def request(method_class, path, body = nil)
      uri = URI("#{@base_url}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.read_timeout = TIMEOUT

      req = method_class.new(uri)
      req['Content-Type'] = 'application/json'
      req['Authorization'] = "Bearer #{@api_key}" if @api_key
      req.body = body.to_json if body

      response = http.request(req)
      JSON.parse(response.body)
    rescue JSON::ParserError
      {}
    end
  end
end
