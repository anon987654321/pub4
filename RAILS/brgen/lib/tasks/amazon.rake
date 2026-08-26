# frozen_string_literal: true

require "cgi"

namespace :scrape do
  desc "Amazon search results via Ferrum + vision LLM (queries: comma-separated)"
  task :amazon, [ :queries ] => :environment do |_, args|
    queries = (args[:queries] || "vinyl,turntable,headphones").split(",").map(&:strip)
    schema = %w[title url price currency image_url asin rating reviews prime]
    queries.each do |q|
      Scrape.call(
        "https://www.amazon.com/s?k=#{CGI.escape(q)}",
        schema: schema,
        hint: "Skip the sponsored carousel at the top. asin is the 10-char product id in the URL after /dp/. price is a number, currency is the symbol or ISO code. prime is true/false based on the badge."
      ).each { |item| puts item.merge("query" => q).to_json }
    end
  end
end
