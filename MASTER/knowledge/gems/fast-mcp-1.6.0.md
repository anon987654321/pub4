require 'fast_mcp'

server = FastMcp::Server.new(name: 'my-ai-server', version: '1.0.0')

class SummarizeTool < FastMcp::Tool  description "Summarize text"

  arguments do
    required(:text).filled(:string)
    optional(:max_length).filled(:integer)
  end

  def call(text:, max_length: 100)
    text.split('.').first(3).join('.') + '...'
  end
end

server.register_tool(SummarizeTool)

class StatsResource < FastMcp::Resource
  uri 'data/stats'
  resource_name 'Stats'
  mime_type 'application/json'

  def content
    JSON.generate(users_online: 120, queries_per_minute: 250)
  end
end

server.register_resource(StatsResource)
server.start
