FROM golang:1.25-alpine AS build
WORKDIR /src
RUN apk add --no-cache git
RUN git clone --depth 1 https://github.com/hnrss/hnrss.git .
RUN CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o /hnrss .

FROM alpine:3.20
RUN apk add --no-cache ca-certificates
COPY --from=build /hnrss /hnrss
EXPOSE 9000
ENTRYPOINT ["/hnrss", "-bind", "0.0.0.0:9000"]
