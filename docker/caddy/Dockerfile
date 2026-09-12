# Official Caddy does not ship the rate-limit module, and Nextcloud's login
# form is exactly the kind of endpoint that needs one in front of it on the
# open internet. Build it in with xcaddy instead of hand-rolling rate
# limiting elsewhere.
FROM caddy:2-builder AS builder

RUN xcaddy build \
    --with github.com/mholt/caddy-ratelimit

FROM caddy:2-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
