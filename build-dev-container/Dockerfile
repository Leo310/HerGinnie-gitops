FROM debian:11-slim

ENV TERM xterm-256color

ARG uid
ARG gid

# Home setup
ARG container_home="/home"
ENV HOME=${container_home}
RUN mkdir -p ${HOME}; chown ${uid}:${gid} ${HOME}

# install system applications
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    wget \
    python3-pip \
    jq \
    curl \
    vim \
    less
    # nodejs \
    # npm \
    # groff

# install pyq
RUN pip3 install yq

# Versions
ARG helm_version="3.6.0"
ARG kubectl_version="v1.21.4"
ARG kubeseal_version="0.17.1"
# ARG go_version="go1.16.4.linux-amd64"
ARG kustomize_version="v4.2.0"
ARG argocd_version="v2.1.7"


# install kubectl
RUN curl -LO "https://storage.googleapis.com/kubernetes-release/release/${kubectl_version}/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# install kubeseal
RUN curl -LO "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${kubeseal_version}/kubeseal-${kubeseal_version}-linux-amd64.tar.gz" && \
    tar zxvf kubeseal-${kubeseal_version}-linux-amd64.tar.gz && \
    mv kubeseal /usr/local/bin

# install helm
RUN wget "https://get.helm.sh/helm-v${helm_version}-linux-amd64.tar.gz" && \
    tar -zxvf helm-v${helm_version}-linux-amd64.tar.gz && \
    mv linux-amd64/helm /usr/local/bin/helm && \
    rm helm-v${helm_version}-linux-amd64.tar.gz && \
    rm -rf linux-amd64

# install kustomize
RUN curl -LO "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/${kustomize_version}/kustomize_${kustomize_version}_linux_amd64.tar.gz" && \
    tar -zxvf kustomize_${kustomize_version}_linux_amd64.tar.gz && \
    mv kustomize /usr/local/bin/kustomize && \
    rm kustomize_${kustomize_version}_linux_amd64.tar.gz

# install argocd cli
RUN curl -sLO "https://github.com/argoproj/argo-cd/releases/download/$argocd_version/argocd-linux-amd64"
RUN chmod +x argocd-linux-amd64
RUN mv ./argocd-linux-amd64 /usr/local/bin/argocd

# install cloudflared
RUN mkdir -p --mode=0755 /usr/share/keyrings
RUN curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
RUN echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared bullseye main' | tee /etc/apt/sources.list.d/cloudflared.list
RUN apt-get update && apt-get install cloudflared

# install go
# RUN wget "https://golang.org/dl/${GO_VERSION}.tar.gz" -O "${GO_VERSION}.tar.gz"
# RUN tar -C /usr/local -xzf "${GO_VERSION}.tar.gz"
# RUN rm "${GO_VERSION}.tar.gz"
# ENV PATH=$PATH:/usr/local/go/bin

# everything before this command with root user now with specified user, useradd gives us a name
ARG username
RUN useradd -r -u $uid $username
USER ${username}:${gid}

# fix this issue for kubectl https://stackoverflow.com/questions/66339069/kubectl-get-all-command-return-throttling-request
RUN mkdir -p $HOME/.kube/cache
RUN chmod 777 -R $HOME/.kube/cache
