# frozen_string_literal: true

# A phone that loses signal after the server has the message but before the
# answer arrives resends it, and without a name for the attempt the thread gets
# the line twice. The composer mints one token per attempt and keeps it across
# retries, so the server can recognise a repeat and answer with the original.
class AddClientTokenToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :client_token, :string

    # Scoped to the sender: a token is only a promise from one person's composer.
    # Rows without one (bots, the corner widget, imports) are not constrained —
    # NULLs do not collide in a unique index.
    add_index :messages, %i[sender_id client_token], unique: true
  end
end
