FROM ghcr.io/xtls/xray-core:latest AS source

FROM busybox:musl
ARG PROCESS_NAME=nginx
ENV PROCESS_NAME=${PROCESS_NAME}

COPY --from=source /usr/local/bin/xray /usr/local/bin/${PROCESS_NAME}
COPY --from=source /usr/local/share/xray/ /usr/local/share/xray/
COPY --from=source /usr/local/etc/xray/ /usr/local/etc/xray/
RUN mkdir -p /var/log/xray

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
