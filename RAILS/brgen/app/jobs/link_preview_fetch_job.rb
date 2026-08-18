# frozen_string_literal: true

# Reads a linked page's own description of itself. Runs off the request, because
# a remote server that takes ten seconds must not hold a message send open.
class LinkPreviewFetchJob < ApplicationJob
  queue_as :bulk

  # Only the head of the document is needed, and a page that puts its OpenGraph
  # tags after 256 KB is a page we can live without a preview of.
  MAX_HTML = 256_000

  def perform(link_preview_id)
    preview = LinkPreview.find_by(id: link_preview_id)
    return if preview.nil?
    return if preview.ok? && !preview.stale?

    document = fetch(preview.url)
    if document.nil?
      preview.update!(status: "failed", fetched_at: Time.current)
      return
    end

    preview.update!(
      title: meta(document, "og:title") || document.at("title")&.text.to_s.strip.presence,
      description: meta(document, "og:description") || meta_name(document, "description"),
      site_name: meta(document, "og:site_name") || preview.host,
      status: "ok",
      fetched_at: Time.current
    )
  end

  private

  def fetch(url)
    uri = URI(url)
    return nil unless uri.is_a?(URI::HTTPS) && OutboundHttp.public_https?(uri)

    response = get(uri)
    return nil unless response.is_a?(Net::HTTPSuccess)
    return nil unless response["content-type"].to_s.start_with?("text/html")

    Nokogiri::HTML(response.body.to_s[0, MAX_HTML])
  rescue *OutboundHttp::NETWORK_ERRORS => e
    Rails.logger.warn("link_preview: #{url} failed: #{e.class}")
    nil
  end

  def get(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = OutboundHttp::TIMEOUT
    http.read_timeout = OutboundHttp::TIMEOUT
    request = Net::HTTP::Get.new(uri.request_uri)
    request["Accept"] = "text/html"
    request["User-Agent"] = "brgen link preview"
    http.request(request)
  end

  def meta(document, property)
    document.at("meta[property='#{property}']")&.[]("content").to_s.strip.presence
  end

  def meta_name(document, name)
    document.at("meta[name='#{name}']")&.[]("content").to_s.strip.presence
  end
end
