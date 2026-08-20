# frozen_string_literal: true

# The half of federation brgen could not do: follow somebody, tell the fediverse
# an edit happened, and refuse an instance.
class AddOutboundFederation < ActiveRecord::Migration[8.1]
  def change
    # One table, two directions, rather than a second table of the same shape.
    # Everything that predates this is a remote actor following a local user.
    add_column :fedi_follows, :direction, :string, null: false, default: "inbound"
    remove_index :fedi_follows, column: %i[fedi_actor_id user_id] if index_exists?(:fedi_follows, %i[fedi_actor_id user_id])
    add_index :fedi_follows, %i[fedi_actor_id user_id direction], unique: true

    # A whole instance, refused. Domain rather than actor: the reason to block
    # one is usually that moderating it actor by actor is the problem.
    create_table :fedi_blocks do |t|
      t.string :domain, null: false
      t.text :reason
      t.references :created_by, null: true, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :fedi_blocks, :domain, unique: true
  end
end
