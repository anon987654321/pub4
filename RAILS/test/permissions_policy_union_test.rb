# frozen_string_literal: true

require "minitest/autorun"

# relayd `set`s Permissions-Policy and overwrites whatever the app sent.
# The nearby outage was this file and that line disagreeing about geolocation.
# Accelerometer/gyroscope are the same shape: MASTER's face and RAILS tilt
# need (self), and a local () here only fools development.
class PermissionsPolicyUnionTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  REPO = File.expand_path("..", ROOT)

  def test_rails_permissions_policy_matches_relayd_sensor_union
    rails = File.read(File.join(ROOT, "shared/config/initializers/security_headers.rb"))
    relayd = File.read(File.join(REPO, "OPENBSD/etc/relayd.conf"))

    rails_header = rails[/Permissions-Policy" => "([^"]+)"/, 1]
    relayd_header = relayd[/Permissions-Policy" value "([^"]+)"/, 1]

    refute_nil rails_header
    refute_nil relayd_header
    assert_includes rails_header, "accelerometer=(self)"
    assert_includes rails_header, "gyroscope=(self)"
    assert_includes rails_header, "geolocation=(self)"
    assert_equal relayd_header, rails_header
  end
end
