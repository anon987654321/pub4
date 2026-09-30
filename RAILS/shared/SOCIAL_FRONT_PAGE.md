# Social front-page reference

Updated 2026-09-30 after a current review of Reddit, X and TikTok, with the goal of taking interaction patterns rather than copying their surface styling.

## Consent

The useful pattern is not a louder "accept" button. It is a short explanation, equal first-layer choices and an easy path to preferences. X documents a broad stack of cookies, pixels and local storage for authentication, preferences, personalization, analytics, advertising and related functions. It also documents extra controls for off-X activity and personalization. TikTok likewise exposes cookie and advertising measurement controls in its privacy tooling.

Pub4 already had the right core behavior: optional analytics and advertising stay off until consent, with accept/reject/manage peers. The integration adds an explicit necessary-storage row so the reader can see what is essential and what is optional.

## Onboarding

Reddit's own guidance stresses that a new visitor should understand a community through clear descriptions, rules, welcoming material and posting guidance. X's signup sequence asks for account setup, then interests/accounts, then posting. TikTok's main product loop is the For You feed: the user starts watching and recommendations learn from engagement.

The pub4 implication is simple: do not put a long setup wizard between a visitor and the product. The existing welcome cover remains the deliberate first-run story, with three concrete steps, persistent dismissal and consent-aware ordering. MASTER now treats "show the product before asking for setup" as a durable constraint.

## Content

Reddit supplies contextual community identity and multiple feed interpretations. X compresses a post into identity, statement/media and a compact action row. TikTok reduces the cognitive load further by letting the media itself become navigation and by continuously adapting what comes next.

For brgen this argues for a feed that feels locally alive before it feels like a dashboard. The existing city feed, staged live arrivals, media wall and vertical promotional units already provide the building blocks. The new post-detail action jump makes the conversation immediately reachable without adding another feed-ordering strip to root.

Amber should keep its editorial reading posture rather than imitate a generic social feed: richer whitespace, wardrobe/item context, then action and discussion.

## Post detail and auth

The strongest small pattern from X is a focused auth interruption that preserves the current context. X documents that its follow widget shows a small pop-up when used by logged-out visitors, rather than requiring the widget host page to become the account page.

Pub4 now uses the browser's native Popover API for the same class of interaction on brgen and amber post detail pages. It offers sign in and account creation in a compact surface while leaving the post readable. Native popover avoids another bespoke modal state and keeps focus, escape and top-layer behavior with the browser.

Brgen also exposes the existing comment count as a direct jump from the detail action row. The page remains content-first, while social proof and discussion are only one small gesture away.

## Small details worth keeping

Use the browser's native overlay primitives where they fit. Keep 44px interaction geometry, visible focus, one reading measure, no duplicated nav, staged live arrivals, and explicit sponsored labeling. Avoid copying colors, gradients, radius values or visual chrome merely because another service uses them; those values remain owned by the pub4 design system and its operator.

## Primary sources

Reddit:
- https://support.reddithelp.com/hc/en-us/articles/53416317564820-Changelog-September-10-2026
- https://support.reddithelp.com/hc/en-us/articles/28621027395220-How-to-join-or-leave-a-community
- https://support.reddithelp.com/hc/en-us/articles/15484358732692-Welcoming-new-members
- https://support.reddithelp.com/hc/en-us/articles/45959071783316-Changelog-February-4-2026

X:
- https://help.x.com/en/using-x/x-timeline
- https://help.x.com/en/using-x/create-x-account
- https://help.x.com/en/rules-and-policies/x-cookies
- https://help.x.com/en/using-x/add-follow-button-to-website
- https://help.x.com/en/rules-and-policies/recommendations

TikTok:
- https://support.tiktok.com/en/getting-started/for-you/test-for-you
- https://newsroom.tiktok.com/new-features-bring-tiktok-magic-to-desktop?lang=en
