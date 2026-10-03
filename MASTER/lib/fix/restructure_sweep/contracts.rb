# frozen_string_literal: true

module Master
  module Fix
    class RestructureSweep
      # What each tree's code promises, handed to the model with every
      # restructure it proposes there. The proof checks these after the fact;
      # stating them first saves the calls a broken plan would cost.
      module Contracts
        COMMON = <<~TEXT
          - Every require, require_relative, source and render that names a moved file is updated.
          - Methods stay within 20 code lines and classes within 300.
          - A comment states the present-tense reason; keep the ones that still hold.
          - At most 12 files.
        TEXT

        BY_TREE = {
          "MASTER" => <<~TEXT,
            MASTER, a constitutional AI runtime in Ruby.
            - MASTER/lib/ loads through Zeitwerk under Master: lib/a/b_c.rb defines
              Master::A::BC, one constant per file, path and constant always agreeing.
              Inflections: cli->CLI, llm->LLM, llm_dispatcher->LLMDispatcher, tts->TTS.
            - MASTER/data/rules.yml and MASTER/data/soul.yml are never written.
          TEXT
          "RAILS" => <<~TEXT,
            RAILS, three Rails 8 apps (brgen, amber, bsdports) and RAILS/shared, a
            mixin engine all three mount; brgen's verticals are engines under
            RAILS/brgen/engines.
            - Zeitwerk per app: app/models/foo_bar.rb defines FooBar; a partial
              app/views/posts/_card.html.erb is reached by render "posts/card".
            - User-facing text goes through I18n keys and defaults to Norwegian; never
              add an English literal.
            - One application.scss per app, partials through @use; the compiled CSS
              must not change.
            - db/migrate and db/schema are never touched.
          TEXT
          "OPENBSD" => <<~TEXT,
            OPENBSD, the deploy pipeline and runbook for one OpenBSD VPS.
            - OPENBSD/etc, var, usr, home and dotfiles mirror the box path for path
              and never move. An rc.d script's name is its service's name.
            - Scripts are zsh or POSIX sh with OpenBSD base tools; no GNU-only flags.
          TEXT
        }.freeze

        def self.for(tree) = "#{BY_TREE.fetch(tree)}#{COMMON}"
      end
    end
  end
end
