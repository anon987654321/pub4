# frozen_string_literal: true

require "json"
require "ruby_llm"
require_relative "../result"

module Master
  module Io
    # LLM-callable wrappers around the existing Master tool instances.
    # Each class holds a reference to the underlying tool via initialize,
    # so governor, undo, and event_bus plumbing stay intact.
    module LLM
      # The sixteen tools below differ only in the params they declare, the
      # coercion each applies, and how a success renders. The call itself and
      # the error line are the same everywhere, so they live here: `execute`
      # coerces its declared params and hands them to #forward.
      module ToolForwarding
        def initialize(tool) = @tool = tool

        private

        # Yields the value when the caller wants a shaped success; without a
        # block the value is the reply.
        def forward(**args)
          result = @tool.call(**args)
          return "Error: #{result.message}" unless result.ok?

          block_given? ? yield(result.value!) : result.value!
        end
      end

      class ReadFile < RubyLLM::Tool
        include ToolForwarding
        DEFAULT_LIMIT = 2000

        description "Read a file with line numbers. Path is relative to project root."
        param :path, desc: "File path relative to project root", required: true
        param :offset, desc: "First line to read (0-indexed)", type: "integer", required: false
        param :limit, desc: "Maximum number of lines to return", type: "integer", required: false

        def execute(path:, offset: 0, limit: DEFAULT_LIMIT)
          forward(path: path.to_s, offset: offset.to_i, limit: limit.to_i)
        end
      end

      class WriteFile < RubyLLM::Tool
        include ToolForwarding
        description "Write content to a file, creating it if needed. Snapshots for undo."
        param :path, desc: "File path relative to project root", required: true
        param :content, desc: "Full content to write", required: true

        def execute(path:, content:)
          forward(path: path.to_s, content: content.to_s) { |value| "Written: #{value}" }
        end
      end

      class StrReplace < RubyLLM::Tool
        include ToolForwarding
        description "Replace an exact unique string in a file with new content."
        param :path, desc: "File path relative to project root", required: true
        param :old_string, desc: "Exact string to find (must be unique in file)", required: true
        param :new_string, desc: "Replacement string", required: true

        def execute(path:, old_string:, new_string:)
          forward(path: path.to_s, old_string: old_string.to_s, new_string: new_string.to_s) do |value|
            "Replaced in: #{value}"
          end
        end
      end

      class ListDir < RubyLLM::Tool
        include ToolForwarding
        description "List directory contents as a tree. Path is relative to project root."
        param :path, desc: "Directory path (default: project root)", required: false
        param :depth, desc: "Tree depth (1-5)", type: "integer", required: false

        def execute(path: ".", depth: 3)
          forward(path: path.to_s, depth: depth.to_i)
        end
      end

      class SearchFiles < RubyLLM::Tool
        include ToolForwarding
        description "Search files in the project for a regex pattern. Returns matching lines with context."
        param :pattern, desc: "Ruby regex pattern to search for", required: true
        param :path, desc: "Directory to search in (default: project root)", required: false
        param :context, desc: "Lines of context to show around each match", type: "integer", required: false

        def execute(pattern:, path: ".", context: 2)
          forward(pattern: pattern.to_s, glob: path.to_s, context_lines: context.to_i)
        end
      end

      class Shell < RubyLLM::Tool
        include ToolForwarding
        description "Run a shell command in the project root. MASTER enforces blocked patterns."
        param :command, desc: "Shell command to execute", required: true

        def execute(command:) = forward(command: command.to_s)
      end

      class WebSearch < RubyLLM::Tool
        include ToolForwarding
        MAX_QUERY_LENGTH = 300

        description "Search the web using DuckDuckGo. Returns titles and snippets."
        param :query, desc: "Search query (max #{MAX_QUERY_LENGTH} chars)", required: true

        def execute(query:) = forward(query: query.to_s)
      end

      class WebFetch < RubyLLM::Tool
        include ToolForwarding
        description "Fetch a URL as plain text. Rewrites github/gist/arxiv/codepen URLs."
        param :url, desc: "http(s) URL to fetch", required: true

        def execute(url:) = forward(url: url.to_s)
      end

      class AskLlm < RubyLLM::Tool
        include ToolForwarding
        description "Ask a sub-question to a fresh LLM context. Useful for isolated reasoning."
        param :prompt, desc: "The question or prompt to ask", required: true
        param :context, desc: "Optional background context", required: false

        def execute(prompt:, context: nil)
          forward(prompt: prompt.to_s, context: context&.to_s)
        end
      end

      class GitContext < RubyLLM::Tool
        include ToolForwarding
        description "Query git log, blame, diff, status, or show for the project."
        param :operation, desc: "One of: log, blame, diff, status, show", required: true
        param :path, desc: "File path (required for blame; optional for log/diff/show)", required: false
        param :limit, desc: "Max commits for log", type: "integer", required: false

        def execute(operation:, path: nil, limit: 20)
          forward(operation: operation.to_s, path: path&.to_s, limit: limit.to_i)
        end
      end

      class AstEdit < RubyLLM::Tool
        include ToolForwarding
        description "AST-aware Ruby code editing: find, rename, or insert methods safely."
        param :operation, desc: "One of: find_method, rename_method, add_after, method_lines", required: true
        param :path, desc: "File path relative to project root", required: true
        param :name, desc: "Method name (for find_method, method_lines)", required: false
        param :from, desc: "Original method name (for rename_method)", required: false
        param :to, desc: "New method name (for rename_method)", required: false
        param :after, desc: "Insert after this method name (for add_after)", required: false
        param :code, desc: "Ruby code to insert (for add_after)", required: false

        def execute(operation:, path:, name: nil, from: nil, to: nil, after: nil, code: nil)
          forward(operation: operation.to_s, path: path.to_s,
                  name: name&.to_s, from: from&.to_s, to: to&.to_s,
                  after: after&.to_s, code: code&.to_s)
        end
      end

      class SearchKnowledge < RubyLLM::Tool
        include ToolForwarding
        description "Search the local knowledge base: ruby_llm docs, OpenBSD man pages, " \
          "system prompts, gem docs. Topics: ruby_llm, openbsd, system_prompts, gems, awesome."
        param :query, desc: "Search pattern (regex-capable)", required: true
        param :topic, desc: "Limit to topic folder: ruby_llm, openbsd, system_prompts, gems, awesome", required: false

        def execute(query:, topic: nil)
          forward(query: query.to_s, topic: topic&.to_s)
        end
      end

      class FeedbackRecord < RubyLLM::Tool
        include ToolForwarding
        description "Record RSI feedback: tool_success, tool_failure, user_correction, provider_error, user_feedback."
        param :event_type, desc: "One of: tool_success tool_failure user_correction provider_error user_feedback", required: true
        param :dimension, desc: "Tool name, provider name, or pattern label", required: true
        param :value, desc: "Numeric value (1.0=success 0.0=failure or duration)", type: "number", required: false
        param :metadata, desc: "Additional context string", required: false

        def execute(event_type:, dimension:, value: nil, metadata: nil)
          forward(event_type: event_type.to_s, dimension: dimension.to_s, value:, metadata:)
        end
      end

      class MemoryRecord < RubyLLM::Tool
        include ToolForwarding
        description "Write a durable markdown memory record (user facts, feedback, project context, or external references)."
        param :key, desc: "Snake-case identifier, e.g. user_role or feedback_no_python", required: true
        param :description, desc: "One-line hook surfaced in the memory index", required: true
        param :body, desc: "Full memory body (markdown)", required: true
        param :type, desc: "One of: user, feedback, project, reference, general", required: false

        def execute(key:, description:, body:, type: "general")
          forward(key: key.to_s, description: description.to_s, body: body.to_s, type: type.to_s)
        end
      end

      class SubdomainOrchestrator < RubyLLM::Tool
        include ToolForwarding
        description "Inspect or synchronize a pub4 subdomain cluster. Domains: marketplace, playlist, takeaway, tv, messages, maps, amber, bsdports, brgen, ai."
        param :domain, desc: "Subdomain cluster key (e.g. marketplace, maps, amber, bsdports)", required: true
        param :context, desc: "Optional operator context or directive", required: false

        def execute(domain:, context: nil)
          forward(domain: domain.to_s, context:) { |value| JSON.pretty_generate(value) }
        end
      end

      class DynamicHttp < RubyLLM::Tool
        include ToolForwarding
        description "Call a configured HTTP tool from data/tools.dynamic.yml."
        param :name, desc: "Tool name from tools.dynamic.yml", required: true
        param :params, desc: "JSON object of query/body parameters", required: false

        def execute(name:, params: "{}")
          payload = params.is_a?(Hash) ? params : JSON.parse(params.to_s)
          forward(name: name.to_s, params: payload, &:to_s)
        rescue JSON::ParserError => e
          "Error: invalid params JSON — #{e.message}"
        end
      end
    end
  end
end
