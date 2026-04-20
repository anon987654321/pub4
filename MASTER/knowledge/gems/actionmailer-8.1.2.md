class Notifier < ActionMailer::Base
  default from: 'system@loudthinking.com'

  def welcome(recipient)
    @recipient = recipient
    mail(to: recipient,
         subject: "[Signed up] Welcome #{recipient}")
  end
end
