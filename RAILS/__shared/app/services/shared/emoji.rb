# frozen_string_literal: true

require "yaml"

module Shared
  # Turns :shortcode: into the emoji it names, the way the first brgen did with
  # gemoji, but as Unicode text rather than images: a phone draws it in its own
  # emoji font, and copying the post copies the emoji.
  #
  # Only names in the table convert, so "kl. 10:30:00" and an unknown :word:
  # stay as written. In editor HTML only text between tags is touched: an
  # attribute such as href, and anything inside <code> or <pre>, keeps its
  # colons.
  module Emoji
    TABLE_PATH = File.expand_path("../../../config/emoji_shortcodes.yml", __dir__)
    SHORTCODE = /(?<![\w:]):([a-z0-9_+-]{1,40}):(?![\w:])/
    VERBATIM = %w[code pre].freeze
    TAG = /<[^>]*>/

    module_function

    def table
      @table ||= YAML.safe_load_file(TABLE_PATH).freeze
    end

    def lookup(name) = table[name.to_s]

    # Plain text or editor HTML in, the same with every known shortcode replaced.
    def emojify(text)
      return text if text.nil? || !text.include?(":")

      verbatim = 0
      pieces = text.split(/(#{TAG})/o).map do |piece|
        if piece.start_with?("<")
          verbatim += verbatim_step(piece)
          piece
        else
          verbatim.positive? ? piece : piece.gsub(SHORTCODE) { lookup(Regexp.last_match(1)) || Regexp.last_match(0) }
        end
      end
      pieces.join
    end

    # +1 entering <code>/<pre>, -1 leaving, 0 for any other tag.
    def verbatim_step(tag)
      name = tag[%r{\A</?\s*([a-zA-Z]+)}, 1].to_s.downcase
      return 0 unless VERBATIM.include?(name)

      tag.start_with?("</") ? -1 : 1
    end
  end
end
