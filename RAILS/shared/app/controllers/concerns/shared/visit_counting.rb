# frozen_string_literal: true

module Shared
  # Counts a page view per host per day. See Shared::VisitCount for why it is a
  # counter rather than a log, and why it holds no personal data.
  #
  # after_action, so a request that raised or redirected is not counted as a page
  # someone saw. Only GETs that returned HTML: a Turbo Stream, a JSON endpoint
  # and a redirect are all traffic, but none of them is a visit to a page, and
  # counting them would make the busiest "page" whichever one polls.
  #
  # `route` is controller#action rather than request.path. That is what bounds
  # the table: a path carries listing ids, city slugs and query strings, so one
  # row per distinct path is one row per listing per day — unbounded, and it
  # would also record which item each visitor looked at, which is exactly the
  # personal record this avoids being.
  module VisitCounting
    extend ActiveSupport::Concern

    included do
      after_action :count_visit
    end

    private

    def count_visit
      return unless request.get?
      return if request.xhr?
      return unless response.media_type == "text/html"
      return unless response.successful?
      return if Shared::VisitCount.bot?(request.user_agent)

      Shared::VisitCount.record(app: visit_counting_app, host: request.host, route: "#{controller_path}##{action_name}")
    rescue StandardError => e
      # Never fail a page over a counter. Reported rather than swallowed, so a
      # table that stops recording does not look like a site nobody visits —
      # which is the one conclusion this table exists to prevent.
      Rails.logger.warn("[visit_count] #{e.class}: #{e.message}")
      nil
    end

    # The fleet's idiom, used the same way by Shared::OutboundClicksController,
    # DomainEvent and LiveSearchable. Worth knowing what it actually returns:
    # brgen and amber are both `module App`, so this is the constant "app" in
    # every row. It does not separate the apps and does not need to — each app
    # has its own SQLite database, and within brgen it is `host` that tells the
    # seven cities apart. The column is here so the schema matches
    # outbound_clicks and one model can serve both apps; override in a host app
    # if these tables ever share a database.
    def visit_counting_app
      Rails.application.class.module_parent_name.to_s.downcase
    end
  end
end
