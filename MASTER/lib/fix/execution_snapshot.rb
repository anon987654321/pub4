# frozen_string_literal: true

require "digest"

module Master
  module Fix
    # Captures an immutable description of each observed path before preflight
    # validation. File contents are fingerprinted by digest; symlinks are
    # fingerprinted as links so their targets are never compiled implicitly.
    module ExecutionSnapshot
      private

      def reread(paths, failures)
        bytes = 0
        Array(paths).each do |path|
          full = resolve_inside_root(path)
          state = fingerprint(full)
          @fingerprints[full] = state
          bytes += state.fetch(:bytes, 0)
        rescue StandardError => error
          failures << "#{relative(path)}: reread failed: #{error.class}: #{error.message}"
        end
        bytes
      end

      def verify_snapshot(paths, failures)
        Array(paths).each do |path|
          full = File.expand_path(path, @root)
          expected = @fingerprints[full]
          next unless expected

          actual = fingerprint(full)
          next if expected == actual

          failures << "#{relative(full)}: changed during preflight"
        rescue StandardError => error
          failures << "#{relative(full)}: snapshot verification failed: #{error.class}: #{error.message}"
        end
      end

      # Resolving paths is a precondition to reading or hashing them. Lexical
      # containment alone is insufficient because a symlink can escape root.
      def resolve_inside_root(path)
        full = File.expand_path(path.to_s, @root)
        root = File.realpath(@root)
        unless full == @root || full.start_with?("#{@root}#{File::SEPARATOR}")
          raise ArgumentError, "path resolves outside repository: #{path}"
        end

        if File.exist?(full) || File.symlink?(full)
          real = File.realpath(full)
          unless real == root || real.start_with?("#{root}#{File::SEPARATOR}")
            raise ArgumentError, "path resolves outside repository: #{path}"
          end
        end

        full
      rescue Errno::ENOENT
        # Missing tracked paths remain visible to reread as an explicit failure.
        raise if File.symlink?(File.expand_path(path.to_s, @root))

        full || File.expand_path(path.to_s, @root)
      end

      def fingerprint(path)
        full = resolve_inside_root(path)
        if File.symlink?(full)
          target = File.readlink(full).freeze
          return { kind: :symlink, target:, bytes: target.bytesize }.freeze
        end

        stat = File.stat(full)
        raise ArgumentError, "not a regular file: #{path}" unless stat.file?

        digest = @digestor.call(full)
        value = digest.respond_to?(:hexdigest) ? digest.hexdigest : digest.to_s
        {
          kind: :file,
          digest: value.dup.freeze,
          bytes: stat.size,
        }.freeze
      end

      # Compare exactly the captured UTF-8 source against the initial digest.
      # This prevents validation from approving bytes that changed after the
      # preflight read but before syntax or YAML parsing.
      def content_matches_snapshot?(path, content, failures, phase:)
        full = File.expand_path(path, @root)
        expected = @fingerprints[full]
        unless expected
          failures << "#{relative(full)}: no fingerprint available during #{phase}"
          return false
        end

        actual = Digest::SHA256.hexdigest(content.to_s.b)
        return true if expected[:kind] == :file && expected[:digest] == actual

        failures << "#{relative(full)}: content differs during #{phase}"
        false
      rescue StandardError => error
        failures << "#{relative(path)}: snapshot comparison failed during #{phase}: #{error.class}: #{error.message}"
        false
      end
    end
  end
end
