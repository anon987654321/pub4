# frozen_string_literal: true

# Shared::OutboundClick counts the clicks that leave; nothing counted the visits
# they came from, so a click rate had no denominator. amber is one host rather
# than brgen's seven, which makes the host column look redundant here — it is
# not: the same table answers "how much of amber's traffic is the wardrobe and
# how much is the social feed" through `route`, and keeping the schema identical
# across both apps is what lets one Shared::VisitCount serve them.
#
# Counters, not rows. The unique index is what makes that work: one row per
# (app, host, route, day), incremented in place, so a day of traffic on one
# surface is one row however many visits it holds. A row per request is what an
# analytics product would store, and it would put unbounded write volume on
# SQLite on a 1 vCPU host to answer a question that only needs the total.
#
# No IP, no user agent, no user id, no session, no path parameters — `route` is
# controller#action, the shape of the page rather than the identity of the thing
# viewed. So this is not personal data and needs no consent banner, the same
# reasoning that made outbound_clicks store a host instead of a URL.
#
# One migration per app, which is this repo's convention — the engine declares
# config.paths["db/migrate"] but the apps do not read it. Guarded, so re-running
# is free.
class CreateVisitCounts < ActiveRecord::Migration[8.1]
  def change
    return if table_exists?(:visit_counts)

    create_table :visit_counts do |t|
      t.string :app, null: false
      t.string :host, null: false
      t.string :route, null: false
      t.date :day, null: false
      t.bigint :count, null: false, default: 0
      t.timestamps
    end

    # Unique, because it is the increment target: VisitCount.record updates this
    # row or creates it, and a duplicate would silently split a day's count in
    # two. Ordered host-first so "which domain gets traffic" reads the index.
    add_index :visit_counts, %i[app host route day], unique: true, name: "index_visit_counts_on_key"
    add_index :visit_counts, %i[day host]
  end
end
