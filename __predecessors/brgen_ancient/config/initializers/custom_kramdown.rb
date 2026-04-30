require 'kramdown/document'

module Kramdown
  module Parser
    class CustomKramdown < Kramdown::Parser::Kramdown

      # Comment Kramdown parsers we don't want

      # https://github.com/gettalong/kramdown/blob/master/lib/kramdown/parser/kramdown.rb#L75

      def initialize(source, options)
        super

        # Keep the original order

        [
          # :blank_line,
          # :codeblock,
          :codeblock_fenced,
          # :blockquote,
          # :atx_header,
          :horizontal_rule,
          # :list,
          # :definition_list,
          :block_html,
          :setext_header,
          :table,
          :footnote_definition,
          :link_definition,
          :abbrev_definition,
          :block_extensions,
          :block_math,
          :eob_marker,
          # :paragraph
        ].each do |parser|
          @block_parsers.delete(parser)
        end

        [
          # :emphasis,
          :codespan,
          :autolink,
          :span_html,
          :footnote_marker,
          # :link,
          :smart_quotes,
          :inline_math,
          # :span_extensions,
          :html_entity,
          :typographic_syms,
          # :line_break,
          :escaped_chars
        ].each do |parser|
          @span_parsers.delete(parser)
        end
      end
    end
  end
end

