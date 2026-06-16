# config/application.rb
module MyApp
  class Application < Rails::Application
    # ------------------------------------------------------------------
    # Action Mailbox – ingress selection
    # ------------------------------------------------------------------
    # Choose one of the supported ingresses:
    #   :mailgun, :mandrill, :postmark, :sendgrid, :relay, :smtp
    # The selected ingress must have its adapter gem installed and the
    # required credentials present in `config/credentials.yml.enc` or
    # environment variables.  Missing credentials raise a clear error at
    # boot time, preventing silent failures.
    config.action_mailbox.ingress = :mailgun

    # ------------------------------------------------------------------
    # Routing – map recipient patterns to mailbox classes
    # ------------------------------------------------------------------
    # Keys are regular expressions matched against the full recipient
    # address.  Values are the constant name of a class inheriting from
    # `ApplicationMailbox`.  Use fully‑qualified strings to avoid
    # autoloading surprises during eager load.
    #
    # Example:
    #   %r{^support@} => "SupportMailbox"
    #   %r{^sales@}   => "SalesMailbox"
    #
    # If you need a nested mailbox (e.g. Admin::AlertsMailbox), use the
    # fully‑qualified constant name:
    #   %r{^alerts@} => "Admin::AlertsMailbox"
    config.action_mailbox.routing = {
      %r{^support@} => "SupportMailbox",
      %r{^sales@}   => "SalesMailbox"
    }

    # ------------------------------------------------------------------
    # Preserve raw inbound email
    # ------------------------------------------------------------------
    # When true, the original MIME message is stored in Active Storage.
    # This aids debugging and forensic analysis but increases storage
    # usage.  Ensure a service (e.g. S3, GCS) is configured for Active
    # Storage to avoid filling the local disk.
    config.action_mailbox.store_original_email = true

    # Retention period for the stored original email.
    # Accepts any ActiveSupport::Duration.  Use `:destroy` to delete
    # immediately after processing, or a concrete period such as
    # `30.days`.  The default is `:destroy`.
    config.action_mailbox.store_original_email_retention = 30.days

    # ------------------------------------------------------------------
    # Active Storage – route prefix
    # ------------------------------------------------------------------
    # Adjust only if you serve uploads from a custom path.  Changing this
    # prefix requires updating any external services that reference the
    # generated URLs.
    config.active_storage.routes_prefix = '/rails/active_storage'
  end
end