# frozen_string_literal: true

module MASTER
  # Undo - Undo support for operations (NN/g: user control and freedom)
  module Undo
    extend self

    STACK_SIZE = 50

    @stack = []
    @redo_stack = []

    Operation = Struct.new(:type, :data, :timestamp) do
      def description
        case type
        when :file_edit
          "Edit #{data[:path]}"
        when :file_create
          "Create #{data[:path]}"
        when :file_delete
          "Delete #{data[:path]}"
        when :db_change
          "Database change"
        else
          type.to_s
        end
      end
    end

    class << self
      def push(type, data)
        op = Operation.new(type, data, Time.now)
        @stack.push(op)
        @stack.shift while @stack.size > STACK_SIZE
        @redo_stack.clear
        op
      end

      def undo
        return nil if @stack.empty?

        op = @stack.pop
        reverse(op)
        @redo_stack.push(op)
        op
      end

      def redo
        return nil if @redo_stack.empty?

        op = @redo_stack.pop
        apply(op)
        @stack.push(op)
        op
      end

      def can_undo?
        !@stack.empty?
      end

      def can_redo?
        !@redo_stack.empty?
      end

      def history
        @stack.map(&:description)
      end

      def clear
        @stack.clear
        @redo_stack.clear
      end

      # Track file edit
      def track_edit(path, original_content)
        push(:file_edit, { path: path, original: original_content })
      end

      # Track file creation
      def track_create(path)
        push(:file_create, { path: path })
      end

      # Track file deletion
      def track_delete(path, content)
        push(:file_delete, { path: path, content: content })
      end

      private

      def reverse(op)
        case op.type
        when :file_edit
          if op.data[:original]
            File.write(op.data[:path], op.data[:original])
            Result.ok(restored: op.data[:path])
          else
            Result.err("No original content to restore.")
          end
        when :file_create
          if File.exist?(op.data[:path])
            File.delete(op.data[:path])
            Result.ok(deleted: op.data[:path])
          else
            Result.ok(already_gone: op.data[:path])
          end
        when :file_delete
          File.write(op.data[:path], op.data[:content])
          Result.ok(restored: op.data[:path])
        else
          Result.err("Unknown operation type: #{op.type}")
        end
      end

      def apply(op)
        case op.type
        when :file_edit
          Result.err("Cannot redo file edit without new content.")
        when :file_create
          Result.err("Cannot redo file create without content.")
        when :file_delete
          if File.exist?(op.data[:path])
            File.delete(op.data[:path])
            Result.ok(deleted: op.data[:path])
          else
            Result.err("File not found: #{op.data[:path]}")
          end
        else
          Result.err("Unknown operation type: #{op.type}")
        end
      end
    end
  end
end
