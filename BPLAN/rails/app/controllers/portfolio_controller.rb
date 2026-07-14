# frozen_string_literal: true

class PortfolioController < ApplicationController
  def show
    @portfolio_html = catalog.portfolio_summary_html
    @convergence_version = catalog.convergence_version
  end
end