# frozen_string_literal: true

class SecurityAdvisoryRefreshJob < ApplicationJob
  queue_as :bulk

  def perform
    Rails.logger.info("bsdports: refreshing security advisories")
    # Placeholder: scrape OpenBSD errata and upsert SecurityAdvisory records.
  end
end
