# frozen_string_literal: true

# A reply to a story is a direct message that says what it is answering.
#
# Stories had no conversation hook at all: the viewer could look and leave. The
# reply lands in the DM thread the two already share, so it is readable after the
# story has expired — which is the point, since the story will not be there.
class AddStoryReplies < ActiveRecord::Migration[8.1]
  def change
    # nullify on the story's own sweep: the message is the pair's, and it
    # outlives the 24 hours the story had.
    add_reference :messages, :story, null: true, foreign_key: true
  end
end
