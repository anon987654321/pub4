# frozen_string_literal: true

module Tv
  # For tv records that have no city of their own and inherit one from their
  # channel: Tv::Video and Tv::Broadcast.
  #
  # This is the fix for the tv.oshlo.no 500 of 2026-08-12. Tv::Channel includes
  # CityTenantable, so acts_as_tenant puts a default_scope on it. Tv::Video does
  # not, and tv_videos has no city_id — a video's city is whatever its channel's
  # is. On brgen.no the two agreed and nothing showed. On oshlo.no:
  #
  #   Tv::Video.trending.includes(:channel)
  #
  # returned Bergen's six videos, because nothing scoped the videos — and then
  # the preload of :channel ran through Channel's default_scope, matched no rows
  # for Oslo, and set every video's channel association to nil. The card partial
  # says tv_video.channel.name, so the page 500'd. belongs_to :channel is
  # required and the FK was set on every row; the nil came entirely from the
  # tenant scope, which is why it looked impossible.
  #
  # Guarding the view against a nil channel would have stopped the 500 and left
  # the real defect: one city's videos listed on another city's front page. The
  # scope is the fix; the crash was the symptom that made it visible.
  module ChannelTenanted
    extend ActiveSupport::Concern

    included do
      # nil city_id included deliberately. acts_as_tenant :city is declared
      # `optional: true` on Tv::Channel, so a channel with no city is legal and
      # reads as global rather than orphaned — it should appear in every city,
      # not in none. No such rows exist today (all three production channels are
      # Bergen's); this decides the case before it arrives rather than after.
      scope :in_current_city, lambda {
        tenant = ActsAsTenant.current_tenant
        next all unless tenant

        joins(:channel).where(tv_channels: { city_id: [tenant.id, nil] })
      }
    end
  end
end
