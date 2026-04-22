FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Copy the initialization script
COPY on-create.sh /tmp/on-create.sh

# Grant execution permissions and run the script
# During the build process, this runs as root, which is ideal for global installations
RUN chmod +x /tmp/on-create.sh && \
    /tmp/on-create.sh && \
    rm /tmp/on-create.sh
