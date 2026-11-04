# frozen_string_literal: true

module PortsHelper
  # A dependency-graph node carries the id and pkgpath, which is all to_param needs.
  def graph_node_path(node)
    port_path(Port.new(id: node[:id], pkgpath: node[:pkgpath]))
  end

  # A port homepage as its host ("git-scm.com") with the full URL in title,
  # so a long homepage does not wrap across the definition list. A value
  # that is not an http(s) URL is printed as text, as before.
  def homepage_link(url)
    return url unless url.match?(%r{\Ahttps?://}i)

    host = URI.parse(url).host.presence || url
    link_to host.delete_prefix("www."), url, title: url, rel: "nofollow noopener noreferrer"
  rescue URI::InvalidURIError
    link_to url, url, rel: "nofollow noopener noreferrer"
  end
end
