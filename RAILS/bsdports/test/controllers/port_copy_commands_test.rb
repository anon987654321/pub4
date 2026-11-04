# frozen_string_literal: true

require "test_helper"

# The install panel offered a copy button only for pkg_add; the pkgpath and
# the build-from-ports command had to be retyped.
class PortCopyCommandsTest < ActionDispatch::IntegrationTest
  test "pkg_add, make install and the pkgpath each have a labelled copy field" do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel")
    port = Port.create!(platform:, category:, name: "git", version: "2.45", pkgpath: "devel/git")

    get port_path(port)
    assert_response :success
    {
      "doas pkg_add git" => "ports.copy_pkg_add",
      "cd /usr/ports/devel/git && make install" => "ports.copy_make_install",
      "devel/git" => "ports.copy_pkgpath",
    }.each do |text, key|
      assert_select ".install-panel input[readonly][value=?][aria-label=?]", text, I18n.t(key)
    end
  end
end
