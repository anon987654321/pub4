# frozen_string_literal: true

module Master
  module Content
    # The content machine — a kanban whose cards are written, edited and judged
    # to a publishable standard before they leave the board. Grounded in the
    # runtime's own review machinery: the judge is a council, the writer and
    # editor are operators with briefs, and no card crosses a lane without the
    # verdict that admits it.
    VERSION = 1
  end
end

require_relative "content/card"
require_relative "content/board"
require_relative "content/judge"
require_relative "content/machine"
