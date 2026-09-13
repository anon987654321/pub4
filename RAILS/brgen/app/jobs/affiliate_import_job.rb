# frozen_string_literal: true

# Nightly TradeDoubler (and other network) product + voucher import.
class AffiliateImportJob < ApplicationJob
  queue_as :bulk
  # A second import started while one runs writes the same products twice.
  limits_concurrency to: 1, key: "affiliate-import", duration: 1.hour, on_conflict: :discard

  def perform(category = nil)
    results = Shared::Affiliate.import_all!(category: category)
    voucher_count = Shared::Tradedoubler.import_vouchers!
    Rails.logger.info(
      "[affiliate_import] products=#{results.inspect} vouchers=#{voucher_count} " \
      "live=#{Shared::AffiliateProduct.sellable.real.count}"
    )
    { products: results, vouchers: voucher_count }
  end
end
