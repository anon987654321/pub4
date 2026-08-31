# frozen_string_literal: true

require "yaml"

module Master
  module Ground
    # The one reader of YAML front matter, in two shapes.
    #
    # Five copies of this existed. Two called `parse` here; three carried
    # /\A---\s*\n(.*?)\n---\s*\n?(.*)\z/m inline — lib/cli/skills.rb and both
    # antigravity readers — and each answered a malformed header differently: two
    # returned {} silently and the third let the exception out. One input, three
    # behaviours, decided by which reader reached the file first.
    #
    # `split` is for a caller that has to tell a file with no front matter from a
    # file with empty front matter; a skill with no header is not a skill, while a
    # rule with no header is still a rule. `parse` is for a caller that does not
    # care, and keeps the {meta:, body:} shape its two callers already read.
    module Frontmatter
      RE = /\A---\s*\n(.*?)\n---\s*\n?(.*)\z/m

      module_function

      # The header and the body, or nil where the file has no front matter.
      #
      # `context` is required rather than defaulted: a swallow with no
      # caller-supplied context is the undifferentiated stream Swallow's own
      # header warns about. A header that will not parse is load-bearing every
      # time — the caller reads a name out of it and drops the subject when it is
      # empty, so a typo silently unregisters the thing rather than reporting it
      # broken.
      def split(raw, context:, **meta)
        match = raw.to_s.match(RE) or return nil

        header = begin
          YAML.safe_load(match[1], permitted_classes: [Symbol, Time, Date], aliases: false) || {}
        rescue StandardError => error
          Swallow.log(error, context:, severity: :load_bearing, **meta)
          {}
        end
        [header, match[2].strip]
      end

      def parse(raw, context: "ground.frontmatter", **meta)
        header, body = split(raw, context:, **meta)
        return { meta: {}, body: raw.to_s.strip } if header.nil?

        { meta: header, body: }
      end

      def parse_file(path)
        parse(File.read(path, encoding: "UTF-8"), context: "ground.frontmatter.file", path:)
      end
    end
  end
end
