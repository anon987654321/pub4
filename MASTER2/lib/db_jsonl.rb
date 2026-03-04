# frozen_string_literal: true

%w[json time fileutils].each { |library_name| require library_name }

class DbJsonl
  def initialize(model_class:, association_names: [])
    @model_class = model_class
    @association_names = Array(association_names)
  end

  def export(name:, scope: nil)
    export_scope = build_scope(scope)
    jsonl_path = data_path(name)

    FileUtils.mkdir_p(File.dirname(jsonl_path))
    File.open(jsonl_path, "w") do |file|
      export_scope.find_each do |record|
        file.puts(JSON.generate(serialize_record(record)))
      end
    end

    jsonl_path
  end

  def import(name:, upsert: false, unique_by: nil)
    jsonl_path = data_path(name)
    return 0 unless File.exist?(jsonl_path)

    imported_count = 0
    File.foreach(jsonl_path) do |line|
      next if line.strip.empty?

      attributes = parse_json_line(line)
      next unless attributes

      imported_count += 1 if persist_record(attributes, upsert:, unique_by:)
    end

    imported_count
  end

  private

  attr_reader :model_class, :association_names

  def build_scope(scope)
    base_scope = scope || model_class.all
    return base_scope if association_names.empty?

    base_scope.includes(*association_names)
  end

  def data_path(name)
    Paths.data_file("#{name}.jsonl")
  end

  def parse_json_line(line)
    JSON.parse(line, symbolize_names: true)
  rescue JSON::ParserError
    nil
  end

  def persist_record(attributes, upsert:, unique_by:)
    return create_record(attributes) unless upsert

    upsert_record(attributes, unique_by)
  end

  def create_record(attributes)
    model_class.create(attributes).persisted?
  end

  def upsert_record(attributes, unique_by)
    unique_key = unique_by || model_class.primary_key&.to_sym
    return create_record(attributes) unless unique_key

    unique_value = attributes.fetch(unique_key, nil)
    return create_record(attributes) unless unique_value

    record = model_class.find_or_initialize_by(unique_key => unique_value)
    record.assign_attributes(attributes)
    record.save
  end

  def serialize_record(record)
    {
      model: model_class.name,
      exported_at: timestamp_iso8601,
      attributes: record.attributes
    }
  end

  def timestamp_iso8601
    Time.current.utc.iso8601
  end
end