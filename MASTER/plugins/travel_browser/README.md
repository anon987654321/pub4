# Travel Browser

**Travel Browser lets MASTER do the searching, comparing and form-filling of a
trip, and leaves the one act that spends money, and every secret on the way to
it, in the hands of the person who is going.**

It drives a visible browser, through the Ferrum gem, for flights, hotels,
restaurants, tours and transfers. It works on any site that has a page, because
it automates the page and not a provider's private interface. A provider with a
stable authenticated API and a stronger contract may get its own adapter later.

The actions are status, inspect, open, login, fill, click and book. Open
accepts HTTPS addresses only and passes them through the same guard that blocks
loopback, private and reserved destinations. Inspect returns the page title,
its text, up to 120 of its form controls and a screenshot. Page text passes
through the injection guard and is treated as untrusted content, never as
instruction. Each browser action keeps a named session, a profile stored under
`~/.master/plugins/travel_browser/sessions/` with owner-only permissions. The
repository holds no credentials and no booking state.

Secrets stay with the operator. Login waits in the visible browser while the
operator types credentials and one-time codes, and MASTER receives none of
them. The fill action refuses any selector that names a password, one-time
code, card, security code or passport field, so those fields can only be filled
by hand. A CAPTCHA, an access-denied page or any other security challenge stops
the run and waits for a person.

The book action is the final gate. It does nothing unless the call carries
confirm_purchase set to true, and it compares the total on the page with the
expected total when the caller supplies one. A mismatch refuses the click. The
result holds the URL, the page title, the visible total and screenshots from
before and after. It states that the submission happened and that the
confirmation page or the booking email must prove the rest. A click alone is
never reported as a booking.

The rules are declared in `data/laws.yml` under the travel_browser policy, and
the manifest, `plugin.yml`, marks only status and inspect as observable. The
other five actions run only through an explicit plugin run. The code is in
`travel_browser.rb`.

## Use

Inside a MASTER session, the plugin command reaches it.

```text
/plugin info travel_browser
/plugin run travel_browser status
/plugin run travel_browser open {"session":"trip","url":"https://example.com"}
```
