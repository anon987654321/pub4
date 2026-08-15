# frozen_string_literal: true

require "minitest/autorun"
require_relative "../brgen/app/lib/fediverse/client"

class FediverseSsrfTest < Minitest::Test
  def test_loopback_https_is_refused
    refute Fediverse::Client.public_https?(URI("https://127.0.0.1/actor"))
  end

  def test_link_local_metadata_is_refused
    refute Fediverse::Client.public_https?(URI("https://169.254.169.254/latest/meta-data"))
  end

  def test_non_443_is_refused
    refute Fediverse::Client.public_https?(URI("https://example.com:8443/actor"))
  end
end
