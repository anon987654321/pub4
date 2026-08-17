# frozen_string_literal: true

# Pull TradeDoubler Link Converter script onto this origin so ad blockers that
# target tradedoubler.com do not strip tracking from UGC links.
class LinkConverterSyncJob < ApplicationJob
  queue_as :bulk

  RELATIVE_PATH = "js/td-lc.js"

  def perform
    return false unless Shared::Tradedoubler.link_converter_configured?

    path = Rails.public_path.join(RELATIVE_PATH)
    ok = Shared::Tradedoubler.sync_link_converter!(local_path: path.to_s)
    Rails.logger.info("[link_converter_sync] ok=#{ok} path=#{path}")
    ok
  end
end
