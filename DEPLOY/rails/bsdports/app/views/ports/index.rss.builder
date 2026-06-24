xml.instruct! :xml, version: "1.0"
xml.rss version: "2.0" do
  xml.channel do
    xml.title "OpenBSD ports - new (last 7 days)"
    xml.link ports_url(format: :rss)
    xml.description "Recently added or updated ports from the OpenBSD ports tree"
    xml.language "en-us"
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
