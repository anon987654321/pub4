#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "optparse"
require "tempfile"
require_relative "../gates/support/png_diff"
require_relative "../gates/support/geometry_probe"

# Promote the exact, inspected PNGs from one browser-diagnostics run. This tool
# is deliberately outside the gate registry: ordinary /fix must never approve
# its own visual changes.
module VisualBaselineApproval
  ROOT = File.expand_path("../..", __dir__).freeze
  BASELINE_DIR = File.join(ROOT, "MASTER", "gates", "data", "visual_baselines").freeze
  INVENTORY = "MASTER/gates/data/geometry_surfaces.yml".freeze
  ApprovalError = Class.new(StandardError)

  module_function

  def approve(manifest_path:, selected: [], replace: false, baseline_dir: BASELINE_DIR, surfaces: nil)
    manifest_path = File.expand_path(manifest_path)
    raise ApprovalError, "manifest file must be named manifest.json" unless File.basename(manifest_path) == "manifest.json"

    manifest = JSON.parse(File.read(manifest_path))
    raise ApprovalError, "unsupported manifest schema" unless manifest["schema"] == 1
    raise ApprovalError, "manifest was not produced from the canonical geometry inventory" unless manifest["source_inventory"] == INVENTORY

    capture_dir = File.realpath(File.dirname(manifest_path))
    screenshots_dir = File.realpath(File.join(capture_dir, "screenshots"))
    unless screenshots_dir.start_with?(capture_dir + File::SEPARATOR)
      raise ApprovalError, "screenshots directory resolves outside the capture run"
    end

    rows = Array(manifest["results"])
    ids = rows.map { |row| surface_id(row) }
    raise ApprovalError, "manifest contains duplicate route/viewport rows" unless ids.uniq.length == ids.length

    selected = Array(selected).map(&:to_s).map(&:strip).reject(&:empty?).uniq
    requested_missing = selected - ids
    raise ApprovalError, "requested surface(s) are absent from manifest: #{requested_missing.join(', ')}" unless requested_missing.empty?

    surfaces ||= canonical_surfaces
    by_id = surfaces.to_h { |surface| [surface.id, surface] }
    candidates = selected.empty? ? rows.select do |row|
      surface = by_id[surface_id(row)]
      surface&.pixel_snapshot && row["status"] == "PASS"
    end : selected.map { |id| rows.find { |row| surface_id(row) == id } }

    raise ApprovalError, "no passing pixel_snapshot captures selected" if candidates.empty?

    actions = candidates.map do |row|
      id = surface_id(row)
      surface = by_id[id]
      raise ApprovalError, "#{id} is not a declared pixel_snapshot surface" unless surface&.pixel_snapshot
      raise ApprovalError, "#{id} is not PASS; failed or inconclusive captures cannot be approved" unless row["status"] == "PASS"

      screenshot = File.realpath(row.fetch("screenshot"))
      unless screenshot.start_with?(screenshots_dir + File::SEPARATOR)
        raise ApprovalError, "#{id} screenshot is outside the manifest screenshots directory"
      end
      digest = row.fetch("screenshot_sha256").to_s
      actual_digest = Digest::SHA256.file(screenshot).hexdigest
      raise ApprovalError, "#{id} screenshot SHA-256 does not match its manifest" unless digest.match?(/\A[0-9a-f]{64}\z/) && digest == actual_digest

      image = Deploy::PngDiff.decode(File.binread(screenshot))
      expected_dimensions = [surface.width, surface.height]
      actual_dimensions = [image[:width], image[:height]]
      raise ApprovalError, "#{id} PNG dimensions #{actual_dimensions.join('x')} differ from #{expected_dimensions.join('x')}" unless actual_dimensions == expected_dimensions
      raise ApprovalError, "#{id} manifest dimensions differ from PNG" unless row["dimensions"] == actual_dimensions

      target = File.join(File.expand_path(baseline_dir), "#{safe_slug(surface.app)}-#{safe_slug(surface.label)}-#{safe_slug(surface.viewport)}.png")
      raise ApprovalError, "baseline path is a symlink: #{target}" if File.symlink?(target)
      if File.file?(target) && !replace
        raise ApprovalError, "baseline already exists; review the replacement and pass --replace: #{target}"
      end
      { id:, source: screenshot, target:, bytes: File.binread(screenshot), digest: }
    rescue KeyError => e
      raise ApprovalError, "#{id} manifest is missing #{e.key.inspect}"
    rescue PngDiff::InvalidPng => e
      raise ApprovalError, "#{id} screenshot is not a supported PNG: #{e.message}"
    end

    # Preflight every candidate before creating or replacing any reference.
    target_dir = File.expand_path(baseline_dir)
    parent = File.realpath(File.dirname(target_dir))
    raise ApprovalError, "baseline directory parent must not be a symlink" unless parent == File.expand_path(File.dirname(target_dir))
    raise ApprovalError, "baseline directory must not be a symlink" if File.symlink?(target_dir)
    FileUtils.mkdir_p(target_dir)

    actions.each do |action|
      raise ApprovalError, "baseline path is a symlink: #{action[:target]}" if File.symlink?(action[:target])
      temporary = Tempfile.new([".visual-baseline-", ".png"], target_dir)
      begin
        temporary.binmode
        temporary.write(action[:bytes])
        temporary.flush
        temporary.fsync
        temporary.close
        File.rename(temporary.path, action[:target])
      ensure
        temporary.close! rescue nil
      end
      puts "visual_baseline0: approved #{action[:id]} sha256=#{action[:digest]} -> #{action[:target]}"
    end
    puts "visual_baseline0: #{actions.length} reference(s) written from the reviewed manifest"
    actions.map { |action| action[:target] }
  end

  def canonical_surfaces
    previous = ENV.delete("GATE_SURFACES")
    Deploy::GeometryProbe.surfaces(root: ROOT)
  ensure
    ENV["GATE_SURFACES"] = previous unless previous.nil?
  end

  def surface_id(row)
    [row.fetch("app"), row.fetch("surface"), row.fetch("viewport")].join("/")
  rescue KeyError => e
    raise ApprovalError, "manifest route row is missing #{e.key.inspect}"
  end

  def safe_slug(value)
    value.to_s.gsub(/[^a-zA-Z0-9_-]+/, "_").sub(/\A_+/, "").sub(/_+\z/, "")
  end
  private_class_method :canonical_surfaces, :surface_id, :safe_slug
end

if $PROGRAM_NAME == __FILE__
  options = { manifest: nil, surfaces: [], replace: false }
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby MASTER/tools/approve_visual_baselines.rb --manifest PATH [--surface APP/LABEL/VIEWPORT] [--replace]"
    opts.on("-m", "--manifest PATH", "manifest.json from one reviewed browser-diagnostics run") { |value| options[:manifest] = value }
    opts.on("-s", "--surface APP/LABEL/VIEWPORT", "approve one specific captured surface; repeatable") { |value| options[:surfaces] << value }
    opts.on("--replace", "replace an existing approved PNG after reviewing its diff") { options[:replace] = true }
  end

  begin
    parser.parse!
    raise VisualBaselineApproval::ApprovalError, "--manifest is required" unless options[:manifest]

    VisualBaselineApproval.approve(manifest_path: options[:manifest], selected: options[:surfaces], replace: options[:replace])
  rescue OptionParser::ParseError, VisualBaselineApproval::ApprovalError, JSON::ParserError, SystemCallError, PngDiff::InvalidPng => e
    warn "visual_baseline0: BLOCKED — #{e.class}: #{e.message}"
    exit 1
  end
end
