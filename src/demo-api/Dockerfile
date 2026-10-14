FROM --platform=$BUILDPLATFORM golang:1.27 AS build
ARG TARGETOS
ARG TARGETARCH
ARG VERSION=dev
WORKDIR /src
COPY go.mod ./
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags "-s -w -X main.version=$VERSION" -o /out/demo-api .

FROM gcr.io/distroless/static-debian13:nonroot
COPY --from=build /out/demo-api /demo-api
EXPOSE 8080
ENTRYPOINT ["/demo-api"]
