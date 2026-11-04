# frozen_string_literal: true

require "test_helper"

# The engine's mail layout and the auth mails that render through it. The
# password-reset mail was English literals as bare paragraphs on the dark
# canvas, the sign-in mail bare paragraphs with a default blue link, and the
# layout titled every mail without an edition "Newsletter".
class SharedMailLayoutTest < ActionMailer::TestCase
  def user
    @user ||= User.create!(email_address: "mail-layout@example.com", password: "password")
  end

  def html(mail) = (mail.html_part || mail).body.to_s
  def text(mail) = (mail.text_part || mail).body.to_s

  test "the layout titles a mail by its subject and tells clients it paints its own scheme" do
    mail = PasswordsMailer.reset(user)
    page = Nokogiri::HTML(html(mail))

    assert_equal I18n.t("mailer.password_reset_subject"), page.at("title").text
    assert_equal "light dark", page.at("meta[name='color-scheme']")&.[]("content")
    assert_equal "light dark", page.at("meta[name='supported-color-schemes']")&.[]("content")
    assert_nil page.at(".skip-link"), "a mail has no page chrome to skip"
  end

  test "an edition's preheader opens the body and its subject is the title" do
    sub = EmailSubscription.create!(email: "layout-edition@example.com", confirmed: true, agreed_to_marketing: true)
    edition = NewsletterEdition.create!(
      kind: "daily", city: "bergen", edition_date: Date.current, subject: "Uka i Bergen",
      preheader: "Tre ting i dag", lede: "Noen nyttige ting.", sign_off: "Brgen",
      permission_line: "Du ba om disse e-postene.", stories: [], deals: []
    )
    body = html(NewsletterMailer.edition(sub, edition))

    assert_equal "Uka i Bergen", Nokogiri::HTML(body).at("title").text
    assert_operator body.index("Tre ting i dag"), :>, body.index("<body")
  end

  test "the password-reset mail is Norwegian, in the mail shell, with one button" do
    mail = PasswordsMailer.reset(user)
    page = Nokogiri::HTML(html(mail))
    reset_url = %r{/passwords/[^"]+/edit}

    assert page.at("table.mail-shell"), "expected the mail shell, not bare paragraphs"
    button = page.at("a.mail-cta")
    assert_equal I18n.t("mailer.password_reset_action"), button.text.strip
    assert_match reset_url, button["href"]
    assert_includes page.text, I18n.t("mailer.password_reset_lede")
    refute_match(/You can reset|This link will expire/, html(mail) + text(mail))
    assert_includes text(mail), I18n.t("mailer.password_reset_action")
    assert_match reset_url, text(mail)
  end

  test "the sign-in mail is in the mail shell with its link as the button" do
    mail = Shared::PasswordlessMailer.sign_in(user, "magic-token")
    page = Nokogiri::HTML(html(mail))

    assert page.at("table.mail-shell")
    button = page.at("a.mail-cta")
    assert_equal I18n.t("mailer.sign_in_link_action"), button.text.strip
    assert_includes button["href"], "token=magic-token"
    assert_equal I18n.t("mailer.sign_in_link_subject"), page.at("title").text
    assert_includes text(mail), "token=magic-token"
  end

  test "the shared verification mail carries its link in both parts" do
    user.generate_email_verification!
    mail = Shared::VerificationMailer.verify(user.reload, "brgen.no")

    assert_equal I18n.t("mailer.verify_email_subject"), Nokogiri::HTML(html(mail)).at("title").text
    [ html(mail), text(mail) ].each { |part| assert_includes part, "https://brgen.no/" }
  end
end
