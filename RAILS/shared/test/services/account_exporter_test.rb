# frozen_string_literal: true

require "minitest/autorun"
require "csv"
require_relative "../../app/services/shared/account_exporter"

# The controller called this class for a year before anyone wrote it, so /account/export answered 500 fleet-wide.
class SharedAccountExporterTest < Minitest::Test
  Reflection = Struct.new(:name, :macro, :options)

  class Record
    attr_reader :attributes

    def initialize(attributes) = @attributes = attributes
  end

  class Owner < Record
    def self.reflections = @reflections ||= []
    def self.reflect_on_all_associations = reflections

    def initialize(attributes, associations = {})
      super(attributes)
      @associations = associations
    end

    def public_send(name) = @associations.key?(name) ? @associations[name] : super
  end

  def setup
    Owner.reflections.clear
  end

  def test_redacts_credentials_but_keeps_the_rest
    secrets = { "password_digest" => "x", "otp_secret" => "y", "remember_token" => "z" }
    rows = export(Owner.new({ "id" => 7, "email_address" => "a@b.no" }.merge(secrets)))

    assert_equal [ "7" ], values_for(rows, "account", "id")
    assert_equal [ "a@b.no" ], values_for(rows, "account", "email_address")
    assert_empty rows.select { |row| %w[password_digest otp_secret remember_token].include?(row["field"]) }
  end

  def test_exports_owned_associations_and_numbers_their_records
    Owner.reflections << Reflection.new(:posts, :has_many, {})
    owner = Owner.new({ "id" => 1 }, posts: [ Record.new("title" => "first"), Record.new("title" => "second") ])

    rows = export(owner)

    assert_equal %w[first second], values_for(rows, "posts", "title")
    assert_equal %w[0 1], rows.select { |row| row["section"] == "posts" }.map { |row| row["record"] }
  end

  # An association reachable only through another one would be exported twice.
  def test_skips_through_associations
    Owner.reflections << Reflection.new(:followers, :has_many, { through: :follows })
    rows = export(Owner.new({ "id" => 1 }, followers: [ Record.new("id" => 2) ]))

    assert_empty rows.select { |row| row["section"] == "followers" }
  end

  def test_records_a_failing_association_instead_of_losing_the_export
    Owner.reflections << Reflection.new(:broken, :has_many, {})
    owner = Owner.new({ "id" => 1 }, broken: Object.new)

    rows = export(owner)

    assert_equal [ "1" ], values_for(rows, "account", "id")
    assert_equal 1, rows.count { |row| row["field"] == "export_error" }
  end

  private

  def export(owner) = CSV.parse(Shared::AccountExporter.new(owner).to_csv, headers: true).map(&:to_h)

  def values_for(rows, section, field)
    rows.select { |row| row["section"] == section && row["field"] == field }.map { |row| row["value"] }
  end
end
