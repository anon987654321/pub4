# frozen_string_literal: true

class PortfolioController < ApplicationController
  def show
    require File.expand_path("../../../funding_helpers.rb", __dir__)
    @portfolio_html = catalog.portfolio_summary_html
    @chart_html = FundingHelpers.portfolio_chart_block(catalog.funding)
    @compare_html = FundingHelpers.venture_compare_block(catalog.funding)
    @convergence_version = catalog.convergence_version
  end
end