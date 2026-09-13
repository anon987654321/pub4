# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class Ports::Openbsd::MakefileParserTest < ActiveSupport::TestCase
  test "parses makefile metadata and depends" do
    path = Rails.root.join("test/fixtures/ports/openbsd/devel/git/Makefile")
    metadata = Ports::Openbsd::MakefileParser.parse(path)

    assert_equal "git", metadata[:name]
    assert_equal "devel/git", metadata[:pkgpath]
    assert_includes metadata[:build_depends], "devel/gettext"
    assert_includes metadata[:lib_depends], "security/openssl"
    assert_equal "2.43.0", metadata[:version]
    assert metadata[:permit_file_distfiles]
  end

  test "?= leaves a variable that is already set alone" do
    metadata = Ports::Openbsd::MakefileParser.parse(Rails.root.join("test/fixtures/ports/openbsd/devel/git/Makefile"))

    assert_equal "distributed version control", metadata[:comment]
  end

  test "?= sets a variable that is unset" do
    metadata = parse_makefile(<<~MAKE)
      DISTNAME = tool-1.2
      PKGNAME ?= ${DISTNAME}
    MAKE

    assert_equal "1.2", metadata[:version]
  end

  test "+= appends to the value before it" do
    metadata = Ports::Openbsd::MakefileParser.parse(Rails.root.join("test/fixtures/ports/openbsd/devel/git/Makefile"))

    assert_equal %w[devel/gettext textproc/asciidoc], metadata[:run_depends]
  end

  test "+= on an unset variable starts it" do
    metadata = parse_makefile("RUN_DEPENDS += devel/gettext\n")

    assert_equal %w[devel/gettext], metadata[:run_depends]
  end

  test "a restricted port does not permit distfiles" do
    metadata = parse_makefile(%(PERMIT_PACKAGE = "patent issues"\n))

    assert_equal false, metadata[:permit_file_distfiles]
  end

  test "PERMIT_DISTFILES overrides the PERMIT_PACKAGE default" do
    assert_equal true, parse_makefile("PERMIT_PACKAGE = no fee\nPERMIT_DISTFILES = Yes\n")[:permit_file_distfiles]
    assert_equal false, parse_makefile("PERMIT_PACKAGE = Yes\nPERMIT_DISTFILES = no redistribution\n")[:permit_file_distfiles]
  end

  private

  def parse_makefile(body)
    Dir.mktmpdir do |dir|
      port_dir = File.join(dir, "devel", "tool")
      FileUtils.mkdir_p(port_dir)
      File.write(File.join(port_dir, "Makefile"), body)
      Ports::Openbsd::MakefileParser.parse(File.join(port_dir, "Makefile"))
    end
  end
end
