# frozen_string_literal: true

require "minitest/autorun"
# Every read below inspects UTF-8 source. Under a C locale -- which is how the
# weekly integrity run invokes these on vm23 -- Ruby defaults file reads to
# US-ASCII and each one raises "invalid byte sequence". Same require, same
# reason, as RAILS/gates/runner.rb.
require_relative "../lib/utf8"

class RestoreScriptsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_restore_backups_is_litestream_restore
    source = File.read(File.join(ROOT, "restore_backups.sh"))
    assert_includes source, "litestream restore"
    assert_includes source, "extract_legacy_installers.sh"
    refute_includes source, "MASTER/RAILS"
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
    source = File.read(File.join(ROOT, "vps_ci.sh"))
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
    source = File.read(File.join(ROOT, "vps_ci.sh"))
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
    assert_match(%r{grep -oE '/assets/\[\^"\]\+\\\.css'}, source, "must read the href off the rendered page")
    assert_includes source, 'Host: ${domain}', "must ask through the app's own Host or it 403s"
    assert_match(/css_href.*\n.*write_stamp "\$app" failed/m.freeze, source[/if \[\[ -n \$css_href \]\].*?^fi/m].to_s,
                 "a 404 stylesheet must fail the deploy, not warn")
  end

  def test_extract_legacy_installers_targets_top_level_rails
    source = File.read(File.join(ROOT, "extract_legacy_installers.sh"))
    assert_includes source, 'scripts_root="$ROOT_DIR/RAILS"'
    refute_includes source, "MASTER/RAILS"
  end
end
