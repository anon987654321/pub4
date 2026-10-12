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
    reader = source[/^css_href=\$\(.*"\$RUBY" -e '([^']+)'\)$/, 1]
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

  # dr-pull against a fake ssh that plays vm23: three SQLite databases, a
  # sha256 -r listing and a tar stream, all in a scratch directory. Nothing here
  # touches the box or the operator's real ~/pub4-dr.
  FAKE_SSH = <<~'RUBY'
    #!/usr/bin/env ruby
    require "digest"
    require "fileutils"
    remote = ENV.fetch("FAKE_VM23")
    cmd = ARGV.last.to_s
    case cmd
    when /VACUUM INTO/
      FileUtils.mkdir_p(remote)
      %w[brgen amber bsdports].each do |app|
        db = File.join(remote, "#{app}-production.sqlite3")
        system("sqlite3", db, "CREATE TABLE IF NOT EXISTS schema_migrations(version); INSERT INTO schema_migrations VALUES ('20260928090000'); CREATE TABLE users(id integer); INSERT INTO users VALUES (1);")
      end
      puts "total 0"
    when /dr_pull_ok/
      File.write(File.join(ENV.fetch("FAKE_VM23_BLOBS"), "dr_pull_ok"), Time.now.to_i.to_s)
    when /sha256 -r/
      Dir[File.join(remote, "*.sqlite3")].sort.each { |p| puts "#{Digest::SHA256.file(p).hexdigest} #{File.basename(p)}" }
    when %r{/home/(\w+)/app/storage}
      app = $1
      src = File.join(ENV.fetch("FAKE_VM23_BLOBS"), app)
      if app == "brgen"
        FileUtils.mkdir_p(File.join(src, "ab"))
        File.write(File.join(src, "ab", "blob"), "uploaded")
        exec("tar", "-C", src, "-cf", "-", "ab")
      end
    when /tar -C/
      exec("tar", "-C", remote, "-cf", "-", ".")
    end
  RUBY

  def dr_env(dir)
    bin = File.join(dir, "bin")
    FileUtils.mkdir_p(bin)
    File.write(File.join(bin, "ssh"), FAKE_SSH)
    File.chmod(0o755, File.join(bin, "ssh"))
    { "PATH" => "#{bin}:#{ENV['PATH']}", "FAKE_VM23" => File.join(dir, "vm23"), "FAKE_VM23_BLOBS" => File.join(dir, "vm23blobs"),
      "PUB4_DR_DIR" => File.join(dir, "dr"), "PUB4_SSH_KEY" => File.join(dir, "key") }
  end

  def dr_pull(env, *args)
    Open3.capture3(env, RbConfig.ruby, File.join(ROOT, "bin", "dr-pull"), *args)
  end

  def test_dr_pull_records_vm23s_checksums_and_the_drill_reads_the_pull_back
    skip "sqlite3 CLI missing" unless system("sqlite3", "-version", out: File::NULL, err: File::NULL)

    Dir.mktmpdir do |dir|
      env = dr_env(dir)
      out, err, status = dr_pull(env)
      assert status.success?, "pull failed: #{out}#{err}"
      pull = Dir[File.join(dir, "dr", "2*")].first
      sums = File.read(File.join(pull, "SHA256SUMS"))
      assert_equal 3, sums.lines.size
      assert_match(/\A\h{64}  amber-production\.sqlite3$/, sums.lines.first)

      assert File.file?(File.join(dir, "dr", "blobs", "brgen", "ab", "blob")), "uploaded files were not pulled"
      assert_match(/\A\d+\z/, File.read(File.join(dir, "vm23blobs", "dr_pull_ok")), "the box was not told a pull landed")
      refute Dir.exist?(File.join(dir, "dr", "blobs", "amber")), "an app with no uploads gets no blob directory"

      out, err, status = dr_pull(env, "--drill")
      assert status.success?, "drill failed: #{out}#{err}"
      assert_includes out, "brgen blobs: 1 file(s)"
      assert_includes out, "matches the pull"
      assert_includes out, "brgen: integrity ok, migration 20260928090000"
      assert_includes out, "restores and reads back"
      assert Dir.exist?(pull), "the drill must leave the pull itself alone"

      File.open(File.join(pull, "amber-production.sqlite3"), "ab") { |f| f.write("x") }
      out, err, status = dr_pull(env, "--drill")
      refute status.success?, "a pull altered after the fact must fail the drill"
      assert_includes out, "MISMATCH"
      assert_includes err, "checksum"
    end
  end

  def test_dr_pull_refuses_a_stream_whose_bytes_differ_from_vm23s_checksum
    skip "sqlite3 CLI missing" unless system("sqlite3", "-version", out: File::NULL, err: File::NULL)

    Dir.mktmpdir do |dir|
      env = dr_env(dir)
      bin = File.join(dir, "bin", "ssh")
      File.write(bin, File.read(bin).sub('exec("tar", "-C", remote, "-cf", "-", ".")',
                                         'File.open(File.join(remote, "brgen-production.sqlite3"), "ab") { |f| f.write("torn") }; exec("tar", "-C", remote, "-cf", "-", ".")'))
      _, err, status = dr_pull(env)
      refute status.success?
      assert_includes err, "checksum differs from vm23's"
    end
  end
end
