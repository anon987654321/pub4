# frozen_string_literal: true

require "minitest/autorun"

class PwaGeneratorContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def source
    @source ||= File.read(File.join(ROOT, "..", "MASTER", "tools", "rails", "build_workbox.mjs"))
  end

  test "all store apps generate from one shared worker source" do
    assert_includes source, 'const APPS = ["amber", "brgen", "bsdports"]'
    assert_includes source, 'const source = join(root, "__shared", "pwa", "service_worker.js")'
    assert_includes source, 'const destination = join(root, app, "app", "views", "pwa", "service-worker.js")'
  end

  test "the generator excludes digest assets from precache" do
    assert_includes source, 'globIgnores: ["service-worker.js", "assets/**"]'
    assert_includes source, '{ url: "/", revision: "shell-v1" }'
    assert_includes source, '{ url: "/offline", revision: "offline-v1" }'
  end

  test "workbox version and browser floor stay explicit" do
    assert_includes source, "Workbox 7.4.1 generated"
    assert_includes source, 'target: ["chrome96", "firefox102", "safari16"]'
  end
end
