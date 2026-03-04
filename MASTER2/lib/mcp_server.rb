# frozen_string_literal: true

require "json"

module MCP
  class Server
    ARGUMENTS_SCHEMA = {
      type: "object",
      properties: {},
      required: [],
      additionalProperties: true
    }.freeze

    Tool = Struct.new(:name, :description, :input_schema, :handler, keyword_init: true)

    def initialize
      @tools = {}
    end

    def tool(name, description:, input_schema: ARGUMENTS_SCHEMA, &handler)
      raise ArgumentError, "tool name must be a non-empty String" if name.to_s.strip.empty?
      raise ArgumentError, "handler block is required" unless handler

      @tools[name.to_s] = Tool.new(
        name: name.to_s,
        description: description.to_s,
        input_schema: input_schema || ARGUMENTS_SCHEMA,
        handler: handler
      )
    end

    def tools
      @tools.values
    end

    def call(json_request)
      request = parse_json(json_request)
      handle_request(request)
    rescue JSON::ParserError
      error("Invalid JSON")
    rescue StandardError => e
      error(e.message)
    end

    private

    def handle_request(request)
      method = request["method"].to_s
      params = request["params"].is_a?(Hash) ? request["params"] : {}

      case method
      when "tools/list"
        success("tools" => tools.map { |t| tool_payload(t) })
      when "tools/call"
        name = params["name"].to_s
        arguments = params["arguments"].is_a?(Hash) ? params["arguments"] : {}
        invoke_tool(name, arguments)
      else
        error("Unknown method: #{method}")
      end
    end

    def invoke_tool(name, arguments)
      tool = @tools[name]
      return error("Unknown tool: #{name}") unless tool

      result = tool.handler.call(arguments)
      success("result" => result)
    end

    def tool_payload(tool)
      {
        "name" => tool.name,
        "description" => tool.description,
        "inputSchema" => tool.input_schema
      }
    end

    def parse_json(json)
      JSON.parse(json.to_s)
    end

    def success(payload)
      { "ok" => true, "payload" => payload }
    end

    def error(message)
      { "ok" => false, "error" => { "message" => message.to_s } }
    end
  end
end