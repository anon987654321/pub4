# frozen_string_literal: true

require "minitest/autorun"

# No key material and no encrypted credentials in the tree, as a test rather than a
# .gitignore line — because .gitignore is what already failed here.
#
# github.com/anon987654321/pub4 is public and its history holds seven real 32-hex
# master.key blobs: DEPLOY/rails/{brgen,amber,bsdports,baibl,blognet,hjerterom}/
# config/master.key, added 2026-05-06 (ffb39dc12, b1882a484), moved 2026-05-17
# (28bad8208) and emptied 2026-05-29 (4f3780d89, 6f81a4d34) — plus MASTER/web's,
# untracked from the tip at 139c907e6. Emptying a file changes the tip, not the
# history: `git cat-file -p 28bad8208:DEPLOY/rails/brgen/config/master.key` returns
# 32 hex characters today. All seven are burned and cannot be un-burned.
#
# What made them dangerous was pairing: six sat beside the credentials.yml.enc they
# decrypt, and three of those .enc files were still tracked here on 2026-08-12 —
# MASTER/web, amber and bsdports. Verified by decrypting them with the historical
# keys: each held exactly one value, secret_key_base, and nothing else. No API key,
# no database password.
#
# They were removed rather than re-keyed, because nothing read them. Every
# Rails.application.credentials reference in this repo is inside a comment (the
# commented-out aws block in each app's storage.yml). Production takes the value
# from ENV — shared/config/environments/production_baseline.rb sets
# config.secret_key_base from ENV["SECRET_KEY_BASE"], /etc/<app>.env supplies it at
# 640 root:<app>, and each rc.d script hard-requires it
# (`: "${SECRET_KEY_BASE:?missing SECRET_KEY_BASE in /etc/<app>.env}"`), so the
# service refuses to boot without one. MASTER/web never needed a real value at all:
# its rc.d exports SECRET_KEY_BASE_DUMMY=1. A re-key would have produced a new
# secret for a file with no reader.
#
# The live values were confirmed to differ from the exposed ones before any of this
# was called safe — SHA256 of each, compared as digests rather than values: amber
# 9bbeac9f… in git against d14ba067… live, bsdports 6ffd8e80… against c50ceca2…
# So the rotation this debt asked for had already happened in /etc; what was left
# was the dead half still sitting in git.
#
# A tracked credentials.yml.enc is therefore a regression twice over: it is a file
# no code reads, and it re-creates the pair that made a burned key matter.
class TrackedSecretsTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  # Key material, and the encrypted files a leaked key would open.
  FORBIDDEN = [
    %r{(?:\A|/)config/master\.key\z},
    %r{(?:\A|/)config/credentials/[^/]+\.key\z},
    %r{(?:\A|/)credentials(?:\.[a-z_]+)?\.yml\.enc\z},
  ].freeze

  def tracked
    @tracked ||= Dir.chdir(ROOT) { IO.popen(%w[git ls-files -z], &:read) }.split("\0")
  end

  def test_no_key_material_or_encrypted_credentials_is_tracked
    offenders = tracked.select { |path| FORBIDDEN.any? { |re| path.match?(re) } }

    assert_empty offenders,
                 "these are tracked in a public repo:\n  #{offenders.join("\n  ")}\n" \
                 "A master.key is burned the moment it is pushed. An encrypted " \
                 "credentials file beside a burned key is plaintext. Nothing in this " \
                 "repo reads Rails credentials — production takes SECRET_KEY_BASE " \
                 "from /etc/<app>.env — so the fix is deletion, not a re-key."
  end

  # The gate above only sees what is tracked now. This one keeps `git add` from
  # making it tracked in the first place, which is the layer that was missing when
  # MASTER/web/config/master.key was committed.
  def test_gitignore_still_covers_master_key
    ignored = File.read(File.join(ROOT, ".gitignore"))

    assert_includes ignored, "**/config/master.key",
                    ".gitignore lost the pattern that stops a new key being added"
  end

  # Guards the reasoning above, not the files: if something starts reading
  # credentials for real, deleting the .enc files stops being the right answer and
  # this test should fail rather than quietly stay green.
  def test_nothing_reads_rails_credentials_outside_a_comment
    readers = []
    Dir.chdir(ROOT) do
      %w[RAILS MASTER].each do |tree|
        Dir.glob("#{tree}/**/*.{rb,erb,yml}").each do |path|
          next if path.match?(%r{vendor/bundle|node_modules|/builds/|/test/})

          File.foreach(path).with_index(1) do |line, number|
            next unless line.include?("application.credentials")
            next if line.strip.start_with?("#") || line.include?("# ")

            readers << "#{path}:#{number}"
          end
        end
      end
    end

    assert_empty readers,
                 "something now reads Rails credentials:\n  #{readers.join("\n  ")}\n" \
                 "Deleting credentials.yml.enc assumed no reader. Re-key and supply " \
                 "the master.key out of band instead — see TODO.md " \
                 "committed_rails_master_key_public_repo."
  end
end
