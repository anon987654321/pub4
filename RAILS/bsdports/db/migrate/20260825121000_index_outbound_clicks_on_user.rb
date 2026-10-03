# frozen_string_literal: true

# outbound_clicks carried indexes on created_at, [merchant, created_at] and
# [subject_type, subject_id] and none on user_id -- the column every
# per-user attribution, per-user abuse check and GDPR erasure query uses.
# Identical in all three apps, because all three carry the same
# create_outbound_clicks migration.
class IndexOutboundClicksOnUser < ActiveRecord::Migration[8.1]
  def change
    add_index :outbound_clicks, %i[user_id created_at],
              name: "index_outbound_clicks_on_user_id_and_created_at"
  end
end
