# frozen_string_literal: true

pin "application"
pin_all_from "app/javascript/controllers", under: "controllers"
eval(File.read(Shared::Engine.root.join("config/importmap_baseline.rb")), binding)

pin "idb-keyval", to: "idb-keyval.js"
pin "lightgallery", to: "lightgallery.js"
pin "radio_brgen_tunnel", to: "radio_brgen_tunnel.js"