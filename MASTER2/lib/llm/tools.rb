# frozen_string_literal: true

module LLM
  module Tools
    PATH_PARAM_DESC = "Path to the file or directory."

    Tool = Struct.new(:name, :description, :params, :handler, keyword_init: true)

    @registry = {}

    class << self
      def register(name, description:, params: {}, &block)
        raise ArgumentError, "Block required" unless block

        @registry[name.to_s] = Tool.new(
          name: name.to_s,
          description: description,
          params: params,
          handler: block
        )
      end

      def tools
        @registry.values
      end

      def tool(name)
        @registry[name.to_s]
      end

      def execute(name, **kwargs)
        t = tool(name)
        raise ArgumentError, "Unknown tool: #{name}" unless t

        t.handler.call(**kwargs)
      end
    end

    register(
      :read_file,
      description: "Read a file from disk.",
      params: {
        path: { type: :string, desc: PATH_PARAM_DESC }
      }
    ) do |path:|
      File.read(path)
    end

    register(
      :write_file,
      description: "Write content to a file on disk.",
      params: {
        path: { type: :string, desc: PATH_PARAM_DESC },
        content: { type: :string, desc: "Content to write." }
      }
    ) do |path:, content:|
      File.write(path, content)
      "OK"
    end

    register(
      :list_dir,
      description: "List entries in a directory.",
      params: {
        path: { type: :string, desc: PATH_PARAM_DESC }
      }
    ) do |path:|
      Dir.children(path).sort
    end
  end
end