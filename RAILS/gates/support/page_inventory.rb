# frozen_string_literal: true

require "json"
require "yaml"

module Deploy
  # Canonical inventory of full-page Rails surfaces for UI/UX simulation.
  # Discovers non-partial HTML views under brgen, amber, and MASTER web, then
  # maps each to a host + path + guest/auth persona.
  module PageInventory
    ROOT = File.expand_path("../../..", __dir__)
    APEX = "brgen.no"
    VERTICAL_HOSTS = {
      "dating" => "dating.#{APEX}",
      "marketplace" => "markedsplass.#{APEX}",
      "playlist" => "spilleliste.#{APEX}",
      "tv" => "tv.#{APEX}",
      "takeaway" => "takeaway.#{APEX}",
      "maps" => "maps.#{APEX}",
    }.freeze

    # Vertical root view → path "/"
    VERTICAL_ROOTS = {
      %w[marketplace listings index] => true,
      %w[dating home index] => true,
      %w[tv home index] => true,
      %w[maps home index] => true,
      %w[playlist playlists index] => true,
      %w[takeaway restaurants index] => true,
    }.freeze

    APPS = {
      "brgen" => {
        views: File.join(ROOT, "RAILS", "brgen", "app", "views"),
        port_key: "brgen",
      },
      "amber" => {
        views: File.join(ROOT, "RAILS", "amber", "app", "views"),
        port_key: "amber",
      },
      "bsdports" => {
        views: File.join(ROOT, "RAILS", "bsdports", "app", "views"),
        port_key: "bsdports",
      },
      "master" => {
        views: nil, # special-cased
        port_key: "master",
      },
    }.freeze

    SHARED_ROOT = File.join(ROOT, "RAILS", "shared", "app", "views")

    # Pages the engine renders inside every host app. Their routes come from
    # shared/config/routes/{auth,social}.rb, so no filename convention yields them.
    # uncovered_shared_views fails the simulation when a new one lands without a row.
    SHARED_PAGES = {
      %w[account_settings show] => { path: "/account", persona: "auth" },
      %w[two_factor_setups show] => { path: "/two_factor_setup", persona: "auth" },
      %w[passwords new] => { path: "/passwords/new", persona: "guest" },
      %w[passwords edit] => { path: "/passwords/:token/edit", persona: "guest", needs_id: true },
      # bsdports keeps the social routes behind BSDPORTS_SOCIAL=1.
      %w[notifications index] => { path: "/notifications", persona: "auth", apps: %w[brgen amber] },
    }.freeze

    # Rendered by MasterGuestHome inside each app's own home action, so the home row covers it.
    SHARED_VIEWS_WITHOUT_ROUTE = [%w[shared master_guest]].freeze

    MASTER_PAGES = [
      { id: "master/face", view: "MASTER/web/app/views/chat/index.html.erb", path: "/", persona: "guest" },
      { id: "master/dashboard", view: "MASTER/web/app/views/dashboard/index.html.erb", path: "/dashboard", persona: "guest" },
      { id: "master/offline", view: "MASTER/web/public/offline.html", path: "/offline.html", persona: "guest" },
      { id: "master/diag", view: "MASTER/web/public/diag.html", path: "/diag.html", persona: "guest" },
      { id: "master/swarm", view: "MASTER/web/public/swarm.html", path: "/swarm.html", persona: "guest" },
    ].freeze

    # Guest-open bsdports catalogue paths (family completeness — CRT dialect).
    BSDPORTS_LIVE = [
      { id: "bsdports/home", path: "/", persona: "guest" },
      { id: "bsdports/ports", path: "/ports", persona: "guest" },
      { id: "bsdports/categories", path: "/categories", persona: "guest" },
      { id: "bsdports/maintainers", path: "/maintainers", persona: "guest" },
      { id: "bsdports/session", path: "/session/new", persona: "guest" },
    ].freeze

    module_function

    def all
      brgen_pages + amber_pages + bsdports_pages + shared_pages + master_pages
    end

    # One row per host app, because the engine's view is a different page in each.
    def shared_pages
      SHARED_PAGES.flat_map do |parts, row|
        abs = File.join(SHARED_ROOT, "#{parts.join("/")}.html.erb")
        Array(row[:apps] || %w[brgen amber bsdports]).map do |app|
          {
            id: "#{app}/shared/#{parts.join("/")}",
            app: app,
            view: abs.sub("#{ROOT}/", ""),
            abs_view: abs,
            host: nil,
            path: row[:path],
            action: parts.last,
            persona: row[:persona],
            needs_id: row.fetch(:needs_id, false),
          }
        end
      end
    end

    # A shared page nobody declared is a page no simulation ever loads — which is how
    # /account/export and /notifications both reached production answering 500.
    def uncovered_shared_views
      declared = SHARED_PAGES.keys + SHARED_VIEWS_WITHOUT_ROUTE
      discover(SHARED_ROOT).filter_map do |abs|
        parts = relative_parts(abs, SHARED_ROOT)
        next if mailer_parts?(parts) || declared.include?(parts)

        abs.sub("#{ROOT}/", "")
      end
    end

    def guest_liveable
      all.select { |p| p[:persona] == "guest" && !p[:needs_id] && !mailer?(p) }
    end

    def brgen_pages
      root = APPS["brgen"][:views]
      discover(root).filter_map do |abs|
        parts = relative_parts(abs, root)
        next if mailer_parts?(parts)

        host, path, action = brgen_route(parts)
        rel = parts.join("/")
        {
          id: "brgen/#{rel}",
          app: "brgen",
          view: abs.sub("#{ROOT}/", ""),
          abs_view: abs,
          host: host,
          path: path,
          action: action,
          persona: guest_open_brgen?(path, rel) ? "guest" : "auth",
          needs_id: path.include?(":id") || path.include?(":handle"),
        }
      end
    end

    def amber_pages
      root = APPS["amber"][:views]
      discover(root).map do |abs|
        parts = relative_parts(abs, root)
        path, action = amber_route(parts)
        rel = parts.join("/")
        {
          id: "amber/#{rel}",
          app: "amber",
          view: abs.sub("#{ROOT}/", ""),
          abs_view: abs,
          host: nil,
          path: path,
          action: action,
          persona: guest_open_amber?(path, rel) ? "guest" : "auth",
          needs_id: path.include?(":id") || path.include?(":handle"),
        }
      end
    end

    def master_pages
      MASTER_PAGES.map do |row|
        abs = File.join(ROOT, row[:view])
        {
          id: row[:id],
          app: "master",
          view: row[:view],
          abs_view: abs,
          host: nil,
          path: row[:path],
          action: "show",
          persona: row[:persona],
          needs_id: false,
        }
      end
    end

    def bsdports_pages
      root = APPS["bsdports"][:views]
      return BSDPORTS_LIVE.map { |row| bsdports_live_row(row) } unless File.directory?(root)

      discovered = discover(root).map do |abs|
        parts = relative_parts(abs, root)
        path, action = bsdports_route(parts)
        rel = parts.join("/")
        {
          id: "bsdports/#{rel}",
          app: "bsdports",
          view: abs.sub("#{ROOT}/", ""),
          abs_view: abs,
          host: nil,
          path: path,
          action: action,
          persona: path.end_with?("/edit") ? "auth" : "guest",
          needs_id: path.include?(":id"),
        }
      end
      discovered
    end

    def bsdports_live_row(row)
      {
        id: row[:id],
        app: "bsdports",
        view: "RAILS/bsdports/app/views",
        abs_view: File.join(ROOT, "RAILS", "bsdports", "app", "views", "ports", "index.html.erb"),
        host: nil,
        path: row[:path],
        action: "index",
        persona: row[:persona],
        needs_id: false,
      }
    end

    def bsdports_route(parts)
      case parts
      when %w[ports index], %w[home index] then ["/", "index"]
      when %w[sessions new] then ["/session/new", "new"]
      when %w[categories index] then ["/categories", "index"]
      when %w[categories show] then ["/categories/:id", "show"]
      when %w[maintainers index] then ["/maintainers", "index"]
      when %w[maintainers show] then ["/maintainers/:id", "show"]
      when %w[ports show] then ["/ports/:id", "show"]
      when %w[ports explore] then ["/ports/:id/explore", "explore"]
      when %w[comments new]
        # Nested under ports only — no bare GET /comments/new
        ["/ports/:id/comments", "new"]
      else
        resource = parts[0]
        action = parts[1] || "index"
        [rest_path(resource, action), action]
      end
    end

    def discover(root)
      Dir.glob(File.join(root, "**", "*.html.erb")).sort.reject do |path|
        base = File.basename(path)
        base.start_with?("_") || path.include?("/layouts/")
      end
    end

    def relative_parts(abs, root)
      rel = abs.sub(%r{\A#{Regexp.escape(root)}/?}, "")
      rel = rel.sub(/\.html\.erb\z/, "")
      rel.split("/")
    end

    def mailer_parts?(parts)
      parts.any? { |p| p.end_with?("_mailer") || p == "mailer" }
    end

    def mailer?(page)
      page[:view].to_s.include?("_mailer") || page[:view].to_s.include?("/mailer/")
    end

    def brgen_route(parts)
      if VERTICAL_HOSTS.key?(parts[0])
        vert = parts[0]
        rest = parts[1..]
        host = VERTICAL_HOSTS[vert]
        if VERTICAL_ROOTS[[vert, *rest]]
          return [host, "/", "index"]
        end
        if rest == %w[carts show]
          return [host, "/cart", "show"]
        end
        if rest == %w[home next]
          return [host, "/next", "next"]
        end
        # Dating uses singular resource :profile (not /profiles)
        if vert == "dating" && rest[0] == "profiles"
          action = rest[1] || "show"
          path =
            case action
            when "new" then "/profile/new"
            when "edit" then "/profile/edit"
            when "show" then "/profile"
            else "/profile/#{action}"
            end
          return [host, path, action]
        end
        # TV shows/episodes/videos are nested under channels in routes —
        # treat non-root index/new as needs_id for live probes.
        if vert == "tv" && %w[shows episodes videos].include?(rest[0])
          resource = rest[0]
          action = rest[1] || "index"
          # Live matrix skips :id paths; mark with :id so guest_liveable excludes them.
          path =
            case action
            when "index" then "/channels/:slug/#{resource}"
            when "new" then "/channels/:slug/#{resource}/new"
            when "show" then "/#{resource}/:id"
            else "/#{resource}/#{action}"
            end
          return [host, path, action]
        end
        if vert == "tv" && rest == %w[live_streams new]
          return [host, "/channels/:slug/live_streams/new", "new"]
        end
        resource = rest[0]
        action = rest[1] || "index"
        resource = "shops" if vert == "marketplace" && resource == "stores"
        return [host, rest_path(resource, action), action]
      end

      host = APEX
      case parts
      when %w[home index] then return [host, "/", "index"]
      when %w[sessions new] then return [host, "/session/new", "new"]
      when %w[live index] then return [host, "/live", "index"]
      when %w[search index] then return [host, "/search", "index"]
      when %w[nearby widget] then return [host, "/nearby/widget", "widget"]
      when %w[messages new]
        # No standalone GET /messages/new — DMs open via conversations
        return [host, "/conversations", "new"]
      end

      if parts[0] == "admin"
        path = "/" + parts[0..-2].join("/")
        path = "/admin/reports" if parts == %w[admin reports index]
        return [host, path, parts[-1]]
      end

      # Nested partner/* resources need ids for show/edit
      if parts[0] == "partner"
        resource = parts[1]
        action = parts[2] || "index"
        path =
          case action
          when "index" then "/partner/#{resource}"
          when "new" then "/partner/#{resource}/new"
          when "show" then "/partner/#{resource}/:id"
          when "edit" then "/partner/#{resource}/:id/edit"
          else "/partner/#{resource}/#{action}"
          end
        return [host, path, action]
      end

      resource = parts[0]
      action = parts[1] || "index"
      [host, rest_path(resource, action), action]
    end

    def amber_route(parts)
      case parts
      when %w[home index] then return ["/", "index"]
      when %w[sessions new] then return ["/session/new", "new"]
      when %w[registrations new] then return ["/registration/new", "new"]
      when %w[demo_wardrobe index] then return ["/demo", "index"]
      when %w[demo_wardrobe show] then return ["/demo/items/:id", "show"]
      when %w[posts feed] then return ["/posts/feed", "feed"]
      when %w[outfits dressing_room] then return ["/outfits/dressing_room", "dressing_room"]
      when %w[items shopping_list] then return ["/items/shopping_list", "shopping_list"]
      when %w[wardrobe_items analytics] then return ["/wardrobe_items/analytics", "analytics"]
      when %w[wardrobe_items timeline] then return ["/wardrobe_items/timeline", "timeline"]
      when %w[creator_profiles show] then return ["/creators/:handle", "show"]
      when %w[creator_profiles new] then return ["/creator_profile/new", "new"]
      when %w[creator_profiles edit] then return ["/creator_profile/edit", "edit"]
      when %w[declutter review] then return ["/declutter/:id/review", "review"]
      end

      if parts[0] == "ai"
        map = {
          "capsule" => "/ai/capsule",
          "color_palette" => "/ai/palette",
          "declutter_guide" => "/ai/declutter",
          "mood_board" => "/ai/moodboard",
          "occasion_map" => "/ai/occasions",
          "packing_list" => "/ai/pack",
          "search" => "/ai/search",
          "style_profile" => "/ai/style",
          "suggest_outfits" => "/ai/outfits/suggest",
        }
        return [map.fetch(parts[1], "/ai/#{parts[1]}"), parts[1]]
      end

      resource = parts[0]
      action = parts[1] || "index"
      [rest_path(resource, action), action]
    end

    def rest_path(resource, action)
      case action
      when "index" then "/#{resource}"
      when "new" then "/#{resource}/new"
      when "show" then "/#{resource}/:id"
      when "edit" then "/#{resource}/:id/edit"
      when "embed" then "/#{resource}/:id/embed"
      when "review" then "/#{resource}/:id/review"
      else "/#{resource}/#{action}"
      end
    end

    def guest_open_brgen?(path, rel)
      return false if rel.match?(%r{\Aadmin/|activity_events|notifications|saved_searches|matches|profiles/edit|orders/})
      return false if path.end_with?("/edit")
      # Nested create forms need a channel/resource id — not guest-liveable as bare paths
      return false if path.include?("/channels/:slug/")
      true
    end

    def guest_open_amber?(path, _rel)
      open_exact = %w[/ /items /demo /posts /posts/feed /session/new /registration/new /outfits /passwords/new]
      return true if open_exact.include?(path)
      return true if path.start_with?("/demo") || path.start_with?("/ai/")
      return false if path.end_with?("/edit") || path.include?("/new")
      # Default browse indexes that still need session are auth
      %w[/connections /declutter /live_streams /messages /planned_outfits /wardrobe_items /items/shopping_list].include?(path) ? false : false
    end

    def write_snapshot!(path = File.join(ROOT, "RAILS", "gates", "data", "page_sim_inventory.yml"))
      rows = all.map do |p|
        p.except(:abs_view).transform_keys(&:to_s)
      end
      File.write(path, {
        "generated_note" => "Snapshot of Deploy::PageInventory.all — regenerate via page_simulation gate",
        "count" => rows.size,
        "pages" => rows,
      }.to_yaml)
      path
    end
  end
end
