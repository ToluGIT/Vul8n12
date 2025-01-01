# Build stage for Java compilation
FROM eclipse-temurin:17.0.11_9-jdk-alpine AS builder
WORKDIR /build
COPY <<EOF /build/VulnerableApp.java
public class VulnerableApp {
    public static void main(String[] args) {
        if (args.length > 0) {
            try {
                // Command Injection vulnerability
                Runtime.getRuntime().exec(args[0]);
                
                // SQL Injection vulnerability
                String query = "SELECT * FROM users WHERE id = " + args[0];
                
                // Path Traversal vulnerability
                java.io.File file = new java.io.File("/tmp/" + args[0]);
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }
}
EOF
RUN javac VulnerableApp.java

# Final stage
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

# Add dummy secrets and environment variables
ENV AWS_ACCESS_KEY_ID="AKIA2OGXXXXXXXXXXXXXX" \
    AWS_SECRET_ACCESS_KEY="pwZ1xXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" \
    DB_PASSWORD="super_secret_password123!" \
    API_KEY="sk-1234567890abcdefghijklmnopqrstuvwxyz"

# Install required packages based on attack script needs
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core tools
    curl \
    wget \
    openjdk-17-jre-headless \
    # Network tools
    netcat-traditional \
    net-tools \
    iproute2 \
    # Process and debugging tools
    procps \
    strace \
    ltrace \
    gdb \
    # File and system tools
    sudo \
    findutils \
    lsof \
    # SSH related
    openssh-client \
    # Additional dependencies needed by test scripts
    cron \
    git \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create working directory and add test files
WORKDIR /security-tests

# Add dummy SSH keys and AWS credentials
RUN mkdir -p /root/.ssh /root/.aws && \
    echo "-----BEGIN OPENSSH PRIVATE KEY-----\n\
MIIEpAIBAAKCAQEA1234567890abcdefghijklmnopqrstuvwxyz\n\
ThisIsADummyKeyForTestingPurposesOnly1234567890abcdef\n\
-----END OPENSSH PRIVATE KEY-----" > /root/.ssh/id_rsa && \
    chmod 600 /root/.ssh/id_rsa && \
    echo "[default]\n\
aws_access_key_id = AKIA2OGXXXXXXXXXXXXXX\n\
aws_secret_access_key = pwZ1xXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" > /root/.aws/credentials

# Copy compiled Java application from builder
RUN mkdir -p /security-tests/java
COPY --from=builder /build/VulnerableApp.class /security-tests/java/

# Add configuration files with secrets
RUN echo "spring.datasource.url=jdbc:mysql://production.server:3306/prod_db\n\
spring.datasource.password=super_secret_password123!" > /security-tests/application.properties && \
    echo "POSTGRES_PASSWORD=db_password_123\n\
STRIPE_SECRET_KEY=sk_live_XXXXXXXXXXXXXXXXXXXXXXXXXX" > /security-tests/.env

# Add healthcheck script
RUN echo '#!/bin/bash\n\
echo "Security testing base image is ready"\n\
echo "Installed tools:"\n\
echo "----------------"\n\
for cmd in curl wget java strace ltrace gdb nc ss netstat lsof sudo find ssh git cron; do\n\
    if command -v $cmd &> /dev/null; then\n\
        echo "✓ $cmd"\n\
    else\n\
        echo "✗ $cmd"\n\
    fi\n\
done\n\
\n\
echo -e "\nSystem Information:"\n\
echo "--------------------"\n\
uname -a\n\
\n\
echo -e "\nTest files:"\n\
echo "----------"\n\
ls -la /security-tests/java/VulnerableApp.class\n\
ls -la /root/.aws/credentials\n\
ls -la /security-tests/.env' > /security-tests/healthcheck.sh && \
    chmod +x /security-tests/healthcheck.sh

ENTRYPOINT ["/bin/bash"]
CMD ["-c", "/security-tests/healthcheck.sh"]
