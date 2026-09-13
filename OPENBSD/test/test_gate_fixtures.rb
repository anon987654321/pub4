# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../lib/utf8"
require_relative "../installed_targets_gate"

# Every OPENBSD gate beside the defect it exists to catch.
#
# A gate that only ever runs over this checkout and says clean proves nothing: it
# says clean just as well with its body gutted. So each pair here plants the
# shape the gate must flag, watches it fail, and runs the committed tree for the
# shape it must not — the house decision of 2026-08-22.
class InstalledTargetsGateFixtureTest < Minitest::Test
  GATE = Deploy::InstalledTargetsGate

  def setup
    @tmp = Dir.mktmpdir("installed-targets")
    GATE.root = @tmp
  end

  def teardown
    GATE.root = GATE::DEFAULT_ROOT
    FileUtils.remove_entry(@tmp)
  end

  def plant(rel, body)
    path = File.join(@tmp, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def missing = GATE.orphans.keys

  # The daily.local shape the gate was written for: a guard on a target nothing
  # installs.
  def test_a_cron_target_nothing_installs_is_named
    plant("etc/crontab.vm23", "*/5 * * * * /usr/local/bin/ghost.sh\n")

    assert_equal ["bin/ghost.sh"], missing
  end

  # resource_guard.sh is installed from the tree root and calls its crisis tier by
  # its installed path. A script the repo installs is a referrer like any crontab.
  def test_an_installed_script_naming_a_target_nothing_installs_is_named
    plant("OPERATOR.sh", %(install -m 755 "${SCRIPT_DIR}/guard.sh" /usr/local/bin/guard.sh\n))
    plant("guard.sh", "[ -x /usr/local/bin/crisis.sh ] && /usr/local/bin/crisis.sh\n")

    assert_equal ["bin/crisis.sh"], missing
  end

  def test_an_install_line_provides_its_target
    plant("OPERATOR.sh", <<~SH)
      install -m 755 "${SCRIPT_DIR}/guard.sh" /usr/local/bin/guard.sh
      install -m 755 "${SCRIPT_DIR}/crisis.sh" /usr/local/bin/crisis.sh
    SH
    plant("guard.sh", "/usr/local/bin/crisis.sh\n")
    plant("crisis.sh", "#!/bin/ksh\n")

    assert_empty missing
  end

  # libexec is copied wholesale like bin, and root dot-sources what is in it.
  def test_a_libexec_target_is_measured_and_shipping_it_provides_it
    plant("etc/daily.local", ". /usr/local/libexec/helper.ksh\n")

    assert_equal ["libexec/helper.ksh"], missing

    plant("usr/local/libexec/helper.ksh", "#!/bin/ksh\n")

    assert_empty missing
  end

  def test_a_directory_named_in_prose_is_not_a_target
    plant("etc/daily.local", "# nothing lives in /usr/local/bin/lib/ any more\n")

    assert_empty GATE.referenced
  end

  def test_the_committed_tree_names_the_crisis_tier_and_provides_it
    GATE.root = GATE::DEFAULT_ROOT

    assert_includes GATE.referenced.keys, "bin/emergency_cpu.sh",
                    "resource_guard.sh's crisis path is no longer read, so a missing install would pass"
    assert_includes GATE.referenced.keys, "libexec/stale_ci_cleanup.ksh"
    assert_empty GATE.orphans
  end
end
