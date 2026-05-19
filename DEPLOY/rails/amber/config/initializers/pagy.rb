# frozen_string_literal: true

require "pagy/extras/overflow"
Pagy::DEFAULT[:items]    = 25
Pagy::DEFAULT[:overflow] = :last_page
