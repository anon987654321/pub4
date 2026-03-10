# frozen_string_literal: true

module Master3
  class Undo
    def initialize(session:, event_bus: nil)
      @session = session
      @bus     = event_bus
      @stack   = []
    end

    def snapshot(path)
      content = File.exist?(path) ? File.read(path) : nil
      @session.snapshot(path, content)
      @stack << { path:, content: }
    end

    def undo!
      entry = @stack.pop
      return Result.err("nothing to undo", category: :validation) unless entry

      path    = entry[:path]
      content = entry[:content]

      if content.nil?
        File.delete(path) if File.exist?(path)
      else
        File.write(path, content)
      end

      @bus&.publish("undo:applied", path:)
      Result.ok(path)
    end

    def depth = @stack.size
  end
end
