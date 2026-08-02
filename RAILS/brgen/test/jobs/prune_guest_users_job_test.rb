# frozen_string_literal: true

require 'test_helper'

# The job existed, was correct, and was enqueued by nothing — so every cookieless
# request's guest row lived forever (102,778 of them on 2026-08-01, 99.3% of the
# users table). These tests pin the three things that have to hold together: the
# job removes the right rows, the schedule exists, and the index its scan needs
# is in the schema.
class PruneGuestUsersJobTest < ActiveSupport::TestCase
  ROOT = File.expand_path('../../..', __dir__)

  def build_guest(created_at:)
    user = User.new(email_address: "guest_#{SecureRandom.hex(6)}@guest.local", guest: true)
    user.password_digest = BCrypt::Password.create('x', cost: BCrypt::Engine::MIN_COST)
    user.save!
    user.update_column(:created_at, created_at)
    user
  end

  test 'destroys stale sessionless guests and keeps everything else' do
    stale = build_guest(created_at: 30.days.ago)
    recent = build_guest(created_at: 1.hour.ago)
    signed_in = build_guest(created_at: 30.days.ago)
    signed_in.sessions.create!(user_agent: 'test', ip_address: '127.0.0.1')
    real = User.create!(email_address: "real_#{SecureRandom.hex(6)}@example.com", password: 'secret123',
                        guest: false)
    real.update_column(:created_at, 30.days.ago)

    Shared::PruneGuestUsersJob.perform_now

    refute User.exists?(stale.id), 'stale sessionless guest should be pruned'
    assert User.exists?(recent.id), 'a guest younger than the window is still in use'
    assert User.exists?(signed_in.id), 'a guest with a session is an active visitor'
    assert User.exists?(real.id), 'real accounts are never guest rows'
  end

  test 'is scheduled in production' do
    schedule = YAML.safe_load_file(File.join(ROOT, 'brgen/config/recurring.yml')).fetch('production')
    entry = schedule.fetch('prune_guest_users')

    assert_equal 'Shared::PruneGuestUsersJob', entry.fetch('class')
    assert_match(/every day/, entry.fetch('schedule'))
  end

  # A daily full scan of the largest table on a 1-vCPU box is the reason the
  # index and the schedule landed in the same change.
  test 'the scan the job performs is indexed' do
    assert_includes File.read(File.join(ROOT, 'brgen/db/schema.rb')),
                    'index_users_on_guest_and_created_at'
  end
end
