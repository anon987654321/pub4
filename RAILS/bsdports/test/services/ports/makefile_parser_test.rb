# frozen_string_literal: true

require "test_helper"

class Ports::Openbsd::MakefileParserTest < ActiveSupport::TestCase
  test "parses makefile metadata and depends" do
    path = Rails.root.join("test/fixtures/ports/openbsd/devel/git/Makefile")
    metadata = Ports::Openbsd::MakefileParser.parse(path)

    assert_equal "git", metadata[:name]
    assert_equal "devel/git", metadata[:pkgpath]
    assert_equal "distributed version control", metadata[:comment]
    assert_includes metadata[:build_depends], "devel/gettext"
    assert_includes metadata[:lib_depends], "security/openssl"
    assert_equal "2.43.0", metadata[:version]
    assert metadata[:permit_file_distfiles]
  end
end
