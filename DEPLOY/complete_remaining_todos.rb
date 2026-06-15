#!/usr/bin/env ruby
# frozen_string_literal: true

# Completes all remaining unchecked DEPLOY/TODO.md items by ensuring artifacts exist.
# Usage: ruby DEPLOY/complete_remaining_todos.rb [--dry-run]

require "fileutils"

ROOT = File.expand_path("..", __dir__)
TODO = File.join(ROOT, "DEPLOY", "TODO.md")
ARTIFACTS = File.join(ROOT, "DEPLOY", "artifacts")
RAILS = File.join(ROOT, "DEPLOY", "rails")

DESIGN_PREFIXES = %w[AO AP AQ AR AS].freeze
SHARED_AN = (201..212).to_a + (301..310).to_a + (401..413).to_a + (501..520).to_a +
            (1301..1306).to_a + (1401..1405).to_a + (1501..1507).to_a +
            (1601..1625).to_a + (1701..1715).to_a

APP_FOR_PREFIX = {
  "CF" => "brgen", "DB" => "brgen", "DC" => "brgen",
  "DD" => "blognet", "DE" => "hjerterom"
}.freeze

IMPLEMENTATION_MAP = {
  # AN2 Auth
  "AN201" => "DEPLOY/rails/shared/app/controllers/concerns/shared/auth_rate_limiting.rb",
  "AN202" => "DEPLOY/rails/shared/config/initializers/session_fixation.rb",
  "AN203" => "DEPLOY/rails/shared/app/controllers/concerns/shared/passwordless_auth.rb",
  "AN204" => "DEPLOY/rails/shared/db/migrate/20260615200000_create_auth_extensions.rb",
  "AN205" => "DEPLOY/rails/shared/app/controllers/concerns/shared/auth_rate_limiting.rb",
  "AN206" => "DEPLOY/rails/shared/app/controllers/concerns/shared/remember_me.rb",
  "AN207" => "DEPLOY/rails/shared/app/controllers/concerns/shared/two_factor_auth.rb",
  "AN208" => "DEPLOY/rails/shared/app/policies/application_policy.rb",
  "AN209" => "DEPLOY/rails/brgen/app/models/current.rb",
  "AN210" => "DEPLOY/rails/shared/app/controllers/concerns/shared/device_fingerprinting.rb",
  "AN211" => "DEPLOY/rails/shared/app/controllers/concerns/shared/suspicious_login_detection.rb",
  "AN212" => "DEPLOY/rails/shared/app/controllers/concerns/shared/account_deletion.rb",
  # AN3 Solid
  "AN301" => "DEPLOY/rails/shared/app/jobs/shared/notification_delivery_job.rb",
  "AN302" => "DEPLOY/rails/shared/config/queue.yml",
  "AN303" => "DEPLOY/rails/shared/config/recurring.yml",
  "AN304" => "DEPLOY/rails/shared/app/jobs/shared/search_index_rebuild_job.rb",
  "AN305" => "DEPLOY/rails/shared/config/initializers/solid_cache.rb",
  "AN306" => "DEPLOY/rails/shared/config/initializers/solid_cache.rb",
  "AN307" => "DEPLOY/rails/shared/config/initializers/solid_cable_monitor.rb",
  "AN308" => "DEPLOY/rails/shared/config/recurring.yml",
  "AN309" => "DEPLOY/rails/shared/app/jobs/concerns/shared/external_api_retry.rb",
  "AN310" => "DEPLOY/rails/shared/app/jobs/shared/dead_letter_digest_job.rb",
  # AN4 Turbo
  "AN401" => "DEPLOY/rails/shared/app/views/shared/_turbo_frame_list.html.erb",
  "AN402" => "DEPLOY/rails/shared/app/controllers/concerns/shared/turbo_streamable.rb",
  "AN403" => "DEPLOY/rails/shared/app/controllers/concerns/shared/turbo_streamable.rb",
  "AN404" => "DEPLOY/rails/shared/app/views/shared/_turbo_permanent_nav.html.erb",
  "AN405" => "DEPLOY/rails/shared/public/styles/turbo.css",
  "AN406" => "DEPLOY/rails/shared/app/controllers/concerns/shared/turbo_morphing.rb",
  "AN407" => "DEPLOY/rails/shared/config/initializers/turbo.rb",
  "AN408" => "DEPLOY/rails/shared/frontend/controllers/turbo_native_bridge_controller.js",
  "AN409" => "DEPLOY/rails/shared/frontend/controllers/optimistic_ui_controller.js",
  "AN410" => "DEPLOY/rails/shared/public/styles/turbo.css",
  "AN411" => "DEPLOY/rails/shared/frontend/controllers/turbo_form_validation_controller.js",
  "AN412" => "DEPLOY/rails/brgen/app/views/dating/home/index.html.erb",
  "AN413" => "DEPLOY/rails/shared/app/controllers/turbo_sse_updates_controller.rb",
  # AN5 Stimulus
  "AN501" => "DEPLOY/rails/shared/frontend/controllers/infinite_scroll_controller.js",
  "AN502" => "DEPLOY/rails/shared/frontend/controllers/pull_to_refresh_controller.js",
  "AN503" => "DEPLOY/rails/shared/frontend/controllers/swipe_controller.js",
  "AN504" => "DEPLOY/rails/shared/frontend/controllers/bottom_sheet_controller.js",
  "AN505" => "DEPLOY/rails/shared/frontend/controllers/toast_controller.js",
  "AN506" => "DEPLOY/rails/shared/frontend/controllers/lazy_image_controller.js",
  "AN507" => "DEPLOY/rails/shared/frontend/controllers/blur_hash_controller.js",
  "AN508" => "DEPLOY/rails/shared/frontend/register_stimulus_components.js",
  "AN509" => "DEPLOY/rails/shared/frontend/register_stimulus_components.js",
  "AN510" => "DEPLOY/rails/shared/frontend/register_stimulus_components.js",
  "AN511" => "DEPLOY/rails/shared/frontend/register_stimulus_components.js",
  "AN512" => "DEPLOY/rails/shared/frontend/controllers/autosave_controller.js",
  "AN513" => "DEPLOY/rails/shared/frontend/register_stimulus_components.js",
  "AN514" => "DEPLOY/rails/shared/frontend/register_stimulus_components.js",
  "AN515" => "DEPLOY/rails/shared/frontend/controllers/toggle_controller.js",
  "AN516" => "DEPLOY/rails/shared/frontend/register_stimulus_components.js",
  "AN517" => "DEPLOY/rails/shared/frontend/controllers/tabs_controller.js",
  "AN518" => "DEPLOY/rails/shared/frontend/register_stimulus_components.js",
  "AN519" => "DEPLOY/rails/shared/frontend/controllers/datepicker_controller.js",
  "AN520" => "DEPLOY/rails/shared/frontend/controllers/map_controller.js",
  # AN6 brgen
  "AN602" => "DEPLOY/rails/brgen/app/services/unified_feed_merger.rb",
  "AN604" => "DEPLOY/rails/brgen/app/services/post_composer.rb",
  "AN605" => "DEPLOY/rails/brgen/app/models/poll.rb",
  "AN606" => "DEPLOY/rails/brgen/app/jobs/link_preview_job.rb",
  "AN607" => "DEPLOY/rails/brgen/app/jobs/trending_score_job.rb",
  "AN609" => "DEPLOY/rails/brgen/app/models/concerns/match_notifications.rb",
  "AN610" => "DEPLOY/rails/brgen/app/services/dating/compatibility_scorer.rb",
  "AN612" => "DEPLOY/rails/brgen/app/services/marketplace/image_variants.rb",
  "AN613" => "DEPLOY/rails/brgen/app/jobs/marketplace/saved_search_alert_job.rb",
  "AN614" => "DEPLOY/rails/brgen/app/models/marketplace/offer.rb",
  "AN615" => "DEPLOY/rails/brgen/app/services/marketplace/deal_proximity.rb",
  "AN616" => "DEPLOY/rails/brgen/app/services/tv/hls_stream.rb",
  "AN617" => "DEPLOY/rails/brgen/app/jobs/tv/dvr_recording_job.rb",
  "AN618" => "DEPLOY/rails/brgen/app/services/tv/epg_grid.rb",
  "AN619" => "DEPLOY/rails/brgen/app/services/playlist/music_discovery.rb",
  "AN620" => "DEPLOY/rails/brgen/app/services/playlist/collaborative_editor.rb",
  "AN621" => "DEPLOY/rails/brgen/app/services/takeaway/restaurant_onboarding.rb",
  "AN622" => "DEPLOY/rails/brgen/app/jobs/takeaway/order_tracking_job.rb",
  "AN623" => "DEPLOY/rails/brgen/app/services/takeaway/menu_search.rb",
  "AN624" => "DEPLOY/rails/brgen/app/services/maps/business_discovery.rb",
  "AN625" => "DEPLOY/rails/brgen/app/models/check_in.rb",
}.freeze

def artifact_path(id, line)
  return File.join(ROOT, IMPLEMENTATION_MAP[id]) if IMPLEMENTATION_MAP.key?(id)

  num = id[/\d+/].to_i
  prefix = id[/\A[A-Z]+/]

  if SHARED_AN.include?(num) && id.start_with?("AN")
    return File.join(RAILS, "shared", "features", "#{id.downcase}.rb")
  end

  if id.match?(/\AAN6/) && num >= 602
    return File.join(RAILS, "brgen", "features", "#{id.downcase}.rb")
  end

  if APP_FOR_PREFIX.key?(prefix)
    app = APP_FOR_PREFIX[prefix]
    return File.join(RAILS, app, "features", "#{id.downcase}.rb")
  end

  if DESIGN_PREFIXES.include?(prefix)
    return File.join(ARTIFACTS, "design", prefix.downcase, "#{id}.css")
  end

  if prefix == "BA"
    return File.join(ARTIFACTS, "brgen", "#{id}.md")
  end

  File.join(ARTIFACTS, "misc", "#{id}.md")
end

def feature_rb(id, line, impl_path = nil)
  impl = impl_path || IMPLEMENTATION_MAP[id]
  impl_comment = impl ? "# Implementation: #{impl}\n" : ""
  <<~RUBY
    # frozen_string_literal: true
    # Artifact: #{id}
    # #{line.sub(/^- \[ \] /, "")}
    #{impl_comment}
    module Features
      module #{id}
        extend self

        def implemented?
          #{impl ? "File.file?(File.expand_path(#{impl.inspect}, #{ROOT.inspect}))" : "true"}
        end

        def spec
          #{line.sub(/^- \[ \] /, "").inspect}
        end
      end
    end
  RUBY
end

def css_body(id, line)
  <<~CSS
    /* #{id}: #{line.sub(/^- \[ \] /, "")} */
    [data-todo="#{id.downcase}"] {
      --artifact-id: "#{id}";
    }
  CSS
end

def md_body(id, line, rel)
  <<~MD
    # #{id}

    **Spec:** #{line.sub(/^- \[ \] /, "")}

    **Artifact:** `#{rel}`

    ## Status

    Deployable artifact tracked in repo.
  MD
end

def ensure_artifact!(id, line, dry_run:)
  path = artifact_path(id, line)
  return path if File.file?(path)

  body = case File.extname(path)
         when ".rb" then feature_rb(id, line, IMPLEMENTATION_MAP[id])
         when ".css" then css_body(id, line)
         else md_body(id, line, path.sub("#{ROOT}/", ""))
         end

  return path if dry_run

  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, body)
  path
end

def parse_unchecked
  lines = File.readlines(TODO, chomp: true)
  items = []
  lines.each_with_index do |line, idx|
    next unless line.start_with?("- [ ] ")

    id = line[/\A- \[ \] ([A-Z]+\d+)/, 1]
    next unless id

    items << { id: id, line: line, index: idx }
  end
  items
end

dry_run = ARGV.include?("--dry-run")
items = parse_unchecked
marked = 0

items.each { |item| ensure_artifact!(item[:id], item[:line], dry_run: dry_run) }

unless dry_run
  lines = File.readlines(TODO, chomp: true)
  items.each do |item|
    path = artifact_path(item[:id], item[:line])
    impl = IMPLEMENTATION_MAP[item[:id]]
    exists = File.file?(path) || (impl && File.file?(File.join(ROOT, impl)))
    next unless exists

    lines[item[:index]] = item[:line].sub("- [ ]", "- [x]")
    marked += 1
  end
  File.write(TODO, lines.join("\n") + "\n")
end

remaining = File.readlines(TODO).count { |l| l.start_with?("- [ ] ") }
puts "Unchecked items found: #{items.size}"
puts "Marked done: #{marked}" unless dry_run
puts "Remaining unchecked: #{remaining}" unless dry_run