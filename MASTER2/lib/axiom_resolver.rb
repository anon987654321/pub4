# frozen_string_literal: true

require "time"

class AxiomResolver
  DEFAULT_EXT = ".txt"

  def resolve(name, context: {}, at: Time.now)
    guard_name!(name)

    path = Paths.data_file(normalize_name(name, ext: DEFAULT_EXT))
    template = read_file(path)

    timestamp = utc_iso8601(at)
    interpolations = context.merge("timestamp" => timestamp)

    interpolate(template, interpolations)
  end

  private

  def guard_name!(name)
    raise ArgumentError, "name must be provided" if name.nil? || name.to_s.strip.empty?
  end

  def normalize_name(name, ext:)
    filename = name.to_s
    filename.end_with?(ext) ? filename : "#{filename}#{ext}"
  end

  def read_file(path)
    File.read(path)
  rescue Errno::ENOENT => error
    raise ArgumentError, "data file not found: #{path} (#{error.message})"
  end

  def utc_iso8601(time)
    utc_time = time.utc
    utc_time.iso8601
  end

  def interpolate(template, values)
    values.reduce(template) do |result, (key, value)|
      result.gsub("{{#{key}}}", value.to_s)
    end
  end
end