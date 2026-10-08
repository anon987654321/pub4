# frozen_string_literal: true

module Shared
  # Page views per host per day, as counters rather than rows.
  #
  # Shared::OutboundClick is the other half of this and was built first: it is
  # the denominator for affiliate revenue, clicks × conversion × basket ×
  # commission. But a click rate has no meaning without the visits it came from,
  # and nothing counted those. brgen serves seven live city domains — brgen.no,
  # oshlo.no, stvanger.no, trndheim.no, cardff.uk, edinbrgh.uk, frankfrt.de —
  # and there was no way to say which of them anyone reaches. Every decision
  # about where to spend effort was a guess between seven options.
  #
  # A counter, not a log. One row per (app, host, route, day) incremented in
  # place, so a day of traffic on one surface is one row however many visits it
  # holds. The alternative — a row per request, which is what an analytics
  # product would store — puts unbounded write volume on a SQLite database on a
  # 1 vCPU host, to answer a question that only ever needs the total.
  #
  # Deliberately not personal data. No IP, no user agent, no user id, no session,
  # no path parameters: `route` is controller#action, which is the shape of the
  # page and not the identity of the thing viewed. So this needs no consent
  # banner and cannot become a liability, which is the same reasoning
  # OutboundClick records a host instead of a URL.
  class VisitCount < ApplicationRecord
    self.table_name = "visit_counts"

    validates :app, :host, :route, :day, presence: true
    validates :host, :route, length: { maximum: 255 }

    scope :since, ->(date) { where(day: date..) }
    scope :for_host, ->(host) { where(host:) }

    # Obvious crawlers, so "which city has traffic" does not answer "the one the
    # crawlers like". Read from the request and never stored — matching on a
    # handful of substrings is imprecise on purpose, because the cost of missing
    # a bot is a slightly high number and the cost of storing a user agent to
    # classify it properly is a personal-data record we do not want.
    BOT_HINTS = %w[bot crawl spider slurp curl wget headless preview monitor probe].freeze

    def self.bot?(user_agent)
      ua = user_agent.to_s.downcase
      return true if ua.empty?

      BOT_HINTS.any? { |hint| ua.include?(hint) }
    end

    # One indexed upsert per view. Not buffered in memory: at the traffic these
    # domains actually have, a buffer would trade lost counts on restart and a
    # flush thread for a write that SQLite does in microseconds. Revisit if a
    # single host passes a few views per second — the shape here does not change,
    # only where the increment accumulates first.
    def self.record(app:, host:, route:, day: Date.current)
      return nil if app.blank? || host.blank? || route.blank?

      normalized = host.to_s.downcase.delete_prefix("www.")
      return nil if normalized.length > 255

      key = { app: app.to_s, host: normalized, route: route.to_s, day: }
      # UPDATE first, INSERT only when the day's row does not exist yet. Written
      # this way rather than as an ON CONFLICT upsert because the placeholder
      # syntax for that differs between SQLite and PostgreSQL, and apps.yml has
      # both apps moving to PostgreSQL later; this is the same two statements on
      # either. RecordNotUnique is the race between two first-of-the-day
      # requests, and the retry lands on the UPDATE.
      return true if where(key).update_all("count = count + 1, updated_at = CURRENT_TIMESTAMP").positive?

      begin
        create!(**key, count: 1)
      rescue ActiveRecord::RecordNotUnique
        where(key).update_all("count = count + 1, updated_at = CURRENT_TIMESTAMP")
      end
      true
    end

    # The report the whole table exists for: which domains anyone actually
    # reaches, busiest first.
    def self.by_host(since: 30.days.ago.to_date)
      since(since).group(:host).order(Arel.sql("SUM(count) DESC")).sum(:count)
    end

    def self.by_route(host: nil, since: 30.days.ago.to_date)
      scope = since(since)
      scope = scope.for_host(host) if host.present?
      scope.group(:route).order(Arel.sql("SUM(count) DESC")).sum(:count)
    end

    def self.total(since: 30.days.ago.to_date) = since(since).sum(:count)
  end
end
