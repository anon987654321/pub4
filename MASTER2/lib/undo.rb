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
          end
        when :file_create
          File.delete(op.data[:path]) if File.exist?(op.data[:path])
        when :file_delete
          File.write(op.data[:path], op.data[:content])
        end
      end

      def apply(op)
        case op.type
        when :file_edit
          # Can't redo edit without new content - this is a limitation
          puts "  Warning: Cannot redo file edit"
        when :file_create
          # File was deleted on undo, would need content to recreate
          puts "  Warning: Cannot redo file create"
        when :file_delete
          File.delete(op.data[:path]) if File.exist?(op.data[:path])
        end
      end
    end
  end
end
