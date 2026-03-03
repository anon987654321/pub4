# frozen_string_literal: true

module AutoInstall
  ASSOCIATION_INCLUDES = [:association].freeze

  Result = Struct.new(:installed, :skipped, :errors, keyword_init: true)

  def self.call(scope)
    return Result.new(installed: [], skipped: [], errors: []) if scope.blank?

    installed = []
    skipped = []
    errors = []

    scope.includes(*ASSOCIATION_INCLUDES).find_each do |record|
      if record.respond_to?(:installed?) && record.installed?
        skipped << record
        next
      end

      begin
        record.install!
        installed << record
      rescue StandardError => e
        errors << { record: record, error: e }
      end
    end

    Result.new(installed: installed, skipped: skipped, errors: errors)
  end
end