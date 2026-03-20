# frozen_string_literal: true

module Master
  # Single-file undo: snapshots file content before a write, restores on demand.
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
      Result.ok(path)
    rescue => e
      Result.err("undo snapshot: #{e.message}", category: :unknown)
    end

    def undo!
      entry = @stack.pop
      return Result.err('nothing to undo', category: :validation) unless entry

      restore(entry[:path], entry[:content])
      @bus&.publish('undo:applied', path: entry[:path])
      Result.ok(entry[:path])
    end

    def depth = @stack.size

    private

    def restore(path, content)
      if content.nil?
        File.delete(path) if File.exist?(path)
      else
        File.write(path, content)
      end
    end
  end
end
