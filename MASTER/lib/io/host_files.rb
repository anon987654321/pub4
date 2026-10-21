# frozen_string_literal: true

require "time"

module Master
  module Io
    # Read-only host filesystem inspection. Relative paths start at HOME; absolute
    # paths are allowed and remain subject to the runtime's actual OS/sandbox access.
    # This tool never invokes doas/sudo or writes files.
    class HostFiles
      NAME = "host_files".freeze
      TIER = :guarded
      DESCRIPTION = "Read-only filesystem inspection for the current Unix host. Relative paths start at HOME; absolute paths can inspect system paths when permitted. List, read, search and inspect only. Never writes or escalates privileges.".freeze
      MAX_DEPTH = 5
      MAX_ENTRIES = 1_000
      MAX_RESULTS = 50
      MAX_LINE_CHARS = 240
      MAX_READ_BYTES = 2 * 1024 * 1024
      DEFAULT_LINES = 200
      MAX_LINES = 500
      ACTIONS = %w[list read search info].freeze
      SENSITIVE_PATHS = [
        %r{(?:\A|/)\.aws/credentials\z}i,
        %r{(?:\A|/)\.config/gh/hosts\.yml\z}i,
        %r{(?:\A|/)\.git-credentials\z}i,
        %r{(?:\A|/)\.netrc\z}i,
        %r{(?:\A|/)\.npmrc\z}i,
        %r{(?:\A|/)\.pypirc\z}i,
        %r{(?:\A|/)\.env(?:\.[^/]*)?\z}i,
        %r{(?:\A|/)(?:id_rsa|id_ed25519|id_ecdsa|identity)\z}i,
        %r{(?:\A|/)[^/]*(?:private[-_]?key|access[-_]?token|refresh[-_]?token|credential|secret)[^/]*\z}i,
        /\.(?:key|p12|pfx)\z/i,
      ].freeze

      def initialize(governor:, event_bus: nil, home: nil)
        value = home.to_s.strip
        value = ENV["HOME"].to_s.strip if value.empty?
        value = Dir.home if value.empty?
        @home = File.realpath(value)
        @governor = governor
        @bus = event_bus
      end

      def call(action:, path: ".", query: nil, depth: 1, offset: 0, limit: DEFAULT_LINES, full: false)
        action = action.to_s.downcase
        return Result.err("host_files: unknown action #{action.inspect}", category: :validation) unless ACTIONS.include?(action)
        return Result.err("host_files: search query is required", category: :validation) if action == "search" && query.to_s.strip.empty?

        resolved = resolve(path)
        return resolved if resolved.err?
        full_path = resolved.value!
        permission = @governor&.permit?(NAME, TIER, "#{action} #{full_path}")
        return permission if permission && permission.err?

        value = case action
        when "list" then list_directory(full_path, depth: depth.to_i.clamp(0, MAX_DEPTH))
        when "read" then read_file(full_path, offset: offset.to_i, limit: limit.to_i, full: full == true)
        when "search" then search_files(full_path, query: query.to_s, depth: depth.to_i.clamp(0, MAX_DEPTH), limit: limit.to_i)
        when "info" then file_info(full_path)
        end
        return value if value.is_a?(Master::Result::Err)
        value = value.value! if value.is_a?(Master::Result::Ok)

        @bus&.publish("tool:after", tool: NAME, action:, path: full_path, bytes: value.to_s.bytesize)
        Result.ok(value)
      rescue StandardError => e
        Result.err("host_files: #{e.class}: #{e.message}", category: :infrastructure)
      end

      private

      def resolve(path)
        requested = path.to_s.strip
        requested = "." if requested.empty?
        expanded = File.expand_path(requested, @home)
        return Result.err("host_files: path not found or inaccessible", category: :validation) unless File.exist?(expanded)

        canonical = File.realpath(expanded)
        return Result.err("host_files: credential or secret path refused", category: :policy) if sensitive_path?(canonical)

        Result.ok(canonical)
      rescue SystemCallError
        Result.err("host_files: path not found or inaccessible", category: :validation)
      end

      def sensitive_path?(path)
        normalized = path.to_s.tr("\\", "/")
        normalized.match?(%r{(?:\A|/)Library/Keychains(?:/|\z)}i) ||
          SENSITIVE_PATHS.any? { |pattern| normalized.match?(pattern) }
      end

      def list_directory(path, depth:)
        return Result.err("host_files: list requires a directory", category: :validation) unless File.directory?(path)

        rows = []
        state = { count: 0, truncated: false }
        walk(path, depth:, indent: 0, rows:, state:)
        rows << "(entry limit reached)" if state[:truncated]
        Result.ok(rows.empty? ? "(no visible entries)" : rows.join("\n"))
      end

      def walk(path, depth:, indent:, rows:, state:)
        return if depth < 0 || state[:count] >= MAX_ENTRIES

        Dir.children(path).sort_by do |entry|
          [File.directory?(File.join(path, entry)) ? 0 : 1, entry.downcase]
        end.each do |entry|
          if state[:count] >= MAX_ENTRIES
            state[:truncated] = true
            break
          end
          child = File.join(path, entry)
          next if File.symlink?(child) || sensitive_path?(child)

          state[:count] += 1
          prefix = "  " * indent
          if File.directory?(child)
            rows << "#{prefix}#{entry}/"
            walk(child, depth: depth - 1, indent: indent + 1, rows:, state:) if depth.positive?
          else
            rows << "#{prefix}#{entry} (#{File.size(child)} bytes)"
          end
        rescue Errno::EACCES, Errno::EPERM, Errno::ENOENT
          rows << "#{prefix}#{entry} (unavailable)"
        end
      rescue Errno::EACCES, Errno::EPERM, Errno::ENOENT
        rows << "#{("  " * indent)}#{File.basename(path)}/ (unavailable)"
      end

      def read_file(path, offset:, limit:, full:)
        return Result.err("host_files: read requires a regular file", category: :validation) unless File.file?(path)
        return Result.err("host_files: file exceeds #{MAX_READ_BYTES} bytes", category: :validation) if File.size(path) > MAX_READ_BYTES

        bytes = File.binread(path)
        return Result.err("host_files: binary file is not readable as text", category: :validation) if bytes.include?("\0")
        text = bytes.force_encoding(Encoding::UTF_8)
        return Result.err("host_files: invalid UTF-8; binary-safe inspection is unavailable", category: :validation) unless text.valid_encoding?

        lines = text.lines
        start = [offset, 0].max
        cap = full ? nil : limit.clamp(1, MAX_LINES)
        slice = cap ? (lines[start, cap] || []) : (lines[start..] || [])
        result = slice.each_with_index.map { |line, index| "#{start + index + 1}\t#{line.chomp}" }.join("\n")
        remaining = lines.length - start - slice.length
        result << "\nAdditional lines remain: read again with offset=#{start + slice.length}." if remaining.positive?
        result.empty? ? "(empty file)" : result
      end

      def search_files(path, query:, depth:, limit:)
        return Result.err("host_files: search requires a directory", category: :validation) unless File.directory?(path)

        term = query.to_s.downcase
        maximum = limit.clamp(1, MAX_RESULTS)
        hits = []
        seen = 0
        pending = [[path, 0]]
        until pending.empty? || hits.size >= maximum || seen >= MAX_ENTRIES
          directory, level = pending.shift
          next if level > depth

          Dir.children(directory).sort.each do |entry|
            child = File.join(directory, entry)
            next if File.symlink?(child) || sensitive_path?(child)
            if File.directory?(child)
              pending << [child, level + 1] if level < depth
              next
            end
            next unless File.file?(child) && File.size(child) <= 512 * 1024

            seen += 1
            body = File.binread(child)
            next if body.include?("\0")
            text = body.force_encoding(Encoding::UTF_8)
            next unless text.valid_encoding?

            text.each_line.with_index do |line, index|
              next unless line.downcase.include?(term)
              hits << "#{child}:#{index + 1}: #{line.strip[0, MAX_LINE_CHARS]}"
              break if hits.size >= maximum
            end
            break if hits.size >= maximum
          rescue Errno::EACCES, Errno::EPERM, Errno::ENOENT
            next
          end
        end
        Result.ok(hits.empty? ? "No matches found." : hits.join("\n"))
      rescue Errno::EACCES, Errno::EPERM, Errno::ENOENT
        Result.err("host_files: search path became inaccessible", category: :infrastructure)
      end

      def file_info(path)
        stat = File.stat(path)
        kind = stat.file? ? "file" : stat.directory? ? "directory" : "other"
        format("path: %<path>s\ntype: %<kind>s\nsize: %<size>d\nmode: %<mode>04o\nreadable: %<readable>s\nwritable: %<writable>s\nmodified: %<modified>s",
          path:, kind:, size: stat.size, mode: stat.mode & 0o7777,
          readable: File.readable?(path), writable: File.writable?(path), modified: stat.mtime.utc.iso8601)
      end
    end
  end
end
