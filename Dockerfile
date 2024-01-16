# syntax=docker/dockerfile:1.6

ARG GOLANG_VERSION="1.21"
ARG BUILD_IMAGE_REPO="public.ecr.aws/docker/library/golang"
ARG BUILD_IMAGE="${BUILD_IMAGE_REPO}:${GOLANG_VERSION}-alpine"

ARG GOLANGCI_LINT_IMAGE="golangci/golangci-lint:latest"

ARG BASE_IMAGE="scratch"

# =============================================================================
FROM ${BUILD_IMAGE} as base

SHELL ["/bin/ash", "-e", "-u", "-o", "pipefail", "-c"]

WORKDIR /src/local-path-provisioner

ARG GO111MODULE="on"
ARG CGO_ENABLED="0"
ARG GOARCH="amd64"
ARG GOOS="linux"
ENV GO111MODULE="${GO111MODULE}" \
    CGO_ENABLED="${CGO_ENABLED}"  \
    GOARCH="${GOARCH}" \
    GOOS="${GOOS}"

RUN --mount=type=bind,source=./go.mod,target=./go.mod \
    --mount=type=bind,source=./go.sum,target=./go.sum \
    --mount=type=cache,target=/go/pkg/mod \
    go mod download

# =============================================================================
FROM ${GOLANGCI_LINT_IMAGE} AS lint-base

# =============================================================================
FROM base AS lint

RUN --mount=type=bind,source=./,target=./ \
    --mount=from=lint-base,src=/usr/bin/golangci-lint,target=/usr/bin/golangci-lint \
    --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/root/.cache/golangci-lint \
    \
    golangci-lint run \
        --color never \
        --timeout 10m0s ./... | tee /linter_result.txt

# =============================================================================
FROM base AS test

RUN --mount=type=bind,source=./,target=./ \
    --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go test -v -coverprofile=/cover.out ./...

# =============================================================================
FROM base as build

ARG APP_VERSION="docker"

RUN --mount=type=bind,source=./,target=./ \
    --mount=from=lint-base,src=/usr/bin/golangci-lint,target=/usr/bin/golangci-lint \
    --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    \
    go build \
        -tags musl \
        -ldflags '-w -s -X main.VERSION=${APP_VERSION}' -a \
        -o /local-path-provisioner

# wait until other stages are done
# COPY --from=lint /linter_result.txt /linter_result.txt
COPY --from=test /cover.out /cover.out

# =============================================================================
FROM ${BASE_IMAGE} as release
COPY --link --from=build /local-path-provisioner /usr/bin/local-path-provisioner
ENTRYPOINT [ "local-path-provisioner" ]
