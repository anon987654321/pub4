# frozen_string_literal: true

class SitemapsController < ApplicationController
  def show
    render xml: catalog.sitemap_xml
  end
end