# frozen_string_literal: true

module MaintainersHelper
  # The maintainer index and pages are crawlable lists of about a thousand
  # addresses, so they print "kn (at) openbsd.org" and carry no mailto: a
  # reader can still copy it, a harvester matching name@host cannot.
  def obfuscated_email(email)
    user, domain = email.to_s.split("@", 2)
    return email if domain.blank?

    tag.span t("maintainers.email_obfuscated", user:, domain:), class: "maintainer-email", translate: "no"
  end
end
