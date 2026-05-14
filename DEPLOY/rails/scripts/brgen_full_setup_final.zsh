#!/bin/zsh
# brgen_full_setup_final.zsh
# Full Rails scaffolding generator for Brgen platform.
# Run from the root of a Rails 8 app.

set -euo pipefail

log() { print -P "%F{cyan}==>%f $*"; }
skip_if_exists() { [[ -e "$1" ]]; }
run_if_missing() {
  local target=$1
  shift
  if skip_if_exists "$target"; then
    log "skip $target"
  else
    "$@"
  fi
}

log "Starting full Brgen Rails scaffolding"

# Gems used by the generated platform. Keep this idempotent.
if [[ -f Gemfile ]]; then
  grep -q 'gem "view_component"' Gemfile || print 'gem "view_component"' >> Gemfile
  grep -q 'gem "ransack"' Gemfile || print 'gem "ransack"' >> Gemfile
  grep -q 'gem "stimulus_reflex"' Gemfile || print 'gem "stimulus_reflex"' >> Gemfile
end

# Mountable engines for bounded contexts. These are skipped if already present.
run_if_missing brgen_playlist rails plugin new brgen_playlist --mountable --skip-test
run_if_missing brgen_marketplace rails plugin new brgen_marketplace --mountable --skip-test
run_if_missing brgen_dating rails plugin new brgen_dating --mountable --skip-test
run_if_missing brgen_tv rails plugin new brgen_tv --mountable --skip-test
run_if_missing brgen_takeaway rails plugin new brgen_takeaway --mountable --skip-test
run_if_missing amber_demo rails plugin new amber_demo --mountable --skip-test
run_if_missing bsdports rails plugin new bsdports --mountable --skip-test

# Core models.
run_if_missing app/models/brgen/event.rb rails generate model Brgen::Event actor:references action:string object_type:string object_id:integer locality:string visibility:string moderation_state:string source_vertical:string metadata:json
run_if_missing app/models/brgen/report.rb rails generate model Brgen::Report reporter:references reportable:references{polymorphic} reason:string status:string reviewed_at:datetime

# Marketplace / MyDeal-style commerce.
run_if_missing app/models/marketplace/vendor.rb rails generate model Marketplace::Vendor name:string email:string status:string rating:decimal verified:boolean
run_if_missing app/models/marketplace/category.rb rails generate model Marketplace::Category name:string slug:string parent:references
run_if_missing app/models/marketplace/listing.rb rails generate model Marketplace::Listing title:string description:text price_cents:integer original_price_cents:integer status:string vendor:references category:references featured:boolean deal:boolean ends_at:datetime
run_if_missing app/models/marketplace/order.rb rails generate model Marketplace::Order listing:references buyer:references quantity:integer status:string notes:text
run_if_missing app/models/marketplace/order_item.rb rails generate model Marketplace::OrderItem order:references listing:references quantity:integer price_cents:integer

# Brgen Playlist.
run_if_missing app/models/brgen_playlist/set.rb rails generate model BrgenPlaylist::Set title:string description:text visibility:string owner:references
run_if_missing app/models/brgen_playlist/track.rb rails generate model BrgenPlaylist::Track title:string artist:string set:references duration_seconds:integer source_url:string
run_if_missing app/models/brgen_playlist/collaboration.rb rails generate model BrgenPlaylist::Collaboration set:references user:references role:string
run_if_missing app/models/brgen_playlist/like.rb rails generate model BrgenPlaylist::Like track:references user:references

# Dating.
run_if_missing app/models/dating/profile.rb rails generate model Dating::Profile display_name:string age:integer gender:string bio:text user:references visibility:string
run_if_missing app/models/dating/like.rb rails generate model Dating::Like profile:references user:references
run_if_missing app/models/dating/match.rb rails generate model Dating::Match profile_a:references profile_b:references status:string
run_if_missing app/models/dating/safety_report.rb rails generate model Dating::SafetyReport profile:references reporter:references status:string reason:text

# TV.
run_if_missing app/models/tv/channel.rb rails generate model Tv::Channel name:string description:text owner:references
run_if_missing app/models/tv/video.rb rails generate model Tv::Video title:string description:text channel:references duration_seconds:integer status:string
run_if_missing app/models/tv/broadcast.rb rails generate model Tv::Broadcast channel:references video:references starts_at:datetime status:string

# Takeaway.
run_if_missing app/models/takeaway/restaurant.rb rails generate model Takeaway::Restaurant name:string address:string cuisine:string delivery_area:string status:string
run_if_missing app/models/takeaway/menu_item.rb rails generate model Takeaway::MenuItem name:string description:text price_cents:integer restaurant:references available:boolean
run_if_missing app/models/takeaway/order.rb rails generate model Takeaway::Order restaurant:references customer:references status:string total_cents:integer notes:text

# Controllers.
rails generate controller Brgen::Feed index 2>/dev/null || true
rails generate controller Brgen::Search index 2>/dev/null || true
rails generate controller Brgen::Moderation index review 2>/dev/null || true
rails generate controller Marketplace::Listings index show new create 2>/dev/null || true
rails generate controller Marketplace::Orders create 2>/dev/null || true
rails generate controller Marketplace::Vendors index show 2>/dev/null || true
rails generate controller BrgenPlaylist::Playlists index show new create 2>/dev/null || true
rails generate controller BrgenPlaylist::Tracks create 2>/dev/null || true
rails generate controller Dating::Profiles index show new create 2>/dev/null || true
rails generate controller Dating::Matches create 2>/dev/null || true
rails generate controller Tv::Channels index show new create 2>/dev/null || true
rails generate controller Tv::Videos index show new create 2>/dev/null || true
rails generate controller Takeaway::Restaurants index show new create 2>/dev/null || true
rails generate controller Takeaway::MenuItems create 2>/dev/null || true
rails generate controller Amber::Examples index 2>/dev/null || true
rails generate controller Bsdports::Ports index show 2>/dev/null || true
rails generate controller Bsdports::Categories index show 2>/dev/null || true

# View components when the generator is available.
rails generate component ListingCard title:string image:string 2>/dev/null || true
rails generate component BrgenPlaylistCard title:string track_count:integer 2>/dev/null || true
rails generate component BrgenTrackCard title:string artist:string audio_file:string 2>/dev/null || true
rails generate component ProfileCard display_name:string age:integer bio:string 2>/dev/null || true
rails generate component ChannelCard name:string description:string 2>/dev/null || true
rails generate component VideoCard title:string video_file:string 2>/dev/null || true
rails generate component RestaurantCard name:string address:string 2>/dev/null || true
rails generate component MenuItemCard name:string description:string price_cents:integer 2>/dev/null || true

# Stimulus controllers.
rails generate stimulus live_search 2>/dev/null || true
rails generate stimulus lightbox 2>/dev/null || true
rails generate stimulus audio_player 2>/dev/null || true
rails generate stimulus tv_player 2>/dev/null || true

mkdir -p app/views/shared app/javascript/controllers pub4

cat > app/views/shared/_gallery.html.erb <<'EOF'
<div data-controller="lightbox">
  <% items.each do |item| %>
    <a href="<%= url_for(item) %>" data-lightbox="gallery">
      <%= image_tag item.variant(resize_to_limit: [300, 200]) %>
    </a>
  <% end %>
</div>
EOF

cat > app/javascript/controllers/live_search_controller.js <<'EOF'
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results"]
  static values = { url: String }

  connect() {
    this.timeout = null
  }

  search() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.perform(), 200)
  }

  perform() {
    const query = this.inputTarget.value
    fetch(`${this.urlValue}?q=${encodeURIComponent(query)}`, {
      headers: { Accept: "text/vnd.turbo-stream.html" }
    })
      .then((response) => response.text())
      .then((html) => { this.resultsTarget.innerHTML = html })
  }
}
EOF

cat > app/javascript/controllers/lightbox_controller.js <<'EOF'
import { Controller } from "@hotwired/stimulus"
import lightGallery from "lightgallery"

export default class extends Controller {
  connect() {
    this.gallery = lightGallery(this.element, { selector: "a[data-lightbox]" })
  }

  disconnect() {
    if (this.gallery) this.gallery.destroy()
  }
}
EOF

cat > app/javascript/controllers/audio_player_controller.js <<'EOF'
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["audio"]

  play() { this.audioTarget.play() }
  pause() { this.audioTarget.pause() }
}
EOF

cat > app/javascript/controllers/tv_player_controller.js <<'EOF'
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["video"]

  play() { this.videoTarget.play() }
  pause() { this.videoTarget.pause() }
}
EOF

cat > pub4/index.html <<'EOF'
<h1>Radio Bergen Playlist Demo</h1>
<div data-controller="audio-player">
  <% @tracks.each do |track| %>
    <div class="demo-track-card">
      <h3><%= track.title %> — <%= track.artist %></h3>
      <audio data-audio-player-target="audio" src="<%= url_for(track.audio_file) %>" controls></audio>
    </div>
  <% end %>
</div>
EOF

log "Full Brgen Rails scaffolding complete"
