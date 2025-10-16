# Use the Airflow base image
FROM apache/airflow:3.0.3-python3.11

# Switch to root to install system dependencies
USER root

# Install Java (required for PySpark) and other dependencies
RUN apt-get update && \
    apt-get install -y \
        openjdk-17-jdk \
        curl \
        wget \
        procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configure JAVA_HOME
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# Switch back to the airflow user
USER airflow

# Copy requirements first to take advantage of Docker caching
COPY bci-dev-environment/requirements.txt /tmp/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r /tmp/requirements.txt

# Install connectors required for Spark access to Azure Blob
USER root
RUN JARS_DIR="/home/airflow/.local/lib/python3.11/site-packages/pyspark/jars" \
    && mkdir -p "$JARS_DIR" \
    && curl -fsSL https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-azure/3.3.6/hadoop-azure-3.3.6.jar -o "$JARS_DIR/hadoop-azure-3.3.6.jar" \
    && curl -fsSL https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-common/3.3.6/hadoop-common-3.3.6.jar -o "$JARS_DIR/hadoop-common-3.3.6.jar" \
    && curl -fsSL https://repo1.maven.org/maven2/com/microsoft/azure/azure-storage/8.6.6/azure-storage-8.6.6.jar -o "$JARS_DIR/azure-storage-8.6.6.jar" \
    && curl -fsSL https://repo1.maven.org/maven2/com/azure/azure-storage-blob/12.26.0/azure-storage-blob-12.26.0.jar -o "$JARS_DIR/azure-storage-blob-12.26.0.jar" \
    && chown airflow:root \
        "$JARS_DIR/hadoop-azure-3.3.6.jar" \
        "$JARS_DIR/hadoop-common-3.3.6.jar" \
        "$JARS_DIR/azure-storage-8.6.6.jar" \
        "$JARS_DIR/azure-storage-blob-12.26.0.jar"

# Copy DAGs and internal library code
USER airflow
COPY --chown=airflow:root bci-dags/ /opt/airflow/dags/
COPY --chown=airflow:root bci-datamart/ /opt/airflow/plugins/bci_source/

# Configure environment variables for Spark and Airflow
ENV SPARK_HOME=/home/airflow/.local/lib/python3.11/site-packages/pyspark
ENV PATH=$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin
ENV PYTHONPATH=/opt/airflow/plugins:/opt/airflow/plugins/bci_source:/opt/airflow:$SPARK_HOME/python:$PYTHONPATH

# Configure Airflow environment variables
ENV AIRFLOW__CORE__LOAD_EXAMPLES=False
ENV AIRFLOW__CORE__EXECUTOR=CeleryExecutor
ENV AIRFLOW__WEBSERVER__EXPOSE_CONFIG=True

# Create required directories
RUN mkdir -p /opt/airflow/logs /opt/airflow/data

# Default command
CMD ["airflow", "api-server"]
