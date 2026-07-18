# frozen_string_literal: true

module Brgen
  # Brgen alias for shared demo seed media helpers (Bergen photography catalog).
  module DemoMedia
    CATALOG = Pathname.new(__dir__).join("../../config/demo_media/bergen.yml").expand_path.freeze

    module_function

    def attach_remote!(*args, **kwargs)
      Shared::DemoMedia.attach_remote!(*args, **kwargs, catalog: CATALOG)
    end

    def attach_remote_postpro!(*args, **kwargs)
      Shared::DemoMedia.attach_remote_postpro!(*args, **kwargs, catalog: CATALOG)
    end

    def skip_attach?
      Shared::DemoMedia.skip_attach?
    end

    def catalog_path
      CATALOG
    end
  end
end