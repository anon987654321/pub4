# frozen_string_literal: true

# What a link in a message is, without opening it. Cached per URL rather than
# per message: the same article gets pasted into twenty rooms, and fetching it
# twenty times makes this app a small amplifier pointed at whoever was linked.
class CreateLinkPreviews < ActiveRecord::Migration[8.1]
  def change
    create_table :link_previews do |t|
      t.string :url, null: false
      t.string :title
      t.string :site_name
      t.text :description
      # ok or failed. A failure is recorded rather than retried on every render,
      # or a dead link becomes a fetch on every page view of the thread.
      t.string :status, null: false, default: "pending"
      t.datetime :fetched_at
      t.timestamps
    end

    add_index :link_previews, :url, unique: true
    add_reference :messages, :link_preview, null: true, foreign_key: true
  end
end
