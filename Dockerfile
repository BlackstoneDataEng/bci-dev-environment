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

# Install Azure CLI for runtime key retrieval
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Accept Azure credentials as build arguments
ARG AZURE_CLIENT_ID
ARG AZURE_CLIENT_SECRET
ARG AZURE_TENANT_ID

# Create script to fetch keys from Azure Key Vault at runtime
RUN echo '#!/bin/bash' > /usr/local/bin/fetch-keys.sh && \
    echo 'set -e' >> /usr/local/bin/fetch-keys.sh && \
    echo 'echo "Fetching SSH keys from Azure Key Vault..."' >> /usr/local/bin/fetch-keys.sh && \
    echo "az login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID}" >> /usr/local/bin/fetch-keys.sh && \
    echo 'az keyvault secret download --vault-name bci-keyss --name bci-git-key --file /tmp/ssh-key-plugins.raw' >> /usr/local/bin/fetch-keys.sh && \
    echo 'az keyvault secret download --vault-name bci-keyss --name bci-git-keys-dags --file /tmp/ssh-key-dags.raw' >> /usr/local/bin/fetch-keys.sh && \
    echo 'echo "Raw key files downloaded, processing formatting..."' >> /usr/local/bin/fetch-keys.sh && \
    echo 'echo "Raw plugins key content:" && cat /tmp/ssh-key-plugins.raw | head -2' >> /usr/local/bin/fetch-keys.sh && \
    echo 'echo "Raw dags key content:" && cat /tmp/ssh-key-dags.raw | head -2' >> /usr/local/bin/fetch-keys.sh && \
    echo 'python3 -c "' >> /usr/local/bin/fetch-keys.sh && \
    echo 'import re' >> /usr/local/bin/fetch-keys.sh && \
    echo 'for fname in [\"/tmp/ssh-key-plugins\", \"/tmp/ssh-key-dags\"]:' >> /usr/local/bin/fetch-keys.sh && \
    echo '    with open(fname + \".raw\", \"r\") as f:' >> /usr/local/bin/fetch-keys.sh && \
    echo '        content = f.read()' >> /usr/local/bin/fetch-keys.sh && \
    echo '    content = content.replace(\"\\\\n\", \"\\n\")' >> /usr/local/bin/fetch-keys.sh && \
    echo '    content = re.sub(r\"\\r\\n?\", \"\\n\", content)' >> /usr/local/bin/fetch-keys.sh && \
    echo '    if not content.endswith(\"\\n\"):' >> /usr/local/bin/fetch-keys.sh && \
    echo '        content += \"\\n\"' >> /usr/local/bin/fetch-keys.sh && \
    echo '    with open(fname, \"w\") as f:' >> /usr/local/bin/fetch-keys.sh && \
    echo '        f.write(content)' >> /usr/local/bin/fetch-keys.sh && \
    echo '"' >> /usr/local/bin/fetch-keys.sh && \
    echo 'chmod 600 /tmp/ssh-key-plugins /tmp/ssh-key-dags' >> /usr/local/bin/fetch-keys.sh && \
    echo 'echo "SSH keys processed successfully"' >> /usr/local/bin/fetch-keys.sh && \
    echo 'echo "Plugins key first line: $(head -1 /tmp/ssh-key-plugins)"' >> /usr/local/bin/fetch-keys.sh && \
    echo 'echo "DAGs key first line: $(head -1 /tmp/ssh-key-dags)"' >> /usr/local/bin/fetch-keys.sh && \
    echo 'echo "Testing SSH key validity..."' >> /usr/local/bin/fetch-keys.sh && \
    echo 'ssh-keygen -l -f /tmp/ssh-key-plugins || echo "WARNING: Plugins key failed validation"' >> /usr/local/bin/fetch-keys.sh && \
    echo 'ssh-keygen -l -f /tmp/ssh-key-dags || echo "WARNING: DAGs key failed validation"' >> /usr/local/bin/fetch-keys.sh && \
    echo 'rm -f /tmp/ssh-key-plugins.raw /tmp/ssh-key-dags.raw' >> /usr/local/bin/fetch-keys.sh && \
    chmod +x /usr/local/bin/fetch-keys.sh

# Fetch keys and clone repositories
RUN /usr/local/bin/fetch-keys.sh

# Debug: Show what the key processing produced
RUN echo "=== SSH KEY DEBUG INFO ===" && \
    echo "Checking if keys exist:" && \
    ls -la /tmp/ssh-key-* && \
    echo "Key file permissions:" && \
    stat /tmp/ssh-key-plugins /tmp/ssh-key-dags && \
    echo "Key fingerprints (if valid):" && \
    ssh-keygen -l -f /tmp/ssh-key-plugins 2>&1 || echo "Plugins key invalid" && \
    ssh-keygen -l -f /tmp/ssh-key-dags 2>&1 || echo "DAGs key invalid" && \
    echo "First few lines of each key:" && \
    echo "=== PLUGINS KEY ===" && \
    head -3 /tmp/ssh-key-plugins && \
    echo "=== DAGS KEY ===" && \
    head -3 /tmp/ssh-key-dags && \
    echo "=== END DEBUG ==="

# Add cache buster and clone plugins repository using SSH agent
ARG CACHE_BUST=1
RUN echo "=== Starting plugins repo clone with SSH agent (CACHE_BUST=$CACHE_BUST) ===" && \
    echo "Current time: $(date)" && \
    echo "Starting SSH agent and adding key..." && \
    eval "$(ssh-agent -s)" && \
    ssh-add /tmp/ssh-key-plugins && \
    echo "Cloning plugins repository..." && \
    git clone git@github.com:BlackstoneDataEng/bci-datamart.git /tmp/repos/plugins/bci_source && \
    echo "=== Plugins repo clone completed ===" && \
    ls -la /tmp/repos/plugins/bci_source

# Clone dags repository using SSH agent
RUN echo "=== Starting dags repo clone with SSH agent ===" && \
    echo "Starting SSH agent and adding key..." && \
    eval "$(ssh-agent -s)" && \
    ssh-add /tmp/ssh-key-dags && \
    echo "Cloning dags repository..." && \
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
    ls -la /tmp/repos/plugins/bci_source/ 2>/dev/null || echo "plugins not found"

# Copy repositories to app directories
RUN if [ -d /tmp/repos/dags ]; then \
        echo "Copying dags repository..." && \
        cp -r /tmp/repos/dags/* /opt/airflow/dags/ && \
        echo "Dags copied successfully"; \
    else \
        echo "WARNING: No dags repository found to copy"; \
    fi && \
    if [ -d /tmp/repos/plugins/bci_source ]; then \
        echo "Copying plugins repository..." && \
        cp -r /tmp/repos/plugins/bci_source /opt/airflow/plugins/bci_source && \
        echo "Plugins copied successfully"; \
    else \
        echo "WARNING: No plugins repository found to copy"; \
    fi && \
    chown -R airflow:root /opt/airflow/dags /opt/airflow/plugins/bci_source

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