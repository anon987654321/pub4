#!/bin/zsh
# brgen_full_setup_final.zsh
# Full Rails scaffolding generator for Brgen platform

set -e

echo "🚀 Starting full Brgen Rails scaffolding..."

rails plugin new brgen_playlist --mountable --skip-test
rails plugin new brgen_marketplace --mountable --skip-test
rails plugin new brgen_dating --mountable --skip-test
rails plugin new brgen_tv --mountable --skip-test
rails plugin new brgen_takeaway --mountable --skip-test
rails plugin new amber_demo --mountable --skip-test
rails plugin new bsdports --mountable --skip-test

rails generate stimulus live_search
rails generate stimulus lightbox
rails generate stimulus audio_player
rails generate stimulus tv_player

mkdir -p pub4

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

echo "🎉 Full Brgen Rails scaffolding complete!"
