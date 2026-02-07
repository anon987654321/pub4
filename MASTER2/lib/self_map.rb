# frozen_string_literal: true

module MASTER
  # SelfMap - File tree mapping for self-awareness
  class SelfMap
    IGNORED = %w[.git node_modules vendor tmp log .bundle].freeze

    def initialize(root = MASTER.root)
      @root = root
    end

    def tree
      scan_dir(@root)
    end

    def files
      @files ||= collect_files(@root)
    end

    def ruby_files
      files.select { |f| f.end_with?('.rb') }
    end

    def lib_files
      ruby_files.select { |f| f.include?('/lib/') }
    end

    def test_files
      ruby_files.select { |f| f.include?('/test/') || f.include?('_test.rb') || f.include?('test_') }
    end

    def to_prompt
      <<~PROMPT
        MASTER Project Structure:
        #{tree_string}

        Files: #{files.count}
        Ruby files: #{ruby_files.count}
        Library: #{lib_files.count}
        Tests: #{test_files.count}
      PROMPT
    end

    def tree_string(dir = @root, prefix = '')
      result = []
      entries = Dir.entries(dir).sort.reject { |e| e.start_with?('.') || IGNORED.include?(e) }

      entries.each_with_index do |entry, idx|
        path = File.join(dir, entry)
        is_last = idx == entries.size - 1
        connector = is_last ? '└── ' : '├── '
        extension = is_last ? '    ' : '│   '

        result << "#{prefix}#{connector}#{entry}"

        if File.directory?(path)
          result << tree_string(path, "#{prefix}#{extension}")
        end
      end

      result.join("\n")
    end

    private

    def scan_dir(dir)
      result = { name: File.basename(dir), type: :dir, children: [] }

      Dir.entries(dir).sort.each do |entry|
        next if entry.start_with?('.') || IGNORED.include?(entry)

        path = File.join(dir, entry)
        if File.directory?(path)
          result[:children] << scan_dir(path)
        else
          result[:children] << { name: entry, type: :file, size: File.size(path) }
        end
      end

      result
    end

    def collect_files(dir)
      result = []

      Dir.entries(dir).each do |entry|
        next if entry.start_with?('.') || IGNORED.include?(entry)

        path = File.join(dir, entry)
        if File.directory?(path)
          result.concat(collect_files(path))
        else
          result << path.sub("#{@root}/", '')
        end
      end

      result
    end
  end
end
