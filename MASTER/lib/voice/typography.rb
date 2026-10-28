# frozen_string_literal: true

module Master
  module Voice
    # Terminal micro-typography after Bringhurst's Elements. Renderer#beautify
    # owns the prose marks — curly quotes, the apostrophe, the en dash, the
    # sentence space. This module owns the one mechanical courtesy those
    # cannot reach: the cut. A line the terminal cannot hold still ends like
    # a sentence ends, at a word's edge, on one true ellipsis — never three
    # ASCII dots, never a severed syllable, when a boundary can be had.
    module Typography
      ELLIPSIS = "…"
      BOUNDARY_SHARE = 0.7

      module_function

      # The text, cut to the limit at a word boundary with one ellipsis. A
      # single unbroken token — a path, an identifier — earns no boundary and
      # takes the hard cut instead; honesty about the limit outranks a fake
      # courtesy that would double the line.
      def ellipsis(text, limit)
        value = text.to_s
        limit = limit.to_i
        return value if limit <= 0 || value.length <= limit

        room = limit - ELLIPSIS.length
        cut = value[0, room].to_s
        if (boundary = cut.rindex(/\s/)) && boundary + 1 >= (room * BOUNDARY_SHARE).floor
          cut = cut[0, boundary]
        end
        "#{cut.rstrip}#{ELLIPSIS}"
      end
    end
  end
end
