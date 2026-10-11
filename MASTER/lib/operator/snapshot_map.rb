# frozen_string_literal: true

module Operator

  # The map half of a snapshot: one line a file, grouped by directory, naming the file, its
  # length, its one-line purpose and what it declares.
  module SnapshotMap
    MAP_NAMES = 6
    MAP_GROUPS = 3
    MAP_WIDTH = 150
    MAP_PURPOSE = 70

    RUBY_DECLARATIONS = [
      /\A\s*((?:class|module)\s+[\w:]+(?:\s*<\s*[\w:]+)?)/,
      %r{\A\s*(def\s+(?:self\.)?[\w?!=\[\]<>+*/-]+)},
      /\A\s*(test\s+["'][^"']+["'])/,
    ].freeze
    JS_DECLARATIONS = [
      /\A(?:export\s+)?(?:default\s+)?((?:async\s+)?function\*?\s+\w+|class\s+\w+)/,
      /\A(?:export\s+)?(const\s+\w+\s*=\s*(?:async\s*)?(?:\(|function))/,
    ].freeze
    DECLARATIONS = {
      ".rb" => RUBY_DECLARATIONS, ".rake" => RUBY_DECLARATIONS,
      ".yml" => [/\A([A-Za-z_][\w.-]*):/], ".yaml" => [/\A([A-Za-z_][\w.-]*):/],
      ".js" => JS_DECLARATIONS, ".mjs" => JS_DECLARATIONS, ".ts" => JS_DECLARATIONS,
      ".tsx" => JS_DECLARATIONS, ".jsx" => JS_DECLARATIONS,
    }.freeze

    module_function

    def declaration(path, raw)
      DECLARATIONS.fetch(File.extname(path).downcase, []).each do |pattern|
        found = raw[pattern, 1]

        return found if found
      end

      nil
    end

    # A tag (the part number in a multipart pack) follows the length.
    # One line a file: name, length, its one-line purpose and what it declares. The whole tree's
    # map is a fraction of its source, so every file is present in a context that the source
    # never fits; the reader picks files from it and asks for them with --only.
    def map_line(file, inlined: true, tag: nil)
      path = file.fetch(:path)
      mark = inlined ? "" : "~"
      count = file.fetch(:original).lines.size
      line = +"#{mark}#{File.basename(path)} [#{count}L]#{" #{tag.call(file)}" if tag}"
      return line if SnapshotPack.test_path?(path)

      purpose = file.fetch(:minified).lines.first.to_s[/\A#\s+(.+)/, 1]
      line << " — #{purpose[0, MAP_PURPOSE]}" if purpose
      shown = map_declarations(path, file.fetch(:original))
      line << " | #{shown}" unless shown.empty?

      line.length > MAP_WIDTH ? "#{line[0, MAP_WIDTH - 1]}…" : line
    end

    # "Owner: a b c | Other: d e": the first few classes and what each defines.
    def map_declarations(path, original)
      groups = []

      original.each_line do |raw|
        name = declaration(path, raw)
        next unless name

        if name.match?(/\A(class|module)\s/)
          groups << [name.sub(/\A(class|module)\s+/, "").split(/\s/).first, []]
        elsif name.start_with?("def ")
          groups << [nil, []] if groups.empty?
          groups.last.last << name.sub(/\Adef\s+(self\.)?/, '\1')
        elsif groups.empty? || groups.last.first != name
          groups << [name, []]
        end
      end

      shown = groups.first(MAP_GROUPS).map { |owner, defs| [owner, listed_names(defs)].compact.reject(&:empty?) }

      shown.map { |parts| parts.join(": ") }.join(" | ")
    end

    def listed_names(defs)
      listed = defs.first(MAP_NAMES).join(" ")
      defs.size > MAP_NAMES ? "#{listed} +#{defs.size - MAP_NAMES}" : listed
    end

    def map_text(files, chosen, tag: nil)
      by_dir = Hash.new { |hash, key| hash[key] = [] }
      files.each { |f| by_dir[File.dirname(f[:path])] << map_line(f, inlined: chosen.include?(f[:path]), tag:) }

      "#{by_dir.sort.map { |dir, list| "#{dir}/\n#{list.join("\n")}" }.join("\n\n")}\n"
    end
  end
end
