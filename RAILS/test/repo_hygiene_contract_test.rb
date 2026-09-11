# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "yaml"

# What the repository may and may not hold, as distinct from what the gates
# measure. These assertions share no subject with the gate registry: they are
# about scripts reaching for a utility OpenBSD lacks, key material and a
# knowledge corpus that must never be tracked, zone files that must be
# generated rather than hand-edited, and partials duplicated per app.
#
# They sat in deploy_gates_contract_test.rb until that file crossed its length
# ceiling, and the ceiling was right about the shape: one file was answering
# two questions.
class RepoHygieneContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  REPO_ROOT = File.expand_path("../..", __dir__)
  OPENBSD_ROOT = File.join(REPO_ROOT, "OPENBSD")

  # Rails schema files create their tables with `force: :cascade`, so
  # `db:schema:load:queue` drops every table and recreates it empty. Running it
  # on every deploy — which _database.sh did until 2026-08-13 — discards every
  # enqueued background job as a side effect of deploying. brgen was carrying
  # 1670 and had 0 an hour later.
  #
  # It read as harmless because no Solid Queue worker runs on this box, so
  # nothing was going to execute them. That is an argument for fixing it before
  # a worker exists, not after: the first deploy with one would throw away the
  # password-reset emails enqueued while it was running.
  # OpenBSD ships neither lockf(1) nor flock(1) — both are FreeBSD/Linux
  # utilities. `command -v lockf` on vm23 prints nothing.
  #
  # vps_master_scan.sh called `lockf -k "$lock" env ... bin/cli "$@"`, so the
  # documented way to run a MASTER scan on the box exited with "command not
  # found" every time, having taken no lock and run no scan. The failure is
  # silent in the sense that matters: the script's own output says it locked.
  #
  # OPENBSD/bin/with-ci-lock is the same idea in Ruby, which this box has.
  def test_no_script_reaches_for_a_locking_utility_openbsd_lacks
    scripts = Dir.glob("#{File.expand_path("../OPENBSD", ROOT)}/**/*.{sh,ksh,zsh}") +
              Dir.glob("#{ROOT}/**/*.sh").reject { |p| p.include?("/vendor/") }

    offenders = scripts.flat_map do |path|
      lines = File.read(path, encoding: "UTF-8").lines
      lines.each_with_index.filter_map do |line, i|
        next if line.strip.start_with?("#")
        next unless line.match?(/(?:\A|[|;&(]|\s)(?:lockf|flock)\s+-/)
        next if guarded_by_command_v?(lines, i)

        "#{path.sub("#{File.dirname(ROOT)}/", "")}:#{i + 1}"
      end
    end

    assert_empty offenders, "OpenBSD has no lockf(1)/flock(1) — use OPENBSD/bin/with-ci-lock"
  end

  # `command -v flock` before the call is the sanctioned degrade: the script
  # takes the lock where there is one and runs unlocked where there is not,
  # which is what a portable script does with an optional utility. Without the
  # exemption every correctly guarded site reads as a failure, and a rule whose
  # failures are all false is one people learn to skip. Scoped to the enclosing
  # shell function, so a guard in one function does not excuse a bare call in
  # the next.
  def guarded_by_command_v?(lines, index)
    start = index.downto(0).find { |n| lines[n].match?(/\A[\w:.-]+\s*\(\)\s*\{/) } || 0
    lines[start..index].any? { |line| line.match?(/command -v\s+(?:lockf|flock)\b/) }
  end

  # One CI mutex, not two. The Ruby guard and the shell helper have to name the
  # same file or neither excludes the other, which is what happened: CiGuard
  # locked /var/tmp/pub4-ci.lock while ci_lock.sh pointed three scripts at
  # /var/db/pub4/ci.lock and called itself the single source.
  def test_the_ruby_and_shell_ci_locks_are_the_same_file
    shell = File.read(File.expand_path("../OPENBSD/lib/ci_lock.sh", ROOT), encoding: "UTF-8")
    ruby = File.read(File.join(ROOT, "shared/lib/operator/ci_guard.rb"), encoding: "UTF-8")

    assert_includes shell, "PUB4_CI_LOCK_DIR=/var/db/pub4"
    assert_includes shell, "PUB4_CI_LOCK_NAME=ci.lock"
    assert_includes ruby, 'LOCK_DIR = "/var/db/pub4"'
    assert_includes ruby, 'DEFAULT_LOCK_PATH = File.join(LOCK_DIR, "ci.lock")'
  end

  def test_secondary_schema_load_is_guarded_by_an_initialisation_check
    source = File.read(File.join(ROOT, "_database.sh"), encoding: "UTF-8")

    assert_includes source, "secondary_db_initialized",
                    "the deploy must check before loading a secondary schema over live data"

    body = source[/rails_prepare_secondary_dbs_as_app\(\).*?\n}/m]

    refute_nil body, "rails_prepare_secondary_dbs_as_app no longer parses as one function"
    assert_includes body, "if secondary_db_initialized",
                    "db:schema:load must sit behind the guard, not beside it"

    guard_line = body.lines.index { |l| l.include?("if secondary_db_initialized") }
    load_line = body.lines.index { |l| l.include?("db:schema:load:${db}") && !l.strip.start_with?("#") }

    assert_operator guard_line, :<, load_line, "the guard must precede the load it guards"
  end

  def test_local_knowledge_corpus_is_not_tracked
    files = git_files("MASTER/knowledge")

    assert_empty files, "MASTER/knowledge is local-only and must remain untracked"
  end

  # Zone files became tracked on 2026-08-12: they are generated by
  # OPENBSD/bin/render_dns.rb, and git is where the SOA serial history has to
  # live — a fresh checkout regenerating them from nothing would restart serials
  # at today's 01 and could hand ns.hyp.net a lower number than it already holds,
  # which makes a secondary refuse every transfer. This used to assert
  # templates-only, and the templates are gone with the loop that read them.
  #
  # The invariant that survives is about what must NOT be tracked. K*.private is
  # a DNSSEC signing key; .zone.signed, K*.key and *.ds are all derived from one
  # and belong only on the box.
  def test_no_dnssec_key_material_is_tracked
    secrets = git_files("OPENBSD/var/nsd").grep(/\.private\z|\.zone\.signed\z|\/K[^\/]+\.key\z|\.ds\z/)

    assert_empty secrets, "DNSSEC key material must never be committed:\n  #{secrets.join("\n  ")}"
  end

  def test_every_nsd_zone_file_is_tracked_and_generated
    tracked = git_files("OPENBSD/var/nsd")

    assert_includes tracked, "OPENBSD/var/nsd/etc/nsd.conf"

    zones = tracked.grep(%r{\AOPENBSD/var/nsd/zones/master/.+\.zone\z})
    assert_operator zones.size, :>=, 50, "expected the generated zone set, found #{zones.size}"

    ungenerated = zones.reject do |rel|
      File.read(File.join(REPO_ROOT, rel)).start_with?("; Generated by OPENBSD/bin/render_dns.rb")
    end
    assert_empty ungenerated, "hand-written zone file(s) — run `ruby OPENBSD/bin/render_dns.rb`:\n  #{ungenerated.join("\n  ")}"
  end

  def test_openbsd_has_operator_surfaces
    %w[
      OPENBSD/OPERATOR.sh
      OPENBSD/bin/check
      OPENBSD/lib/gate_environment.rb
      OPENBSD/integrity_gate.rb
      OPENBSD/vps_ci.sh
    ].each do |rel|
      assert File.exist?(File.join(REPO_ROOT, rel)), "missing #{rel}"
    end
  end

  def test_shared_search_partials_are_not_duplicated_per_app
    %w[_search_loading.html.erb _search_suggestions.html.erb].each do |partial|
      canonical = File.join(ROOT, "shared", "app", "views", "shared", partial)
      assert_path_exists canonical

      %w[amber brgen bsdports].each do |app|
        duplicate = File.join(ROOT, app, "app", "views", "shared", partial)
        refute_path_exists duplicate, "#{app} must use shared/#{partial} from the shared engine"
      end
    end
  end

  def test_comment_destroy_stream_is_shared
    canonical = File.join(ROOT, "shared", "app", "views", "comments", "destroy.turbo_stream.erb")
    assert_path_exists canonical

    %w[amber brgen bsdports].each do |app|
      duplicate = File.join(ROOT, app, "app", "views", "comments", "destroy.turbo_stream.erb")
      refute_path_exists duplicate, "#{app} must use the shared comment destroy stream"
    end
  end

  private

  def git_files(path)
    output, status = Open3.capture2("git", "-C", REPO_ROOT, "ls-files", path)
    assert status.success?, "git ls-files failed for #{path}"
    output.lines.map(&:chomp).reject(&:empty?).sort
  end


end
