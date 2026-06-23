FROM alpine:latest
RUN apk --no-cache add swi-prolog --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing --repository=https://dl-cdn.alpinelinux.org/alpine/edge/main
COPY *.pl /srv/
WORKDIR /srv
RUN for pl in *.pl; do swipl -q -t "qcompile('$pl')"; done; rm *.pl
ENTRYPOINT ["swipl", "-s", "ev_abs", "--"]
