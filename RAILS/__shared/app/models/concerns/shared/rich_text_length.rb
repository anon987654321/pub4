# frozen_string_literal: true

module Shared
  # Length limits on a rich-text field measure what was written, not the markup
  # around it.
  #
  # A 500-character limit applied to Tiptap's output counts "<p>" and "</p>"
  # against the writer, so a bio at 493 characters becomes invalid the moment an
  # editor is mounted on the field it was already saved in. Worse, the failure is
  # silent in review: the validation still reads `maximum: 500` and the field
  # still holds a bio. This strips tags first, so the number in the model means
  # what a reader would say it means.
  #
  # Entities decode too — "&amp;" is one character to a reader, and five to
  # String#length.
  module RichTextLength
    extend ActiveSupport::Concern

    def self.plain(html)
      ActionView::Base.full_sanitizer.sanitize(html.to_s).to_s
    end

    class_methods do
      def validates_rich_text_length(attribute, maximum:)
        validate do
          value = Shared::RichTextLength.plain(public_send(attribute))
          next if value.length <= maximum

          errors.add(attribute, :too_long, count: maximum)
        end
      end
    end
  end
end
