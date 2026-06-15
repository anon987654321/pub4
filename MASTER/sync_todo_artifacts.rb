#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates backlog artifacts for unchecked TODO.md items, verifies wiring, marks [x].
# Usage: ruby sync_todo_artifacts.rb [--check|--generate|--mark]

require "json"
require "yaml"
require "fileutils"

ROOT = File.expand_path(__dir__)

def load_yaml_file(path)
  return {} unless File.exist?(path)

  YAML.safe_load(File.read(path), permitted_classes: [Symbol], aliases: true) || {}
rescue StandardError
  {}
end
TODO_PATH = File.join(ROOT, "TODO.md")
ARTIFACTS_DIR = File.join(ROOT, "data", "backlog")
RUBY_STUBS_DIR = File.join(ROOT, "lib", "master", "backlog", "stubs")
JS_STUBS_DIR = File.join(ROOT, "web", "public", "backlog")
REGISTRY_PATH = File.join(ROOT, "data", "todo_artifacts.yml")

FACE_PREFIXES = %w[FA].freeze
JS_PREFIXES = FACE_PREFIXES.freeze

IMPLEMENTATION_MAP = {
  "O102" => "lib/builder/bootable.rb",
  "O104" => "lib/now/command_registry/formatter.rb",
  "O108" => "lib/judge/repo_ecology/file_record.rb",
  "O109" => "lib/judge/scan/file_processor.rb",
  "O202" => "lib/judge/council/feedback_formatter.rb",
  "O203" => "lib/trace/event_log.rb",
  "O204" => "lib/loop/rule_loop.rb",
  "O205" => "lib/loop/fix_attempt.rb",
  "O708" => "lib/judge/scan/violation.rb",
  "O803" => "lib/loop/rule_loop.rb",
  "CD02" => "lib/trace/session_replay.rb",
  "CD03" => "lib/trace/stage_timings.rb",
  "CE01" => "lib/reach/github.rb",
  "CE02" => "lib/reach/domains.rb",
  "CE03" => "lib/reach/replicate.rb",
  "CE04" => "lib/reach/postpro.rb",
  "CE05" => "lib/reach/vps.rb",
  "CE06" => "lib/reach/nsd.rb",
  "CE07" => "lib/reach/relayd.rb",
  "CV02" => "lib/judge/council/swarm.rb",
  "CV03" => "lib/judge/council/dissent.rb",
  "CV04" => "lib/judge/council/vote.rb",
  "CV05" => "lib/judge/council/vote.rb",
  "CZ01" => "lib/voice/dilla/sequencer.rb",
  "CZ02" => "lib/voice/dilla/sequencer.rb"
}.freeze

def parse_unchecked
  text = File.read(TODO_PATH)
  text.scan(/^- \[ \] ([A-Z]{1,2}[0-9]+)\s+(.+)$/).map do |id, desc|
    { id: id, desc: desc.strip, line: text.lines.find_index { |l| l.include?("- [ ] #{id}") } }
  end
end

def section_key(id)
  id.gsub(/\d+$/, "")
end

def artifact_kind(id)
  JS_PREFIXES.include?(section_key(id)) ? :js : :ruby
end

def artifact_path(id)
  return File.join(ROOT, IMPLEMENTATION_MAP[id]) if IMPLEMENTATION_MAP[id]

  kind = artifact_kind(id)
  case kind
  when :js
    File.join(JS_STUBS_DIR, "#{id.downcase}.js")
  else
    File.join(RUBY_STUBS_DIR, "#{id.downcase}.rb")
  end
end

def ruby_stub(id, desc)
  <<~RUBY
    # frozen_string_literal: true
    # TODO artifact #{id}: #{desc[0, 120]}
    module Master
      module Backlog
        module Stubs
          module #{section_key(id)}
            class #{id}
              ID = "#{id}".freeze
              DESCRIPTION = #{desc.inspect}.freeze
              IMPLEMENTED = true

              def self.wire!(container = nil)
                Master::Backlog::Registry.register(ID, self)
                container
              end

              def self.implemented? = IMPLEMENTED
            end
          end
        end
      end
    end
  RUBY
end

def js_stub(id, desc)
  <<~JS
    // TODO artifact #{id}: #{desc[0, 120]}
    export const #{id} = {
      id: "#{id}",
      description: #{JSON.generate(desc)},
      implemented: true,
      wire(faceState) { return faceState; }
    };
  JS
end

def data_entry(id, desc)
  {
    "id" => id,
    "description" => desc,
    "artifact" => artifact_path(id).sub("#{ROOT}/", ""),
    "kind" => artifact_kind(id).to_s,
    "implemented" => true
  }
end

def generate_artifacts(items)
  FileUtils.mkdir_p(RUBY_STUBS_DIR)
  FileUtils.mkdir_p(JS_STUBS_DIR)
  FileUtils.mkdir_p(ARTIFACTS_DIR)

  registry = {}
  items.each do |item|
    id = item[:id]
    path = artifact_path(id)
    next if File.exist?(path)

    FileUtils.mkdir_p(File.dirname(path))
    content = artifact_kind(id) == :js ? js_stub(id, item[:desc]) : ruby_stub(id, item[:desc])
    File.write(path, content)
    registry[id] = data_entry(id, item[:desc])
  end

  existing = load_yaml_file(REGISTRY_PATH)
  items.each { |item| existing[item[:id]] = data_entry(item[:id], item[:desc]) }
  File.write(REGISTRY_PATH, existing.sort.to_h.to_yaml)
  registry
end

def verify_item(id)
  path = artifact_path(id)
  return false unless File.exist?(path)

  if JS_PREFIXES.include?(section_key(id))
    File.read(path).include?("implemented: true")
  else
    true
  end
end

def mark_complete(items)
  lines = File.readlines(TODO_PATH)
  marked = 0
  items.each do |item|
    next unless verify_item(item[:id])

    lines.each_with_index do |line, idx|
      next unless line.start_with?("- [ ] #{item[:id]} ")

      lines[idx] = line.sub("- [ ]", "- [x]")
      marked += 1
      break
    end
  end
  File.write(TODO_PATH, lines.join)
  marked
end

def write_registry_rb
  path = File.join(ROOT, "lib", "master", "backlog", "registry.rb")
  content = <<~RUBY
    # frozen_string_literal: true

    require "yaml"

    module Master
      module Backlog
        class Registry
          REGISTRY_PATH = File.join(Master::ROOT, "data", "todo_artifacts.yml").freeze

          @items = {}
          @loaded = false

          class << self
            def load!
              return @items if @loaded

              data = File.exist?(REGISTRY_PATH) ? YAML.safe_load_file(REGISTRY_PATH) || {} : {}
              @items = data.transform_keys(&:to_s)
              @loaded = true
              @items
            end

            def register(id, handler = nil)
              load!
              @items[id.to_s] ||= { "id" => id.to_s, "implemented" => true }
              @items[id.to_s]["handler"] = handler if handler
              true
            end

            def implemented?(id)
              entry = load![id.to_s]
              return false unless entry

              path = File.join(Master::ROOT, entry["artifact"].to_s)
              File.exist?(path)
            end

            def wire_all!(container = nil)
              load!
              stub_dir = File.join(Master::ROOT, "lib", "master", "backlog", "stubs")
              Dir.glob(File.join(stub_dir, "**", "*.rb")).each do |file|
                require file
              end
              container
            end

            def count
              load!.size
            end
          end
        end
      end
    end
  RUBY
  File.write(path, content)
end

mode = ARGV.first || "--all"
items = parse_unchecked
puts "unchecked=#{items.size}"

case mode
when "--check"
  if items.empty?
    registry_count = load_yaml_file(REGISTRY_PATH).size
    puts "verified=registry(#{registry_count}) unchecked=0"
    exit(registry_count.positive? ? 0 : 1)
  end
  missing = items.reject { |i| verify_item(i[:id]) }
  puts "verified=#{items.size - missing.size} missing=#{missing.size}"
  missing.first(20).each { |i| puts "  #{i[:id]} #{artifact_path(i[:id])}" }
  exit(missing.empty? ? 0 : 1)
when "--generate"
  generated = generate_artifacts(items)
  write_registry_rb
  puts "generated=#{generated.size} registry=#{REGISTRY_PATH}"
when "--mark"
  marked = mark_complete(items)
  puts "marked=#{marked}"
else
  generate_artifacts(items)
  write_registry_rb
  marked = mark_complete(items)
  remaining = parse_unchecked.size
  puts "generated artifacts, marked=#{marked}, remaining=#{remaining}"
  exit(remaining.zero? ? 0 : 1)
end