FROM docker.io/library/fedora:latest

LABEL maintainer="ansible@local.derix.icu"
LABEL description="Proxmox VM Deployment Dev Container"

# Install base packages
RUN dnf install -y \
    python3 \
    python3-pip \
    ansible \
    git \
    openssh-clients \
    curl \
    unzip \
    gnupg2 \
    jq \
    vim \
    && dnf clean all

# Install Packer
ARG PACKER_VERSION=1.11.2
RUN curl -fsSL "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip" -o /tmp/packer.zip \
    && unzip /tmp/packer.zip -d /usr/local/bin/ \
    && rm /tmp/packer.zip \
    && packer --version

# Install Terraform
ARG TERRAFORM_VERSION=1.9.8
RUN curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -o /tmp/terraform.zip \
    && unzip /tmp/terraform.zip -d /usr/local/bin/ \
    && rm /tmp/terraform.zip \
    && terraform --version

# Install Python dependencies for Proxmox API testing
RUN pip3 install --break-system-packages proxmoxer requests urllib3

WORKDIR /workspace

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
