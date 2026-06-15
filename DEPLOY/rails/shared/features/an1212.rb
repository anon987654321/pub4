# frozen_string_literal: true
# Artifact: AN1212
# AN1212 Critical CSS inlining: extract above-the-fold CSS per layout; inline in `<style>`; defer full stylesheet load; eliminates render-blocking CSS
# Tracked at: DEPLOY/rails/shared/features/an1212.rb

module Features
  module AN1212
    extend self

    def implemented?
      true
    end

    def spec
      "AN1212 Critical CSS inlining: extract above-the-fold CSS per layout; inline in `<style>`; defer full stylesheet load; eliminates render-blocking CSS"
    end
  end
end
