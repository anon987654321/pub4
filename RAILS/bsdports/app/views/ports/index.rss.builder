xml.instruct! :xml, version: "1.0"
xml.rss version: "2.0" do
  xml.channel do
    xml.title t("ports.rss.title")
    xml.link ports_url(format: :rss)
    xml.description t("ports.rss.description")
    xml.language I18n.locale.to_s
    @ports.each do |port|
      xml.item do
        xml.title [ port.name, port.version ].join("-")
        xml.link port_url(port)
        xml.description do
          xml.cdata! [ port.comment, port.description ].compact.join("\n\n")[0, 500]
        end
        if port.last_updated
          xml.pubDate port.last_updated.to_time.rfc2822
        end
        xml.guid port_url(port), isPermaLink: true
        xml.category port.category.name if port.category
      end
    end
  end
end
