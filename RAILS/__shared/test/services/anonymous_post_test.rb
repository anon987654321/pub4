# frozen_string_literal: true

require "minitest/autorun"
require "active_support"
require "active_support/core_ext/digest"
require "active_record"
require "active_record/migration"
require "securerandom"
module Shared
  class AnonymousPostQuota < ActiveRecord::Base
    self.table_name = "anonymous_post_quotas"
    LIMIT = 2
  end
end

require_relative "../../app/services/shared/anonymous_post"

class AnonymousPostTest < Minitest::Test
  def setup
    setup_database
    Shared::AnonymousPostQuota.delete_all
    @guest = GuestUser.new(guest: true)
    @member = GuestUser.new(guest: false)
  end

  def test_guest_allowed_until_limit
    service = build_service(user: @guest, fingerprint: "a" * 64)
    assert service.allowed?
    assert_equal Shared::AnonymousPost::LIMIT, service.remaining
  end

  def test_guest_blocked_after_limit
    Shared::AnonymousPostQuota.create!(fingerprint: "b" * 64, post_count: Shared::AnonymousPost::LIMIT)
    service = build_service(user: @guest, fingerprint: "b" * 64)
    refute service.allowed?
    assert_equal 0, service.remaining
  end

  def test_record_post_increments_quota
    service = build_service(user: @guest, fingerprint: "c" * 64)
    service.record_post!
    quota = Shared::AnonymousPostQuota.find_by!(fingerprint: "c" * 64)
    assert_equal 1, quota.post_count
  end

  def test_member_always_allowed
    service = build_service(user: @member, fingerprint: "d" * 64)
    assert service.allowed?
    assert_nil service.remaining
  end

  private

  def build_service(user:, fingerprint:)
    request = RequestStub.new(fingerprint:)
    Shared::AnonymousPost.new(request:, user:)
  end

  def setup_database
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    return if ActiveRecord::Base.connection.data_source_exists?("anonymous_post_quotas")

    ActiveRecord::Schema.define do
      create_table :anonymous_post_quotas do |t|
        t.string :fingerprint, null: false
        t.integer :post_count, null: false, default: 0
        t.timestamps
      end
      add_index :anonymous_post_quotas, :fingerprint, unique: true
    end
    Shared::AnonymousPostQuota.reset_column_information
  end

  GuestUser = Struct.new(:guest, keyword_init: true)

  class RequestStub
    def initialize(fingerprint:)
      @fingerprint = fingerprint
    end

    def user_agent = "test-agent"
    def headers = { "Accept-Language" => "en" }
    def cookie_jar = CookieJar.new(@fingerprint)
  end

  class CookieJar
    def initialize(fingerprint)
      @fingerprint = fingerprint
    end

    def signed = self
    def [](_key) = @fingerprint
  end
end
