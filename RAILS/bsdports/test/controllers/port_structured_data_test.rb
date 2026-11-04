# frozen_string_literal: true

require "test_helper"

# The port page carried only the site-wide WebSite schema; the ports index
# opened on a list of questions written for the operator; and every install
# command sat over three clauses of caveats.
class PortStructuredDataTest < ActionDispatch::IntegrationTest
  setup do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel")
    @port = Port.create!(platform:, category:, name: "git", version: "2.45.0", pkgpath: "devel/git",
                         comment: "distributed version control", homepage: "https://git-scm.com/")
  end

  def schema_of(type)
    css_select("script[type='application/ld+json']").map { JSON.parse(_1.text) }.find { _1["@type"] == type }
  end

  test "a port page describes the port as a SoftwareApplication" do
    get port_path(@port)
    app = schema_of("SoftwareApplication")
    assert app, "the port page emitted no SoftwareApplication"
    assert_equal "https://schema.org", app["@context"]
    assert_equal [ "git", "2.45.0", "OpenBSD", "https://git-scm.com/" ],
                 app.values_at("name", "softwareVersion", "operatingSystem", "url")
  end

  test "a port without a homepage points its schema at its own page" do
    @port.update!(homepage: nil)
    get port_path(@port)
    assert_equal port_url(@port), schema_of("SoftwareApplication")["url"]
  end

  test "the index lead is one sentence for a visitor and the install note links the rest" do
    get ports_path
    assert_select ".ports-purpose", text: I18n.t("ports.purpose")
    assert_no_match(/\?/, I18n.t("ports.purpose"))

    get port_path(@port)
    assert_select ".install-panel a[href=?]", "https://man.openbsd.org/pkg_add"
  end
end
