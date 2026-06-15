# VisualizerController - Template for brgen_playlist integration
# This controller serves the audio visualizer interface
# Place in: app/controllers/visualizer_controller.rb

class VisualizerController < ApplicationController
  # Skip authentication for public visualizer access (optional)
  # skip_before_action :authenticate_user!, only: [:index, :playlist]
  
  def index
    # Load cities for carousel (from master.json or database)
    @cities = load_cities
    
    # Load featured tracks or user's playlist
    @tracks = if user_signed_in?
                current_user.playlist_tracks.includes(:track).order(:position)
              else
                Track.featured.limit(20)
              end
    
    # Render with minimal layout for fullscreen experience
    render layout: 'visualizer'
  end
  
  def playlist
    # Dynamic playlist endpoint - returns JSON for visualizer
    tracks = if params[:user_id] && user_signed_in? && current_user.id.to_s == params[:user_id]
               current_user.tracks.order(:position)
             else
               Track.featured.order(:popularity)
             end
    
    render json: tracks.map { |t|
      {
        artist: t.artist,
        title: t.title,
        src: t.audio_url,
        id: t.youtube_id # For YouTube tracks
      }
    }
  end
  
  private
  
  def load_cities
    # Load from database or fallback to hardcoded list
    if defined?(City) && City.respond_to?(:active)
      City.active.pluck(:subdomain, :name)
    else
      # Fallback to static list from index.html
      [
        ['brgen', 'Bergen'],
        ['oshlo', 'Oslo'],
        ['trndheim', 'Trondheim'],
        ['stvanger', 'Stavanger'],
        ['trmso', 'Tromsø'],
        ['longyearbyn', 'Longyearbyen'],
        ['reykjavk', 'Reykjavik'],
        ['kobenhvn', 'Copenhagen'],
        ['stholm', 'Stockholm'],
        ['gtebrg', 'Gothenburg'],
        ['mlmoe', 'Malmö'],
        ['hlsinki', 'Helsinki'],
        ['lndon', 'London'],
        ['cardff', 'Cardiff'],
        ['mnchester', 'Manchester'],
        ['brmingham', 'Birmingham'],
        ['lverpool', 'Liverpool'],
        ['edinbrgh', 'Edinburgh'],
        ['glasgw', 'Glasgow'],
        ['amstrdam', 'Amsterdam'],
        ['rottrdam', 'Rotterdam'],
        ['utrcht', 'Utrecht'],
        ['brssels', 'Brussels'],
        ['zrich', 'Zurich'],
        ['lchtenstein', 'Liechtenstein'],
        ['frankfrt', 'Frankfurt'],
        ['wrsawa', 'Warsaw'],
        ['gdnsk', 'Gdansk'],
        ['brdeaux', 'Bordeaux'],
        ['mrseille', 'Marseille'],
        ['mlan', 'Milan'],
        ['lsbon', 'Lisbon'],
        ['lsangeles', 'Los Angeles'],
        ['newyrk', 'New York'],
        ['chcago', 'Chicago'],
        ['houstn', 'Houston'],
        ['dllas', 'Dallas'],
        ['austn', 'Austin'],
        ['prtland', 'Portland'],
        ['mnneapolis', 'Minneapolis']
      ]
    end
  end
end
