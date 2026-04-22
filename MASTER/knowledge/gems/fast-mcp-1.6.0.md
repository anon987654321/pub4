# frozen_string_literal: true
require 'fast_mcp'

# -------------------------------------------------
# Server configuration
# -------------------------------------------------
SERVER = FastMcp::Server.new(
  name:    'my-ai-server',
  version: '1.0.0'
)

# -------------------------------------------------
# Custom tool: Summarize text
# -------------------------------------------------
class SummarizeTool < FastMcp::Tool
  description 'Summarize text'

  DEFAULT_MAX_LENGTH = 100

  arguments do
    required(:text).filled(:string)
    optional(:max_length).filled(:integer)
  end

  # Returns the first three sentences, truncated to `max_length`
  # characters (default #{DEFAULT_MAX_LENGTH}). If fewer than three
  # sentences are present, all are used. Handles empty input safely.
  def call(text:, max_length: DEFAULT_MAX_LENGTH)
    return '' if text.to_s.strip.empty?

    sentences = text.split(/(?<=[.!?])\s+/)
    summary   = sentences.first(3).join(' ').strip
    summary   = summary[0, max_length] if summary.length > max_length
    summary + '...'
  end
end

SERVER.register_tool(SummarizeTool)

# -------------------------------------------------
# Static JSON resource: Stats
# -------------------------------------------------
class StatsResource < FastMcp::Resource
  uri          'data/stats'
  resource_name 'Stats'
  mime_type    'application/json'

  def content
    JSON.pretty_generate(
      users_online:       120,
      queries_per_minute: 250
    )
  end
end

SERVER.register_resource(StatsResource)

# -------------------------------------------------
# Boot the server
# -------------------------------------------------
SERVER.start
