class AffiliateProductsController < ApplicationController

  # Corresponds to `routes.rb`

  def banner
    @products = AffiliateProducts.fetch
  end

  def jqm_popup
    @products = AffiliateProducts.fetch
  end

  def jqm_page
    @products = AffiliateProducts.fetch
  end
end

