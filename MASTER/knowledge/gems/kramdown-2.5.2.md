require 'kramdown'

# frozen_string_literal: true

# Render a Markdown string to HTML using Kramdown.
#
# @param text [String] the Markdown source
# @param options [Hash] optional Kramdown options (e.g. :input, :auto_ids)
# @return [String] generated HTML
# @raise [ArgumentError] unless +text+ is a String
# @example Basic usage
#   html = render_markdown('# Hello World', auto_ids: false)
#   puts html
def render_markdown(text, **options)
  raise ArgumentError, 'text must be a String' unless text.is_a?(String)

  Kramdown::Document.new(text, **options).to_html
end

# Example usage (commented out to avoid NameError in library context):
# puts render_markdown('# Hello World', auto_ids: false)