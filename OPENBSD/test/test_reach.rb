# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/utf8"
require_relative "../tools/reach"

# Every check here is shown failing before it is trusted passing. A probe nobody
# has watched fire is the same shape as the drift it looks for: complete,
# correct-looking, and measuring nothing.
#
# Two of the three would have been wrong without this. `cron` naively wants the
# scheduled path to be tracked, and resource_guard.sh is tracked at the OPENBSD
# root while being scheduled at /usr/local/bin — OPERATOR.sh installs it there,
# so a path-only check reports a false positive on a correct tree. `rcd` naively
# wants a starter, and all four *_jobs workers plus irc_gateway deliberately have
# none and say so in their own headers.
class ReachTest < Minitest::Test
  R = Pub4::OpenbsdReach

  def setup
    @tmp = Dir.mktmpdir("reach")
    %w[etc/rc.d var/nsd/etc var/nsd/zones/master usr/local/bin bin].each do |d|
      FileUtils.mkdir_p(File.join(@tmp, d))
    end
    write("etc/crontab.vm23", "PATH=/bin:/usr/local/bin\n")
    write("OPERATOR.sh", "#!/bin/ksh\n")
    write("var/nsd/etc/nsd.conf", "server:\n")
    R.root = @tmp
  end

  def teardown
    R.root = R::DEFAULT_ROOT
    FileUtils.remove_entry(@tmp)
  end

  def write(rel, body)
    path = File.join(@tmp, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def checks(kind) = R.findings.select { |f| f.check == kind }

  # ---- cron -----------------------------------------------------------------

  def test_a_scheduled_command_that_is_tracked_reaches
    write("etc/crontab.vm23", "PATH=/bin:/usr/local/bin\n*/5 * * * * /usr/local/bin/thing.sh\n")
    write("usr/local/bin/thing.sh", "#!/bin/ksh\n")

    assert_empty checks("cron")
  end

  def test_a_scheduled_command_that_is_nowhere_is_reported
    write("etc/crontab.vm23", "PATH=/bin:/usr/local/bin\n*/5 * * * * /usr/local/bin/ghost.sh\n")

    assert_equal ["/usr/local/bin/ghost.sh"], checks("cron").map(&:subject)
  end

  # The resource_guard.sh shape: tracked somewhere else, installed into place.
  def test_a_command_installed_by_operator_reaches_from_anywhere
    write("etc/crontab.vm23", "PATH=/bin:/usr/local/bin\n*/5 * * * * /usr/local/bin/guard.sh\n")
    write("guard.sh", "#!/bin/ksh\n")
    write("OPERATOR.sh", %(install -m 755 "${SCRIPT_DIR}/guard.sh" /usr/local/bin/guard.sh\n))

    assert_empty checks("cron")
  end

  # cron's own PATH excludes /usr/local/bin, where every env-shebang interpreter
  # lives. Four of five jobs had never run for exactly this.
  def test_a_command_outside_the_declared_path_is_reported
    write("etc/crontab.vm23", "PATH=/bin\n*/5 * * * * /opt/thing.sh\n")
    write("opt/thing.sh", "#!/bin/ksh\n")

    assert_includes checks("cron").map(&:subject), "/opt"
  end

  def test_redirections_are_not_mistaken_for_the_command
    write("etc/crontab.vm23", "PATH=/bin:/usr/local/bin\n0 2 * * 1 /usr/local/bin/a.sh >> /var/log/a.log 2>&1\n")
    write("usr/local/bin/a.sh", "#!/bin/ksh\n")

    assert_empty checks("cron")
  end

  # ---- rc.d -----------------------------------------------------------------

  def test_a_service_a_starter_enables_reaches
    write("etc/rc.d/thing", "#!/bin/ksh\n")
    write("start_all.sh", "rcctl enable thing\n")

    assert_empty checks("rcd")
  end

  def test_a_service_nothing_starts_and_nothing_explains_is_reported
    write("etc/rc.d/orphan", "#!/bin/ksh\ndaemon=/usr/local/bin/orphan\n")

    assert_equal ["orphan"], checks("rcd").map(&:subject)
  end

  # The *_jobs shape: deliberately off, with the rcctl lines in its own footer.
  def test_a_service_that_declares_itself_off_by_default_reaches
    write("etc/rc.d/thing_jobs", "#!/bin/ksh\n# Solid Queue worker. NOT enabled by default — see the footer.\n")

    assert_empty checks("rcd")
  end

  def test_the_rails_template_is_not_a_service
    write("etc/rc.d/rails-app.tmpl", "#!/bin/ksh\n")

    assert_empty checks("rcd")
  end

  # ---- zones ----------------------------------------------------------------

  def test_a_zone_named_and_present_reaches
    write("var/nsd/zones/master/example.no.zone", "$ORIGIN example.no.\n")
    write("var/nsd/etc/nsd.conf", %(zone:\n  name: "example.no"\n))

    assert_empty checks("zones")
  end

  def test_a_zone_file_nsd_does_not_name_is_reported
    write("var/nsd/zones/master/lonely.no.zone", "$ORIGIN lonely.no.\n")

    assert_equal ["lonely.no"], checks("zones").map(&:subject)
  end

  # nsd refuses to start over a zone whose file is missing, so this direction is
  # the one that takes DNS down rather than merely leaving a domain unserved.
  def test_a_named_zone_with_no_file_is_reported
    write("var/nsd/etc/nsd.conf", %(zone:\n  name: "ghost.no"\n))

    assert_equal ["ghost.no"], checks("zones").map(&:subject)
  end

  # ---- the live tree --------------------------------------------------------

  def test_the_real_tree_reaches
    R.root = R::DEFAULT_ROOT

    assert_empty R.findings.map { |f| "#{f.check} #{f.subject}: #{f.detail}" }
  end

  def test_the_real_tree_has_something_to_measure
    R.root = R::DEFAULT_ROOT
    counts = R.counts

    assert_operator counts["cron"], :>=, 5, "a probe over an empty population passes having measured nothing"
    assert_operator counts["rcd"], :>=, 5
    assert_operator counts["zones"], :>=, 50
  end
end
