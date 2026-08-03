# frozen_string_literal: true

# Namespace hook for playlist/*. Includes the engine's own PlaylistHelper —
# isolate_namespace does not fold engine helpers into controllers that inherit the
# host ApplicationController, so radio_tunnel_catalog (used by the radio-tunnel
# view) is otherwise undefined at render. See brgen/ENGINES.md.
class Playlist::BaseController < ApplicationController
  helper PlaylistHelper
end
