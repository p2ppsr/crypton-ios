# Crypton SDK adaptations

The packaged SDK 3.2.1 browser bundle increases AuthFetch's authenticated-response
deadline and Peer's BRC-103 initial-response deadline from 30 seconds to 600 seconds. The original deadline includes wallet
authentication and signing, which require multiple foreground handoffs between
Crypton and Metanet Explorer on iOS. The native operation remains bounded to fifteen
minutes, each wallet request to five minutes, and HTTP requests retain their own
deadline. Authentication, server identity validation and payment policy are unchanged.

The unique minified expression changed is:

```diff
- b(Error("Timed out waiting for authenticated response."))},3e4)
+ b(Error("Timed out waiting for authenticated response."))},6e5)
```

The unique initial-response expression is similarly changed from `r(Error("Timeout waiting for the BRC-103 initial response."))},3e4)` to `r(Error("Timeout waiting for the BRC-103 initial response."))},6e5)`.
