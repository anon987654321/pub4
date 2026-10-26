# frozen_string_literal: true

# Pending carts expire on a clock; this is the clock.
#
# `unexpired` already keeps a lapsed cart off the reader's order list the
# moment its deadline passes, so — like the stories sweep — this job is about
# the truth of the status column rather than visibility: until it runs, a
# stale cart still reads as "pending" to the kitchen's order list and to any
# count that trusts the column. cancel! (not update_column) so the kitchen
# and the reader are told through the same notification path a manual cancel
# uses.
class TakeawayCartExpirySweepJob < ApplicationJob
  queue_as :bulk
  limits_concurrency to: 1, key: "takeaway-cart-expiry-sweep", duration: 15.minutes, on_conflict: :discard

  def perform
    Takeaway::Order.expire_stale_pending!
  end
end
