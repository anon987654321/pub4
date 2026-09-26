# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
# Every read below inspects UTF-8 source. Under a C locale -- which is how the
# weekly integrity run invokes these on vm23 -- Ruby defaults file reads to
# US-ASCII and each one raises "invalid byte sequence". Same require, same
# reason, as MASTER/gates/runner.rb.
require_relative "../lib/utf8"

class RestoreScriptsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_restore_litestream_is_litestream_restore
    source = File.read(File.join(ROOT, "bin", "restore_litestream.sh"))
    assert_includes source, "litestream restore"
    refute_includes source, "MASTER/RAILS"
  end

  # litestream is absent from this box and unpackageable, so every precondition
  # in restore_litestream.sh is false and a skipping version walked all three apps,
  # restored none and exited 0. A restore that reports success having restored
  # nothing is read as evidence the backups work.
  def test_restore_litestream_fails_rather_than_skipping
    source = File.read(File.join(ROOT, "bin", "restore_litestream.sh"))
    assert_includes source, "require_litestream", "no check that the binary exists"
    refute_match(/log "skip \$app/, source, "a missing replica must fail, not skip")
    assert_match(/missing replica \$replica"; exit 1/, source)
    assert_includes source, "dr-pull", "the failure must name the backup that does work"
  end

  # Run, not read. The config failure used to print to stdout, where the loop read
  # it as an app name and failed later on "/home/[restore] missing…/app/storage".
  def test_a_dry_run_with_no_config_fails_on_the_config
    env = { "DRY_RUN" => "1", "LITESTREAM_CONFIG" => File.join(Dir.tmpdir, "no-such-litestream.yml") }
    out, err, status = Open3.capture3(env, "zsh", File.join(ROOT, "bin", "restore_litestream.sh"))

    assert_equal 1, status.exitstatus
    assert_includes err, "missing litestream config"
    refute_includes out, "/home/", "a log line was read as an app name"
    refute_includes out, "done"
  end

  def test_a_dry_run_of_a_config_plans_only_its_apps
    Dir.mktmpdir("litestream") do |dir|
      config = File.join(dir, "litestream.yml")
      File.write(config, "dbs:\n  - path: /home/ghostapp/app/storage/production.sqlite3\n")
      out, _, status = Open3.capture3({ "DRY_RUN" => "1", "LITESTREAM_CONFIG" => config },
                                      "zsh", File.join(ROOT, "bin", "restore_litestream.sh"))

      assert_equal 1, status.exitstatus, "the app has no storage here, so the plan must fail rather than skip"
      assert_includes out, "FAIL ghostapp — missing /home/ghostapp/app/storage"
    end
  end

  def test_vps_deploy_stamps_head_after_the_work
    source = File.read(File.join(ROOT, "bin/vps-deploy"))
    assert_includes source, "write_stamp()"
    assert_includes source, 'sha=$(git -C "$repo" rev-parse --short HEAD)'
    # The read must live inside write_stamp, not above the master pull.
    write = source[ /write_stamp\(\) \{.*?\n\}/m ]
    assert write, "write_stamp function missing"
    assert_includes write, "rev-parse --short HEAD"
    refute_match(/sha=\$\(git -C "\$repo" rev-parse --short HEAD\)\nstarted=/, source.split("write_stamp()")[0])
    assert_includes source, "pull --ff-only origin main"
    assert_includes source, 'write_stamp master failed'
    assert_includes source, 'write_stamp "$app" failed'
  end

  def test_vps_ci_mirrors_the_tracked_tree_not_vendor
    source = File.read(File.join(ROOT, "bin", "vps_ci.sh"))
    assert_includes source, "git -C \"$repo\" archive HEAD RAILS"
    refute_includes source, 'doas tar cf - -C "$repo" RAILS'
    assert_includes source, "vendor/javascript"
    assert_includes source, "public"
  end

  # public/assets is the one synced directory git does not carry — Propshaft
  # writes it on the box at precompile. Pruning public/ wholesale deleted the
  # running site's stylesheets, and it happened before bin/ci, so a CI failure
  # left the new code live with no assets: brgen served every page with a 404ing
  # <link> on 2026-08-14 while /up, rcctl check and the TLS probe all passed.
  def test_vps_ci_keeps_compiled_assets_across_the_prune
    source = File.read(File.join(ROOT, "bin", "vps_ci.sh"))
    prune = source[/for dir_rel in test app lib config bin db engines public.*?done/m]
    assert prune, "the prune loop moved — re-read this before trusting the assertions below"
    assert_includes prune, "public/assets", "the prune must special-case the one directory git does not carry"
    assert_match(/mv .*public\/assets.*assets-carry/, prune, "assets must be held aside, not deleted")
    assert_match(/mv .*assets-carry.*public\/assets/, prune, "…and put back")
  end

  # /up answers before Propshaft is reached, so it cannot tell a styled site from
  # an unstyled one. The deploy asks for the stylesheet the page links, through
  # the Host that owns it — a bare-IP request 403s on these apps, which would
  # pass by finding no link at all.
  def test_vps_deploy_verifies_the_page_stylesheet_resolves
    source = File.read(File.join(ROOT, "bin/vps-deploy"))
    assert_includes source, "css_href", "no stylesheet verification after restart"
    # The reader is run rather than matched: what matters is the href it finds
    # on a page that links one, and nothing, not a failure, on a page that does
    # not — under set -e a failing read ends the deploy with no stamp.
    reader = source[/^css_href=\$\(.*ruby34 -e '([^']+)'\)$/, 1]
    assert reader, "must read the href off the rendered page"
    link = '<link rel="stylesheet" href="/assets/application-1a2b.css">'
    found, status = Open3.capture2(RbConfig.ruby, "-e", reader, stdin_data: link)
    assert_equal ["/assets/application-1a2b.css", true], [found, status.success?]
    found, status = Open3.capture2(RbConfig.ruby, "-e", reader, stdin_data: "<p>no link</p>")
    assert_equal ["", true], [found, status.success?]
    assert_match(/^home_page=\$\(curl .*\) \|\| \{\n\s*write_stamp "\$app" failed/, source,
                 "a home page that does not answer must fail the deploy with a stamp")
    assert_includes source, 'Host: ${domain}', "must ask through the app's own Host or it 403s"
    assert_match(/css_href.*\n.*write_stamp "\$app" failed/m.freeze, source[/if \[\[ -n \$css_href \]\].*?^fi/m].to_s,
                 "a 404 stylesheet must fail the deploy, not warn")
  end
end
