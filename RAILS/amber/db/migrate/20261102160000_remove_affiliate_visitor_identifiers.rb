# frozen_string_literal: true

require "json"

# The TradeDoubler visitor identifier is not used by the EPI attribution join.
# Remove it and scrub old copies from raw webhook payloads. City/surface
# attribution continues to work without visitor-level tracking.
class RemoveAffiliateVisitorIdentifiers < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:affiliate_conversions)

    scrub_raw_payloads
    remove_column :affiliate_conversions, :visitor_id, :string if column_exists?(:affiliate_conversions, :visitor_id)
  end

  def down
    # Historical identifiers were deliberately erased and cannot be restored.
    add_column :affiliate_conversions, :visitor_id, :string, limit: 128 unless column_exists?(:affiliate_conversions, :visitor_id)
  end

  private

  def scrub_raw_payloads
    connection.select_all(
      "SELECT id, raw_payload FROM affiliate_conversions WHERE raw_payload IS NOT NULL"
    ).each do |row|
      raw = row.fetch("raw_payload")
      payload = raw.is_a?(String) ? JSON.parse(raw) : raw
      next unless payload.is_a?(Hash)
      next unless payload.key?("visitorId") || payload.key?("visitor_id")

      payload.delete("visitorId")
      payload.delete("visitor_id")
      json = connection.quote(JSON.generate(payload))
      id = connection.quote(row.fetch("id"))
      connection.execute("UPDATE affiliate_conversions SET raw_payload = #{json} WHERE id = #{id}")
    end
  end
end
