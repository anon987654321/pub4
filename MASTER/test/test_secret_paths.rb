# frozen_string_literal: true

require_relative "test_helper"

# The read guard is name-based, so it holds for a file the agent has not read
# yet. That makes both halves of it load-bearing: every name below that must be
# refused, and every name that must stay readable. The readable half is where
# this pattern was wrong before — `private` refused private_notes_test.rb and a
# bare `keys?` let api_keys.txt through — so it is pinned as firmly as the rest.
class TestSecretPaths < Minitest::Test
  REFUSED = %w[
    .env .env.local .envrc master.env production.env
    credentials.json secrets.yml token.txt api_key.txt private_key
    id_ed25519 id_rsa .netrc .pgpass .npmrc server.pem
    .master/config.yml MASTER/.master/config.yml
  ].freeze

  READABLE = %w[
    config.yml environment.rb keyboard.js tokenizer.rb private_notes_test.rb
    README.md dilla.rb app/config/database.yml .master/mode
  ].freeze

  def guard(path) = Master::Io::PathGuard.secret?(path)

  def test_refuses_every_credential_shape
    leaked = REFUSED.reject { |path| guard(path) }
    assert_empty leaked, "readable but should be refused"
  end

  def test_keeps_ordinary_files_readable
    blocked = READABLE.select { |path| guard(path) }
    assert_empty blocked, "refused but should be readable"
  end

  # .master/config.yml holds web_token, and its basename is as generic as a
  # filename gets. Only its place in the tree identifies it.
  def test_the_web_token_file_is_refused_by_path_not_name
    assert guard(".master/config.yml")
    refute guard("config.yml")
  end
end
