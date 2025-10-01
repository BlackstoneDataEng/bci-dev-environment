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

# Add GitHub to known hosts to avoid SSH prompt
RUN mkdir -p /root/.ssh && \
    ssh-keyscan -t rsa github.com >> /root/.ssh/known_hosts

RUN mkdir -p /tmp/repos /opt/airflow/dags /opt/airflow/plugins

# Install Azure CLI for runtime key retrieval
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Accept Azure credentials as build arguments
ARG AZURE_CLIENT_ID
ARG AZURE_CLIENT_SECRET
ARG AZURE_TENANT_ID

# Fetch keys from Azure Key Vault and fix formatting (inline commands)
RUN az login --service-principal -u ${AZURE_CLIENT_ID} -p ${AZURE_CLIENT_SECRET} --tenant ${AZURE_TENANT_ID} && \
    az keyvault secret download --vault-name bci-keyss --name bci-git-key --file /tmp/ssh-key-plugins.raw && \
    az keyvault secret download --vault-name bci-keyss --name bci-git-keys-dags --file /tmp/ssh-key-dags.raw && \
    # Debug: Check raw key format \
    echo "=== Raw key plugins format ===" && head -3 /tmp/ssh-key-plugins.raw && \
    echo "=== Raw key dags format ===" && head -3 /tmp/ssh-key-dags.raw && \
    # Process keys: handle both literal \n and actual newlines, remove quotes, add headers \
    for rawkey in /tmp/ssh-key-plugins.raw /tmp/ssh-key-dags.raw; do \
        outkey=${rawkey%.raw} && \
        # Remove surrounding quotes, spaces, and newlines to get clean base64 \
        keydata=$(sed -e 's/^"//' -e 's/"$//' -e 's/\\n//g' -e 's/\r$//' -e 's/ //g' "$rawkey") && \
        # Add proper SSH key headers and format with proper line wrapping \
        echo "-----BEGIN RSA PRIVATE KEY-----" > "$outkey" && \
        echo "$keydata" | fold -w 64 >> "$outkey" && \
        echo "-----END RSA PRIVATE KEY-----" >> "$outkey" && \
        chmod 600 "$outkey" && \
        echo "=== Processed ${outkey} ===" && head -3 "$outkey" && \
        # Validate key format \
        if ! ssh-keygen -l -f "$outkey" >/dev/null 2>&1; then \
            echo "ERROR: Invalid SSH key format in $outkey" && exit 1; \
        fi; \
    done

# Add SSH keys to ssh-agent and clone repos
RUN eval "$(ssh-agent -s)" && \
    ssh-add /tmp/ssh-key-plugins && \
    git clone git@github.com:BlackstoneDataEng/bci-datamart.git /tmp/repos/plugins/bci_source && \
    ssh-add -D && \
    eval "$(ssh-agent -s)" && \
    ssh-add /tmp/ssh-key-dags && \
    git clone git@github.com:BlackstoneDataEng/bci-dags.git /tmp/repos/dags && \
    ssh-add -D

# Clean up SSH keys for security
RUN rm -f /tmp/ssh-key-plugins /tmp/ssh-key-dags /tmp/ssh-key-plugins.raw /tmp/ssh-key-dags.raw

# Verify Java installation
RUN java -version && echo "JAVA_HOME is set to: $JAVA_HOME"

# Copy repositories to airflow directories
RUN cp -r /tmp/repos/dags/* /opt/airflow/dags/ && \
    cp -r /tmp/repos/plugins/bci_source /opt/airflow/plugins/bci_source && \
    chown -R airflow:root /opt/airflow/dags /opt/airflow/plugins/bci_source

# Add plugins folder to PYTHONPATH so DAGs can import bci_source modules
ENV PYTHONPATH="/opt/airflow/plugins/bci_source:${PYTHONPATH}"

USER airflow
WORKDIR /opt/airflow

# Copy requirements and install python dependencies if exists
COPY requirements.txt* ./
RUN if [ -f requirements.txt ]; then pip install -r requirements.txt; fi

# Copy any other local files (optional)
COPY --chown=airflow:root . .

CMD ["webserver"]