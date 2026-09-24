# frozen_string_literal: true

# Reads routes_<app>.jsonl (ARGV[0]) and prints each route with its
# parameters filled from real local records, as JSON lines with a concrete
# `url`. A parameter no record can fill is reported, never guessed.
require "json"

def model_for(name, controller)
  base = name == "id" ? controller.split("/").last : name.delete_suffix("_id")
  namespace = controller.split("/")[0..-2].map(&:camelize)
  candidates = []
  namespace.length.downto(0) { |n| candidates << (namespace.first(n) + [base.singularize.camelize]).join("::") }
  candidates.each do |candidate|
    klass = candidate.safe_constantize
    return klass if klass.is_a?(Class) && klass < ActiveRecord::Base
  end
  nil
end

def value_for(name, controller)
  klass = model_for(name, controller)
  return unless klass

  record = ActsAsTenant.respond_to?(:without_tenant) ? ActsAsTenant.without_tenant { klass.strict_loading(false).first } : klass.strict_loading(false).first
  record&.to_param
rescue StandardError
  nil
end

File.foreach(ARGV.fetch(0)) do |line|
  next unless line.start_with?("{")

  route = JSON.parse(line)
  url = route["path"].dup
  missing = []
  route["params"].each do |name|
    value = value_for(name, route["action"].split("#").first)
    value ? url.sub!(":#{name}", value.to_s) : missing << name
  end
  url = url.gsub(/\([^)]*\)/, "")
  puts JSON.generate(route.merge("url" => url, "missing" => missing))
end
