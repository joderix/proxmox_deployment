FROM docker.io/library/fedora:latest

LABEL maintainer="ansible@local.derix.icu"
LABEL description="Proxmox VM Deployment Dev Container"

# Install base packages
RUN dnf install -y \
    python3 \
    python3-pip \
    git \
    openssh-clients \
    curl \
    unzip \
    gnupg2 \
    jq \
    vim \
    && dnf clean all

# Install Packer
ARG PACKER_VERSION=1.15.1
RUN curl -fsSL "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip" -o /tmp/packer.zip \
    && unzip /tmp/packer.zip -d /usr/local/bin/ \
    && rm /tmp/packer.zip \
    && packer --version

# Install Terraform using HashiCorp release artifact with retries
ARG TERRAFORM_VERSION=1.14.8
RUN curl -fSL --retry 5 --retry-delay 3 --retry-connrefused "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -o /tmp/terraform.zip \
    && unzip -o /tmp/terraform.zip -d /usr/local/bin/ \
    && rm -f /tmp/terraform.zip \
    && terraform --version

# Install Python dependencies for Proxmox API testing, Ansible, and linting
RUN pip3 install --break-system-packages ansible ansible-dev-tools proxmoxer requests urllib3

WORKDIR /workspace

# Copy entrypoint from repo (single source of truth, includes HTTP IP detection)
COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
