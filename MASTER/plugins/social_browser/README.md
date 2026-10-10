# Social Browser

**Social Browser lets MASTER act in the one place an operator lives
online, their own accounts, while the operator keeps every key, every consent
and every consequence.**

It drives a real browser, through the Ferrum gem, on accounts the operator owns
or is authorized to run. Three sites are wired in today: OnlyFans, FetLife and
Snapchat web. Each has an HTTPS start page and a short list of allowed hosts,
and the plugin refuses any other destination. The status action reports whether
the browser is available and which sites are known.

Logging in is the operator's work. The login action opens a visible browser and
takes a screenshot; the operator types the password and any one-time code
there. MASTER never receives passwords, codes, cookies or session credentials.
The browser profile for each account lives under
`~/.master/plugins/social_browser/accounts/`, with owner-only permissions, and
never in the repository.

Reading is open and writing is narrow. The inspect action returns the page
title, the page text and a screenshot, and the text passes through MASTER's
injection guard because a page is untrusted input and never an instruction. Two
actions write: publish_owned posts to an account the caller declares owned, and
reply_inbound answers a message that someone sent to that account. Each needs
explicit consent in the call, and each does one thing per invocation. A message
may not be empty or exceed 4,000 bytes. An account takes one write in any
fifteen seconds, and a lock stops two runs from using the same account at once.
Every write leaves three screenshots, before, typed and after.

A CAPTCHA or security challenge stops the run for a human, before and after a
write. The plugin does not try to get past one. A missing composer, a missing
submit button, an expired session or a changed page is reported as a failure,
and the plugin never says an action is done because a click was attempted.

The law in `data/laws.yml` forbids what this plugin could otherwise be bent
into: unsolicited bulk messaging, automated friend farming, automated
following, deceiving anyone about identity, and getting around a challenge. A
change that makes any of those easier does not belong here.

The manifest, `plugin.yml`, declares status and inspect as observable, so
MASTER's guarded observation tool may call them. Login and the two writes run
only through an explicit plugin run. The code is in `social_browser.rb`.

## Use

Inside a MASTER session, the plugin command reaches it.

```text
/plugin info social_browser
/plugin run social_browser status
```
