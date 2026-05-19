# frozen_string_literal: true

require "yaml"

module Master
  module Ground
    # YAML frontmatter parser for markdown files.
    # Returns {meta: Hash, body: String}; empty meta when no frontmatter or malformed.
    module Frontmatter
      MARKER = "---"
      RE     = /\A---\n(.*?)\n---\n?(.*)/m

      module_function

      def parse(raw)
        s = raw.to_s
        return { meta: {}, body: s.strip } unless s.start_with?(MARKER)
        m = s.match(RE)
        return { meta: {}, body: s.strip } unless m
        meta = begin; YAML.safe_load(m[1]) || {}; rescue Psych::Exception; {}; end
        { meta: meta, body: m[2].strip }
      end

      def parse_file(path)
        parse(File.read(path, encoding: "UTF-8"))
      end
    end
  end
end
