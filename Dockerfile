ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2021-10-15@sha256:33e021267790132e63be2cea08e77d64ec5d0434355734e94f8ff2d90c6f8944
ARG           FROM_IMAGE_AUDITOR=base:auditor-bullseye-2021-10-15@sha256:eb822683575d68ccbdf62b092e1715c676b9650a695d8c0235db4ed5de3e8534
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2021-10-15@sha256:7072702dab130c1bbff5e5c4a0adac9c9f2ef59614f24e7ee43d8730fae2764c
ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2021-10-15@sha256:e8ec2d1d185177605736ba594027f27334e68d7984bbfe708a0b37f4b6f2dbd7
ARG           FROM_IMAGE_NODE=base:node-bullseye-2021-10-15@sha256:7147b869d742a33a9a761163e02766bd2eb5a118011d37c2cc8ec6b415fd13c7

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools
FROM          $FROM_REGISTRY/$FROM_IMAGE_NODE                                                                           AS builder-node

#######################
# Fetcher
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS fetcher-main

ARG           GIT_REPO=github.com/parse-community/parse-server
ARG           GIT_VERSION=4.10.4
ARG           GIT_COMMIT=4ac4b7f71002ed4fbedbb901db1f6ed1e9ac5559

RUN           git clone --recurse-submodules git://"$GIT_REPO" .; git checkout "$GIT_COMMIT"

#######################
# Parse server
#######################
FROM          --platform=$BUILDPLATFORM fetcher-main                                                                    AS builder-main

ARG           TARGETARCH
ARG           TARGETOS
ARG           TARGETVARIANT

COPY          --from=builder-node /usr/local/bin/node /dist/boot/bin/node
COPY          --from=builder-node /usr/local/bin/node /dist/boot/bin/nodejs
COPY          --from=builder-node /usr/local/bin/yarn /dist/boot/bin/yarn
COPY          --from=builder-node /usr/local/bin/yarn /dist/boot/bin/yarnpkg

ARG           npm_config_arch=$TARGETARCH

# XXX cross compiling?
# npm rebuild --arch=${ARCH} --target_arch=arm)?
#RUN           yarn build --skip-os-packages
# XXX cross compiling?

# RUN           yarn ci # --production --ignore-scripts
# hadolint ignore=DL3003

# RUN apt show yarn; apt search yarn; exit 1
#RUN           \
#              mkdir bare; cp package* bare; cd bare; \
#              yarn install --frozen-lockfile --ignore-scripts --production; ls -lA

# RUN exit 1

# hadolint ignore=DL3003
RUN           mkdir bare; cp package* bare; cd bare || exit 1; \
#              ls -lA; cat package.json; \
              npm ci; \
              mv node_modules ../

#RUN           yarn install --frozen-lockfile --ignore-scripts
RUN           yarnpkg build
#RUN           rm -Rf node_modules
#RUN           yarn install --frozen-lockfile --ignore-scripts --production

RUN           mkdir -p /dist/boot/parse
RUN           mv bin /dist/boot/parse
RUN           mv public_html /dist/boot/parse
RUN           mv views /dist/boot/parse
RUN           mv lib /dist/boot/parse
RUN           mv node_modules /dist/boot/parse
RUN           mv package* /dist/boot/parse


#RUN mkdir -p logs && chown -R node: logs

#ENV PORT=1337
#USER node
#EXPOSE $PORT
#ENTRYPOINT ["node", "./bin/parse-server"]


#######################
# Builder assembly
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_AUDITOR                                              AS assembly

COPY          --from=builder-main /dist/boot /dist/boot

COPY          --from=builder-tools  /boot/bin/goello-server-ng  /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/caddy          /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/http-health    /dist/boot/bin

RUN           setcap 'cap_net_bind_service+ep' /dist/boot/bin/caddy

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Running image
#######################
FROM          $FROM_REGISTRY/$FROM_IMAGE_RUNTIME

COPY          --from=assembly --chown=$BUILD_UID:root /dist /

### Front server configuration
# Port to use
ENV           PORT_HTTPS=443
ENV           PORT_HTTP=80
EXPOSE        443
EXPOSE        80
# Log verbosity for
ENV           LOG_LEVEL="warn"
# Domain name to serve
ENV           DOMAIN="$NICK.local"
ENV           ADDITIONAL_DOMAINS=""
# Whether the server should behave as a proxy (disallows mTLS)
ENV           SERVER_NAME="DuboDubonDuponey/1.0 (Caddy/2) [$NICK]"
# Control wether tls is going to be "internal" (eg: self-signed), or alternatively an email address to enable letsencrypt - use "" to disable TLS entirely
ENV           TLS="internal"
# 1.2 or 1.3
ENV           TLS_MIN=1.3
# Issuer name to appear in certificates
#ENV           TLS_ISSUER="Dubo Dubon Duponey"
# Either disable_redirects or ignore_loaded_certs if one wants the redirects
ENV           TLS_AUTO=disable_redirects
# Either require_and_verify or verify_if_given, or "" to disable mTLS altogether
ENV           MTLS="require_and_verify"
# Root certificate to trust for mTLS
ENV           MTLS_TRUST="/certs/mtls_ca.crt"
# Realm for authentication - set to "" to disable authentication entirely
ENV           AUTH="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           AUTH_USERNAME="dubo-dubon-duponey"
ENV           AUTH_PASSWORD="cmVwbGFjZV9tZV93aXRoX3NvbWV0aGluZwo="
### mDNS broadcasting
# Type to advertise
ENV           MDNS_TYPE="_http._tcp"
# Name is used as a short description for the service
ENV           MDNS_NAME="$NICK mDNS display name"
# The service will be annonced and reachable at $MDNS_HOST.local (set to empty string to disable mDNS announces entirely)
ENV           MDNS_HOST="$NICK"
# Also announce the service as a workstation (for example for the benefit of coreDNS mDNS)
ENV           MDNS_STATION=true
# Caddy certs will be stored here
VOLUME        /certs
# Caddy uses this
VOLUME        /tmp
# Used by the backend service
VOLUME        /data
ENV           HEALTHCHECK_URL="http://127.0.0.1:10000/?healthcheck"

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1