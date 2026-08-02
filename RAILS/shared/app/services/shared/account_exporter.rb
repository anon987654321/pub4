# frozen_string_literal: true

require "csv"

module Shared
  # GDPR article 15 export. AccountSettingsController#export named this class from AN212 on; nobody wrote it.
  class AccountExporter
    HEADERS = %w[section record field value].freeze
    SECRET_COLUMNS = %w[password_digest otp_secret].freeze
    SECRET_SUFFIXES = %w[_token _digest _secret].freeze

    def self.call(user) = new(user).to_csv

    def initialize(user)
      @user = user
    end

    # Flat, not nested: the subject opens this in a spreadsheet.
    def to_csv
      CSV.generate do |csv|
        csv << HEADERS
        attribute_rows(@user).each { |field, value| csv << [ "account", 0, field, value ] }
        owned_associations.each { |reflection| append_association(csv, reflection) }
      end
    end

    private

    # brgen, amber and bsdports share almost no associations, so ownership is read off the model rather than listed.
    def owned_associations
      @user.class.reflect_on_all_associations
           .select { |reflection| %i[has_one has_many].include?(reflection.macro) }
           .reject { |reflection| reflection.options[:through] }
           .sort_by(&:name)
    end

    # One unreadable association must not cost the subject the rest of their data, and must not pass as complete.
    def append_association(csv, reflection)
      records(reflection).each_with_index do |record, index|
        attribute_rows(record).each { |field, value| csv << [ reflection.name, index, field, value ] }
      end
    rescue StandardError => e
      csv << [ reflection.name, 0, "export_error", "#{e.class}: #{e.message}" ]
    end

    def records(reflection)
      value = @user.public_send(reflection.name)
      reflection.macro == :has_one ? Array(value) : value.to_a
    end

    def attribute_rows(record)
      return [] if record.nil?

      record.attributes.reject { |name, _| secret?(name) }.sort.map { |name, value| [ name, format_value(value) ] }
    end

    # An access request entitles the subject to their data, not to credentials that re-authenticate as them.
    def secret?(name)
      SECRET_COLUMNS.include?(name) || SECRET_SUFFIXES.any? { |suffix| name.end_with?(suffix) }
    end

    def format_value(value)
      case value
      when nil then ""
      when Time, DateTime then value.iso8601
      when Date then value.to_s
      when Hash, Array then value.to_json
      else value.to_s
      end
    end
  end
end
