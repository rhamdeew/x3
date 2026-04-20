FROM ghcr.io/mhsanaei/3x-ui:latest
ARG PROCESS_NAME=nginx

# Rename the xray binary to the desired process name.
# 3x-ui Go code constructs the binary name as "xray-{os}-{arch}" at runtime,
# so we keep a tiny wrapper at the original path that execs the renamed binary.
RUN XRAY_BIN=$(find /app/bin -name 'xray-linux-*' -type f | head -1) && \
    XRAY_DIR=$(dirname "$XRAY_BIN") && \
    XRAY_BASE=$(basename "$XRAY_BIN") && \
    NEW_NAME="${PROCESS_NAME}${XRAY_BASE#xray}" && \
    mv "$XRAY_BIN" "${XRAY_DIR}/${NEW_NAME}" && \
    printf '#!/bin/sh\nexec "%s/%s" "$@"\n' "$XRAY_DIR" "$NEW_NAME" > "$XRAY_BIN" && \
    chmod +x "$XRAY_BIN"

ENV PROCESS_NAME=${PROCESS_NAME}
