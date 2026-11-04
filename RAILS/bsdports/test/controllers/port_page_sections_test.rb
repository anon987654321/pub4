# frozen_string_literal: true

require "test_helper"

# Sections of the port, maintainer and filtered index pages that said less
# than they knew: a reverse-dependency list cut at 20 without a word, raw
# severity enums in date order, a fake unified diff per update, a category
# filter that never named itself, and a maintainer page that went blank.
class PortPageSectionsTest < ActionDispatch::IntegrationTest
  setup do
    @platform = platforms(:openbsd)
    @category = Category.create!(platform: @platform, name: "devel", slug: "devel", description: "Developer tools")
    @library = make_port("libfoo")
  end

  def make_port(name, **extra)
    Port.create!({ platform: @platform, category: @category, name:, version: "1",
                   pkgpath: "devel/#{name}" }.merge(extra))
  end

  test "a long reverse-dependency list states its total and offers the rest" do
    21.times { |index| Dependency.create!(port: make_port("app#{index}"), depends_on: @library, dep_type: "run") }

    get port_path(@library)
    assert_select "h2#required-by", text: I18n.t("ports.required_by_count", count: 21)
    assert_select "ul[aria-label=?] li", I18n.t("ports.rdeps_label"), 20
    assert_select "a[href=?]", port_path(@library, rdeps: "all", anchor: "required-by")

    get port_path(@library, rdeps: "all")
    assert_select "ul[aria-label=?] li", I18n.t("ports.rdeps_label"), 21
  end

  test "advisories read their severity in words, the worst first" do
    { "CVE-2099-0001" => :low, "CVE-2099-0002" => :critical }.each do |identifier, severity|
      advisory = SecurityAdvisory.create!(identifier:, title: identifier, severity:, published_at: Time.current)
      SecurityAdvisoryPort.create!(security_advisory: advisory, port: @library)
    end

    get port_path(@library)
    labels = css_select("h2 + ul li small").map(&:text).grep(Regexp.union(I18n.t("ports.severity").values))
    assert_equal [ I18n.t("ports.severity.critical"), I18n.t("ports.severity.low") ], labels
  end

  test "version history is a version change and its message, not a diff" do
    @library.port_updates.create!(old_version: "1.0", new_version: "1.1", commit_message: "Update to 1.1",
                                  committed_at: Time.current)

    get port_path(@library)
    assert_select "code", text: I18n.t("ports.version_change", old: "1.0", new: "1.1")
    assert_select "p", text: "Update to 1.1"
    assert_not_includes response.body, "+++ b/"
  end

  test "a category-filtered list names the category and links back to every port" do
    get ports_path(category_id: @category.id)
    assert_select "h2", text: I18n.t("ports.filtered_by", name: "devel")
    assert_select "p", text: "Developer tools"
    assert_select "a[href=?]", ports_path, text: I18n.t("ports.clear_filter")
  end

  test "a maintainer left with no ports says so" do
    maintainer = Maintainer.create!(name: "Kari Nordmann")

    get maintainer_path(maintainer)
    assert_response :success
    assert_select "p.data-state", text: I18n.t("maintainers.no_ports")
  end
end
