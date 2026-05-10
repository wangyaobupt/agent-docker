ARG AGENT_BASE_TAG=<AGENT_BASE_DATE_TAG>
FROM agent-base:${AGENT_BASE_TAG}

# Project-specific apt extras. Delete this RUN if none needed.
# RUN apt-get update && apt-get install -y --no-install-recommends \
#     <package> <package> \
#     && rm -rf /var/lib/apt/lists/*

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace/<PROJECT_NAME>

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["codex", "-C", "/workspace/<PROJECT_NAME>"]
