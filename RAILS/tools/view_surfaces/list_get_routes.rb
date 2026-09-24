# frozen_string_literal: true

# Prints this app's HTML GET routes as JSON lines: path spec, controller#action,
# subdomain constraint, and whether the path needs parameters. Run with
# bin/rails runner from the app directory.
require "json"

SKIP = %r{\A/(rails|assets|cable|up|health|service-worker|manifest|recede|resume|refresh|active_storage|api|admin/jobs|letter_opener|jobs)\b}

def walk(routes, prefix = "", constraint = nil, &blk)
  routes.each do |route|
    app = route.app
    app = app.app while app.respond_to?(:app) && !app.respond_to?(:routes) && app.respond_to?(:constraints)
    sub = route.constraints[:subdomain] || constraint
    if app.respond_to?(:routes) && app.routes.respond_to?(:routes) && app != Rails.application
      walk(app.routes.routes, prefix + route.path.spec.to_s.sub(/\(\.:format\)\z/, ""), sub, &blk)
      next
    end
    blk.call(route, prefix, sub)
  end
end

walk(Rails.application.routes.routes) do |route, prefix, sub|
  next unless route.verb.to_s.split("|").include?("GET")
  next if route.defaults[:controller].nil?
  next if route.defaults[:format] && route.defaults[:format].to_s != "html"

  path = prefix + route.path.spec.to_s.sub(/\(\.:format\)\z/, "")
  path = "/" if path.empty?
  next if path =~ SKIP || path.include?("*")

  puts JSON.generate(
    path:, action: "#{route.defaults[:controller]}##{route.defaults[:action]}",
    subdomain: sub.is_a?(Regexp) ? sub.source : sub, params: path.scan(/:(\w+)/).flatten
  )
end
