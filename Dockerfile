# Container image that runs your code
FROM mambaorg/micromamba
LABEL org.opencontainers.image.authors="Yan Hui <me@yanh.org>"
ADD . /tmp/repo
WORKDIR /tmp/repo
ENV LANG C.UTF-8
ENV SHELL /bin/bash
USER root 

ENV APT_PKGS bzip2 ca-certificates curl wget gnupg2 squashfs-tools build-essential git nano 

RUN apt-get update \
    && apt-get install -y --no-install-recommends ${APT_PKGS} \
    && apt-get clean \
    && rm -rf /var/lib/apt /var/lib/dpkg /var/lib/cache /var/lib/log

RUN micromamba env create -n env1 -f envs/env1.yaml \
    && micromamba env create -n env2 -f envs/env2.yaml \
    && eval "$(micromamba shell hook -s bash)" \
    && micromamba clean --all --yes

ENV PATH /opt/conda/envs/env1/bin:/opt/conda/envs/env2/bin:${PATH}

WORKDIR /home
