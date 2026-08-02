# frozen_string_literal: true

# Nightly TradeDoubler (and other network) product + voucher import.
class AffiliateImportJob < ApplicationJob
  queue_as :bulk

  def perform(category = nil)
    results = Affiliate.import_all!(category: category)
    voucher_count = Tradedoubler.import_vouchers!
    Rails.logger.info(
      "[affiliate_import] products=#{results.inspect} vouchers=#{voucher_count} " \
      "live=#{AffiliateProduct.sellable.real.count}"
    )
    { products: results, vouchers: voucher_count }
  end
end
