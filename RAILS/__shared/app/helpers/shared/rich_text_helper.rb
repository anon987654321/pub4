# frozen_string_literal: true

module Shared
  # The one definition of what user rich text may contain.
  #
  # Tiptap submits HTML. Before this, brgen's posts/show carried the allow-list
  # inline and every other surface rendered the same kind of field with plain
  # escaping — correct while those fields were plain text, and a bug the moment
  # an editor was mounted on them, because the reader then sees a literal
  # "<p>Hello</p>" rather than a paragraph. Rendering rich text through one
  # helper is what keeps the allow-list from being restated per view and
  # drifting; the tag set is deliberately small and carries no attributes, so
  # there is no href, no style, no class and nothing to sanitise a URL scheme
  # out of.
  module RichTextHelper
    TAGS = %w[p br strong em b i ul ol li].freeze

    def rich_text(html)
      sanitize(emojify(html.to_s), tags: TAGS, attributes: [])
    end

    # :fire: as 🔥, the way the first brgen read shortcodes; see Shared::Emoji.
    def emojify(text) = Shared::Emoji.emojify(text)
  end
end
