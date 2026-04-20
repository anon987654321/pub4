# Action Mailbox

Action Mailbox receives inbound email, converts each message into an `InboundEmail` record, stores the original payload with Active Storage, and incinerates the data by default.  

Routes are delivered asynchronously via Active Job to mailboxes that act like controllers, offering direct access to your domain model.  

Supported ingresses: Mailgun, Mandrill, Postmark, SendGrid, and direct Exim, Postfix, Qmail configurations.  

For details, see the [Action Mailbox Basics](https://guides.rubyonrails.org/action_mailbox_basics.html) guide.  

License: MIT (https://opensource.org/licenses/MIT)