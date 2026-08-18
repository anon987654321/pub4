# frozen_string_literal: true

# A forward is a new message in the target thread, not a pointer rendered there:
# the copy has to outlive the original being unsent, it belongs to the person
# who forwarded it, and the people reading it usually cannot open the thread it
# came from. The column records where it came from so the copy can say so.
class AddForwardedFromToMessages < ActiveRecord::Migration[8.1]
  def change
    add_reference :messages, :forwarded_from, null: true, foreign_key: { to_table: :messages }
  end
end
