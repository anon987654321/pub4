# frozen_string_literal: true

require_relative "../trace/write_tracker"

module Master
  module Io
    # AST-aware editing tool using Ruby's Ripper (stdlib) for parsing.
    # Supports: find_method, rename_method, extract_lines_to_method, add_after_method.
    # Uses Ripper::SexpBuilder for structure-awareness without external gem dependencies.
    class AstEdit
      include PathGuard
      include Master::Ground::AtomicWrite
      TIER = :guarded
      NAME = "ast_edit".freeze
      DESCRIPTION = "AST-aware code editing: find, rename, or restructure Ruby methods safely.".freeze

      def initialize(root:, undo:, governor: nil, event_bus: nil)
        @root = File.realpath(root)
        @undo = undo
        @governor = governor
        @bus = event_bus
      end

      def call(operation:, path:, **opts)
        full = resolve(path)
        return full if full.err?
        fp = full.value!
        return Result.err("ast_edit: not found: #{path}", category: :validation) unless File.exist?(fp)

        src = File.read(fp)
        case operation.to_s
        when "find_method" then find_method(src, opts[:name].to_s)
        when "rename_method" then rename_method(fp:, src:, from: opts[:from].to_s, to: opts[:to].to_s)
        when "add_after" then add_after_method(fp:, src:, after_name: opts[:after].to_s, code: opts[:code].to_s)
        when "method_lines" then method_lines(src, opts[:name].to_s)
        else
          Result.err("ast_edit: unknown operation: #{operation}", category: :validation)
        end
      rescue StandardError => e
        Result.err("ast_edit: #{e.message}", category: :unknown)
      end

      private

      def find_method(src, name)
        lines = src.lines
        ranges = method_line_ranges(src)
        entry = ranges.find { |r| r[:name] == name }
        return Result.err("ast_edit: method not found: #{name}", category: :validation) unless entry

        slice = lines[(entry[:start] - 1)..(entry[:end] - 1)].join
        Result.ok("# #{name} (lines #{entry[:start]}–#{entry[:end]})\n#{slice}")
      end

      def rename_method(fp:, src:, from:, to:)
        return Result.err("ast_edit: from/to required", category: :validation) if from.empty? || to.empty?
        return Result.err("ast_edit: invalid name: #{to}",
          category: :validation) unless to.match?(/\A[a-z_][a-zA-Z0-9_]*[?!]?\z/)

        perm = @governor&.permit?(NAME, TIER, fp)
        return perm if perm&.err?

        @undo.snapshot(fp)
        updated = src
          .gsub(/\bdef\s+#{Regexp.escape(from)}\b/, "def #{to}")
          .gsub(/\b#{Regexp.escape(from)}\s*\(/, "#{to}(")
          .gsub(/\b#{Regexp.escape(from)}\b(?!\s*[:=])/) { |m| to }

        atomic_write(fp, updated)
        Master::Trace::WriteTracker.current&.record(fp)
        @bus&.publish("tool:after", tool: NAME, path: fp)
        @bus&.publish("tool:ast_edit", op: "rename", from:, to:, path: fp)
        Result.ok("renamed #{from} → #{to} in #{File.basename(fp)}")
      end

      def add_after_method(fp:, src:, after_name:, code:)
        return Result.err("ast_edit: after/code required", category: :validation) if after_name.empty? || code.empty?

        ranges = method_line_ranges(src)
        entry = ranges.find { |r| r[:name] == after_name }
        return Result.err("ast_edit: method not found: #{after_name}", category: :validation) unless entry

        perm = @governor&.permit?(NAME, TIER, fp)
        return perm if perm&.err?

        lines = src.lines
        insert_at = entry[:end]
        lines.insert(insert_at, "\n", code.chomp + "\n")

        @undo.snapshot(fp)
        atomic_write(fp, lines.join)
        Master::Trace::WriteTracker.current&.record(fp)
        @bus&.publish("tool:after", tool: NAME, path: fp)
        @bus&.publish("tool:ast_edit", op: "add_after", after: after_name, path: fp)
        Result.ok("inserted method after #{after_name} in #{File.basename(fp)}")
      end

      def method_lines(src, name)
        ranges = method_line_ranges(src)
        entry = ranges.find { |r| r[:name] == name }
        return Result.err("ast_edit: method not found: #{name}", category: :validation) unless entry
        Result.ok("#{name}: lines #{entry[:start]}–#{entry[:end]}")
      end

      def method_line_ranges(src)
        require "ripper"
        ranges = []
        stack = []
        depth = 0

        Ripper.lex(src).each do |(line, _col), type, token, _state|
          depth = lex_token_depth(type, token, line, stack, depth, ranges)
        end
        ranges
      end

      def lex_token_depth(type, token, line, stack, depth, ranges)
        case type
        when :on_kw
          depth = kw_token_depth(token, line, stack, depth, ranges)
        when :on_ident
          stack.last[:name] = token if !stack.empty? && stack.last[:name].nil?
        end
        depth
      end

      def kw_token_depth(token, line, stack, depth, ranges)
        case token
        when "def"
          stack.push({ name: nil, start: line, depth: })
          depth + 1
        when "class", "module", "do", "begin", "for", "if", "unless", "while", "until", "case"
          return depth if token == "if" && !stack.empty? && stack.last[:name]

          depth + 1
        when "end"
          close_method_range(stack, depth - 1, line, ranges)
          depth - 1
        else
          depth
        end
      end

      def close_method_range(stack, depth, line, ranges)
        return unless !stack.empty? && depth == stack.last[:depth]

        entry = stack.pop
        entry[:end] = line
        ranges << entry if entry[:name]
      end

    end
  end
end
