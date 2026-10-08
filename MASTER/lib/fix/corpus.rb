# frozen_string_literal: true

require "digest"
require "fileutils"

module Master
  module Fix
    # The first thing a /fix does. It writes the files-and-folders tree, then
    # reads every file under that root in full. Dotfolders, and directories
    # named temp, tmp, vendor, or git, are not entered. The tree file itself
    # lives in .master so the walk that follows does not read it back.
    class Corpus
      SKIP_DIRECTORIES = %w[temp tmp vendor git].freeze
      TREE_NAME = File.join(".master", "fix_tree.txt")
      CHUNK = 1 << 20

      Result = Data.define(:ok, :files, :bytes, :tree_path, :failures, :digests) do
        def ok? = ok

        def summary
          state = ok ? "read" : "failed"
          "corpus: #{state}, #{files.size} files, #{bytes} bytes, tree #{tree_path}"
        end

        def digest(path)
          digests[path]
        end
      end

      def self.establish(root)
        new(root).establish
      end

      def initialize(root)
        @root = File.expand_path(root.to_s)
      end

      def establish
        tree, files = walk(@root)
        tree_path = write_tree(tree)
        bytes, failures, digests = read_files(files)
        Result.new(ok: failures.empty?, files:, bytes:, tree_path:, failures:, digests:)
      end

      private

      def walk(directory)
        dirs = []
        names = []
        files = []
        children(directory).each do |name, path|
          if File.directory?(path)
            child, nested = walk(path)
            dirs << [name, child]
            files.concat(nested)
          else
            names << name
            files << path
          end
        end
        [{ dirs:, files: names }, files]
      end

      def children(directory)
        Dir.children(directory).sort.filter_map do |name|
          next if name.start_with?(".")
          next if SKIP_DIRECTORIES.include?(name) && File.directory?(File.join(directory, name))

          path = File.join(directory, name)
          next if File.symlink?(path)
          next unless File.directory?(path) || File.file?(path)

          [name, path]
        end
      rescue SystemCallError
        []
      end

      def write_tree(tree)
        path = File.join(@root, TREE_NAME)
        FileUtils.mkdir_p(File.dirname(path))
        body = [
          "files and folders under #{@root}",
          "skipped directories: dotfolders, temp, tmp, vendor, git",
          "",
          *render_tree(tree),
          "",
        ].join("\n")
        File.write(path, body)
        path
      end

      def render_tree(node, depth = 0)
        indent = "  " * depth
        lines = []
        node[:dirs].each do |name, child|
          lines << "#{indent}#{name}/"
          lines.concat(render_tree(child, depth + 1))
        end
        node[:files].each { |name| lines << "#{indent}#{name}" }
        lines
      end

      def read_files(files)
        bytes = 0
        failures = []
        digests = {}
        files.each do |path|
          read_bytes, digest = read_fully(path)
          bytes += read_bytes
          digests[path] = digest
        rescue StandardError => e
          failures << "#{path.delete_prefix(@root + File::SEPARATOR)}: #{e.class}: #{e.message}"
        end
        [bytes, failures, digests]
      end

      # Every byte, in chunks, so a long media file is still read to the end
      # and is not held as one string.
      def read_fully(path)
        digest = Digest::SHA256.new
        bytes = 0
        File.open(path, "rb") do |file|
          while (chunk = file.read(CHUNK))
            digest.update(chunk)
            bytes += chunk.bytesize
          end
        end
        [bytes, digest.hexdigest]
      end
    end
  end
end
