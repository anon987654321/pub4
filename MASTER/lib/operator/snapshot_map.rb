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
    MAGIC_COMMENT = /\A(?:frozen_string_literal|encoding|coding|warn_indent|shareable_constant_value)\s*:/i
    SHELL_FUNCTION = /^\s*(?:function\s+([A-Za-z_][\w.-]*)\s*(?:\(\s*\))?|([A-Za-z_][\w.-]*)\s*\(\s*\))\s*\{/
    DECLARATIONS = {
      ".rb" => RUBY_DECLARATIONS, ".rake" => RUBY_DECLARATIONS,
      ".yml" => [/\A([A-Za-z_][\w.-]*):/], ".yaml" => [/\A([A-Za-z_][\w.-]*):/],
      ".js" => JS_DECLARATIONS, ".mjs" => JS_DECLARATIONS, ".ts" => JS_DECLARATIONS,
      ".tsx" => JS_DECLARATIONS, ".jsx" => JS_DECLARATIONS
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
      tag_value = tag&.call(file)
      line = +"#{mark}#{File.basename(path)} [#{count}L]#{" #{tag_value}" if tag_value && !tag_value.empty?}"
      return line if SnapshotPack.test_path?(path)

      purpose = purpose_line(path, file.fetch(:original))
      line << " — #{truncate_at_word(purpose, MAP_PURPOSE)}" if purpose
      shown = map_declarations(path, file.fetch(:original))
      line << " | #{shown}" unless shown.empty?

      truncate_at_word(line, MAP_WIDTH)
    end

    def purpose_line(path, original)
      if File.extname(path).downcase == ".md"
        headings = original.each_line.filter_map do |raw|
          raw[/\A\s{0,3}#+\s+(.+?)\s*#*\s*\z/, 1]&.strip
        end
        return headings.find { |heading| !self_referential_purpose?(path, heading) }
      end

      extension = File.extname(path).downcase
      original.each_line do |raw|
        line = raw.strip
        next if line.empty? || line.start_with?("#!")

        comment = if line.start_with?("#")
                    line.delete_prefix("#").strip
                  elsif line.start_with?("//")
                    line.delete_prefix("//").strip
                  elsif line.start_with?("/*")
                    line.delete_prefix("/*").sub(/\*\/\z/, "").strip
                  elsif line.start_with?("<!--")
                    line.delete_prefix("<!--").sub(/-->\z/, "").strip
                  elsif extension == ".sql" && line.start_with?("--")
                    line.delete_prefix("--").strip
                  else
                    break
                  end
        next if comment.empty? || MAGIC_COMMENT.match?(comment)
        next if self_referential_purpose?(path, comment)

        return comment
      end

      nil
    end

    def self_referential_purpose?(path, text)
      value = text.downcase.gsub(/[^a-z0-9.]+/, "")
      basename = File.basename(path).downcase
      stem = basename.sub(/\.[^.]+\z/, "")
      value == basename.gsub(/[^a-z0-9.]+/, "") || value == stem.gsub(/[^a-z0-9.]+/, "")
    end

    def truncate_at_word(text, width)
      return text if text.length <= width

      prefix = text[0, width - 1]
      boundary = prefix.rindex(/\s/)
      prefix = prefix[0...boundary] if boundary && boundary >= width / 2
      "#{prefix.rstrip}…"
    end

    # Language-specific summaries stay intentionally shallow: they orient the reader without
    # pretending a regex extractor is a full parser.
    def map_declarations(path, original)
      case File.extname(path).downcase
      when ".scss", ".css" then style_declarations(original)
      when ".erb" then erb_declarations(original)
      when ".sh", ".zsh", ".ksh" then shell_declarations(original)
      when ".js", ".mjs", ".ts", ".tsx", ".jsx"
        stimulus_declarations(original) || generic_map_declarations(path, original)
      else
        generic_map_declarations(path, original)
      end
    end

    def style_declarations(original)
      mixins = []
      placeholders = []
      selectors = []
      depth = 0

      original.each_line do |raw|
        visible = raw.sub(%r{/\*.*?\*/}, "").strip
        if depth.zero? && !visible.empty?
          mixin = visible.match(/\A@mixin\s+([\w-]+)/)
          mixins << mixin[1] if mixin
          placeholder = visible.match(/\A%([\w-]+)/)
          placeholders << "%#{placeholder[1]}" if placeholder
          if (match = visible.match(/\A([^@{};]+?)\s*\{\s*\z/))
            selector = match[1].strip.gsub(/\s+/, " ")
            selectors << selector unless selector.empty?
          end
        end

        structural = raw.gsub(/"(?:\\.|[^"])*"|'(?:\\.|[^'])*'/, "")
        structural = structural.gsub(%r{/\*.*?\*/}, "").sub(%r{/\*.*\z}, "")
        depth = [depth + structural.count("{") - structural.count("}"), 0].max
      end

      parts = []
      parts << "mixins: #{listed_names(mixins.uniq)}" unless mixins.empty?
      parts << "placeholders: #{listed_names(placeholders.uniq)}" unless placeholders.empty?
      parts << "selectors: #{listed_names(selectors.uniq)}" unless selectors.empty?
      parts.join(" | ")
    end

    def erb_declarations(original)
      renders = original.scan(/\brender\s+(?:partial:\s*)?["']([^"']+)["']/).flatten.uniq
      forms = original.scan(/\b(simple_form_for|form_with|form_for|form_tag)\b/).flatten.uniq
      frames = original.scan(/\bturbo_frame_tag\s+(?:["']([^"']+)["']|:(\w+))/)
                       .map { |quoted, symbol| quoted || symbol }.uniq

      parts = []
      parts << "renders: #{listed_names(renders)}" unless renders.empty?
      parts << "forms: #{listed_names(forms)}" unless forms.empty?
      parts << "frames: #{listed_names(frames)}" unless frames.empty?
      parts.join(" | ")
    end

    def shell_declarations(original)
      names = original.scan(SHELL_FUNCTION).map { |named, paren| named || paren }.uniq
      names.empty? ? "" : "functions: #{listed_names(names)}"
    end

    def stimulus_declarations(original)
      target_body = original[/^\s*static\s+targets\s*=\s*\[([^\]]*)\]/, 1]
      values_declared = original.match?(/^\s*static\s+values\s*=/)
      targets = target_body ? target_body.scan(/["']([\w-]+)["']/).flatten.uniq : []
      value_body = original[/static\s+values\s*=\s*\{(.*?)\}/m, 1] if values_declared
      values = value_body ? value_body.scan(/(?:\A|[,\n])\s*([a-z][\w-]*)\s*:\s*(?:String|Number|Boolean|Array|Object)\b/).flatten.uniq : []
      methods = original.scan(/^\s{2,}(?:async\s+)?([A-Za-z_$][\w$]*)\s*\([^\n;]*?\)\s*\{/)
                       .flatten.uniq - %w[if for while switch catch function constructor]

      return if targets.empty? && values.empty?

      parts = []
      parts << "targets: #{listed_names(targets)}" unless targets.empty?
      parts << "values: #{listed_names(values)}" unless values.empty?
      parts << "methods: #{listed_names(methods)}" unless methods.empty?
      parts.join(" | ")
    end

    # "Owner: a b c | Other: d e": the first few classes and what each defines.
    def generic_map_declarations(path, original)
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
