# Use a Python image with uv pre-installed
FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim

# Allow statements and log messages to immediately appear in the Knative logs
ENV PYTHONUNBUFFERED True
# Copy from the cache instead of linking since it's a mounted volume
ENV UV_LINK_MODE=copy

# Use vertex by default
ENV GOOGLE_GENAI_USE_VERTEXAI True

# Install the project into `/app`
WORKDIR /app
ADD . /app

# Install production dependencies.
RUN uv pip install -r requirements.txt --system

# Place executables in the environment at the front of the path
ENV PATH="/app/.venv/bin:$PATH"

# Expose the port
EXPOSE 8080

# Run adk web by default, can also run api_server if you choose
ENTRYPOINT ["uv", "run", "adk", "web", "--host", "0.0.0.0", "--port", "8080"]