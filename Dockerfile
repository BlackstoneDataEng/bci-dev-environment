FROM apache/airflow:3.0.3
USER root

# Install system dependencies including Java, Git, and SSH client
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        default-jdk \
        ant \
        git \
        openssh-client \
        curl \
        wget && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set JAVA_HOME environment variable and fix PATH
ENV JAVA_HOME=/usr/lib/jvm/default-java/
ENV PATH=/home/airflow/.local/bin:$PATH:$JAVA_HOME/bin

# Add GitHub/GitLab/Bitbucket to known hosts to avoid SSH prompt
RUN mkdir -p /root/.ssh && \
    ssh-keyscan -t rsa github.com >> /root/.ssh/known_hosts
RUN mkdir -p /tmp/repos /opt/airflow/dags /opt/airflow/plugins

# Copy SSH keys and set permissions
COPY bci-git-key.pem /tmp/ssh-key-plugins
COPY bci-git-key-dags.pem /tmp/ssh-key-dags
RUN chmod 600 /tmp/ssh-key-plugins /tmp/ssh-key-dags

# Add cache buster and clone plugins repository
ARG CACHE_BUST=1
RUN echo "=== Starting plugins repo clone (CACHE_BUST=$CACHE_BUST) ===" && \
    echo "Current time: $(date)" && \
    echo "Cloning plugins repository..." && \
    GIT_SSH_COMMAND="ssh -i /tmp/ssh-key-plugins -o UserKnownHostsFile=/root/.ssh/known_hosts -o StrictHostKeyChecking=no" \
    git clone git@github.com:BlackstoneDataEng/bci-datamart.git /tmp/repos/plugins && \
    echo "=== Plugins repo clone completed ===" && \
    ls -la /tmp/repos/plugins

# Clone dags repository
RUN echo "=== Starting dags repo clone ===" && \
    echo "Cloning dags repository..." && \
    GIT_SSH_COMMAND="ssh -i /tmp/ssh-key-dags -o UserKnownHostsFile=/root/.ssh/known_hosts -o StrictHostKeyChecking=no" \
    git clone git@github.com:BlackstoneDataEng/bci-dags.git /tmp/repos/dags && \
    echo "=== Dags repo clone completed ===" && \
    ls -la /tmp/repos/dags

# Clean up SSH keys for security
RUN rm -f /tmp/ssh-key-plugins /tmp/ssh-key-dags

# Verify Java installation
RUN java -version && echo "JAVA_HOME is set to: $JAVA_HOME"

# Debug: Show what was cloned
RUN echo "=== FINAL REPOSITORY CHECK ===" && \
    echo "Contents of /tmp/repos:" && \
    ls -la /tmp/repos/ && \
    echo "Contents of /tmp/repos/dags (if exists):" && \
    ls -la /tmp/repos/dags/ 2>/dev/null || echo "dags not found" && \
    echo "Contents of /tmp/repos/plugins (if exists):" && \
    ls -la /tmp/repos/plugins/ 2>/dev/null || echo "plugins not found"

# Copy repositories to app directories
RUN if [ -d /tmp/repos/dags ]; then \
        echo "Copying dags repository..." && \
        cp -r /tmp/repos/dags/* /opt/airflow/dags/ && \
        echo "Dags copied successfully"; \
    else \
        echo "WARNING: No dags repository found to copy"; \
    fi && \
    if [ -d /tmp/repos/plugins ]; then \
        echo "Copying plugins repository..." && \
        cp -r /tmp/repos/plugins/* /opt/airflow/plugins/ && \
        echo "Plugins copied successfully"; \
    else \
        echo "WARNING: No plugins repository found to copy"; \
    fi && \
    chown -R airflow:root /opt/airflow/dags /opt/airflow/plugins

# Switch back to airflow user
USER airflow

# Set working directory
WORKDIR /opt/airflow

# Copy requirements file if it exists
COPY requirements.txt* ./

# Install Python dependencies
RUN if [ -f requirements.txt ]; then pip install -r requirements.txt; fi

# Copy any local files (optional)
COPY --chown=airflow:root . .

USER airflow

CMD ["webserver"]