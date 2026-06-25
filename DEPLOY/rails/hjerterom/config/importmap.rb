# frozen_string_literal: true

pin "application"
pin_all_from "app/javascript/controllers", under: "controllers"
eval(File.read(Shared::Engine.root.join("config/importmap_baseline.rb")), binding)