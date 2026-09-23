# frozen_string_literal: true

require "fileutils"

module Master
  class Snapshot
    DEFAULT_TREES = %w[MASTER OPENBSD RAILS STUDIO].freeze
    DEFAULT_OUTPUT = File.join(REPO_ROOT, "snapshot_MASTER.md")
    SKIP = %w[.git .bundle node_modules vendor tmp log coverage storage cache dist build].freeze
    TEXT_EXTENSIONS = %w[.rb .rake .gemspec .ru .yml .yaml .json .js .mjs .ts .tsx .jsx .css .scss .html .erb .sh .zsh .md .txt].freeze
    NAMED_TEXT = %w[Gemfile Rakefile Guardfile Capfile Brewfile Vagrantfile config.ru].freeze

    def initialize(root: ROOT, output: DEFAULT_OUTPUT)
      @root = File.realpath(root)
      @output = File.expand_path(output, @root)
    end

    def write!
      paths = DEFAULT_TREES.map do |name|
        tree_root = File.join(@root, name)
        next unless File.directory?(tree_root)

        output = File.join(@root, "snapshot_#{name}.md")
        Snapshot.new(root: tree_root, output:).write_tree!
        output
      end.compact
      return paths.first if paths.one?

      paths
    end

    def write_tree!
      files = source_files
      body = ["# #{File.basename(@root)} snapshot", "", "Generated from #{@root}.", "", "## Tree", "", tree(files), "", "## Source", ""]
      files.each do |path|
        relative = path.delete_prefix(@root + File::SEPARATOR)
        language = Master.language_for(path) || "text"
        body << "### #{relative}"
        body << ""
        body << "`````#{language}"
        body << File.binread(path).force_encoding("UTF-8").scrub
        body << "`````"
        body << ""
      end
      File.write(@output, body.join("\n"), mode: "w", encoding: "UTF-8")
      @output
    end

    private

    def source_files
      Dir.glob(File.join(@root, "**", "*")).select do |path|
        File.file?(path) && path != @output && text_file?(path) && !skipped?(path)
      end.sort
    end

    def text_file?(path)
      ext = File.extname(path).downcase
      TEXT_EXTENSIONS.include?(ext) || NAMED_TEXT.include?(File.basename(path))
    end

    def skipped?(path)
      relative = path.delete_prefix(@root + File::SEPARATOR)
      SKIP.any? { |segment| relative.split(File::SEPARATOR).include?(segment) }
    end

    def tree(files)
      root = {}
      files.each do |path|
        node = root
        path.delete_prefix(@root + File::SEPARATOR).split(File::SEPARATOR).each do |part|
          node = (node[part] ||= {})
        end
      end
      lines = ["."]
      render_tree(root, lines, 0)
      lines.join("\n")
    end

    def render_tree(node, lines, depth)
      node.keys.sort.each do |name|
        lines << ("  " * depth) + name
        render_tree(node.fetch(name), lines, depth + 1) unless node.fetch(name).empty?
      end
    end
    end
  end
end
