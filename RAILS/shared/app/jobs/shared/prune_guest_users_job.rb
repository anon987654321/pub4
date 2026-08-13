# frozen_string_literal: true

module Shared
  # Delete guest rows nobody is behind any more.
  #
  # Two things were wrong with the one-liner this replaces, and both were silent.
  #
  # `in_batches(of: 500, &:destroy_all)` batches by primary key, and the relation
  # carries a LEFT OUTER JOIN from `where.missing(:sessions)`. Run against
  # production on 2026-08-13 it removed 3,832 of 143,339 eligible rows and
  # returned success: batching by id over a joined relation while deleting from
  # that same relation does not survive the deletion. Plucking ids and deleting
  # by id does, and re-querying each pass means the scope is always current.
  #
  # And every destroy raised FOREIGN KEY constraint failed, from SQLite rather
  # than from Rails, because `User` declared no association for message_receipts
  # or typing_indicators — both of which carry an FK to users. Guests owned
  # 194,295 receipts. That is fixed in User::CoreAssociations; it is named here
  # because this job is where it surfaced, and the same gap made account deletion
  # impossible for any real user with chat history.
  #
  # The pacing is not tidiness either. vm23 is one vCPU, a guest destroy cascades
  # into message_receipts, and resource_guard sheds amber and bsdports under load.
  # Running this unpaced against production took relayd down with it — the whole
  # site, not one app. So it yields between batches and stops entirely when the
  # box is already busy, on the assumption that a hygiene job is never worth an
  # outage and can always finish tomorrow night.
  class PruneGuestUsersJob < ApplicationJob
    queue_as :default

    BATCH = 100
    RETENTION = 7.days
    # Enough for a night's arrivals with headroom; the rest waits for tomorrow.
    MAX_PER_RUN = Integer(ENV.fetch("PRUNE_GUESTS_MAX", "20000"))
    # One vCPU, so a run-queue over this means something else needs the box.
    LOAD_CEILING = Float(ENV.fetch("PRUNE_GUESTS_LOAD_CEILING", "3.0"))

    def perform
      removed = 0

      while removed < MAX_PER_RUN
        break if busy?

        ids = stale_guest_ids
        break if ids.empty?

        ::User.where(id: ids).destroy_all
        removed += ids.size
        sleep(pause) unless Rails.env.test?
      end

      Rails.logger.info("PruneGuestUsersJob: removed #{removed} guest(s), #{remaining} still eligible")
      removed
    end

    private

    def stale_guest_ids
      ::User.where(guest: true)
            .where(created_at: ..RETENTION.ago)
            .where.missing(:sessions)
            .limit(BATCH)
            .pluck(:id)
    end

    def remaining
      ::User.where(guest: true).where(created_at: ..RETENTION.ago).where.missing(:sessions).count
    end

    def pause = Float(ENV.fetch("PRUNE_GUESTS_PAUSE", "0.5"))

    # Skipped rather than slowed when the box is loaded: a queue worker competing
    # with a deploy or a CI run is how the shed starts.
    def busy?
      return false if Rails.env.test?

      load1 = File.read("/proc/loadavg").split.first.to_f
      return false if load1.zero?

      if load1 > LOAD_CEILING
        Rails.logger.info("PruneGuestUsersJob: load #{load1} over #{LOAD_CEILING}, leaving the rest for the next run")
        true
      else
        false
      end
    rescue StandardError
      false
    end
  end
end
