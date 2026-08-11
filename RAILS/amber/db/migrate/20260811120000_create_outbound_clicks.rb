# frozen_string_literal: true

# Nothing in this fleet counted an outbound affiliate click, so every estimate of
# what partner marketing earns was arithmetic over an unmeasured number: in a
# network dashboard, "nobody clicks" and "attribution is broken" are the same zero.
#
# One migration per app, which is this repo's convention — the engine declares
# config.paths["db/migrate"] but the apps do not read it (db:migrate:status lists
# only their own), so a migration left in shared/db/migrate would never run.
#
# Deliberately narrow: a host, not a URL. Recording the full target would make this
# a log of what each visitor shops for, which is not needed to answer the question
# and would be a liability. Guarded, so re-running is free.
class CreateOutboundClicks < ActiveRecord::Migration[8.1]
  def change
    return if table_exists?(:outbound_clicks)

    create_table :outbound_clicks do |t|
      t.string :app, null: false
      t.string :surface
      t.string :merchant
      t.string :url_host, null: false
      t.string :subject_type
      t.bigint :subject_id
      t.string :epi
      t.bigint :user_id
      t.boolean :guest, null: false, default: false
      t.datetime :created_at, null: false
    end

    add_index :outbound_clicks, :created_at
    add_index :outbound_clicks, %i[merchant created_at]
    add_index :outbound_clicks, %i[subject_type subject_id]
  end
end
