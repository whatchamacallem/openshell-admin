# Dockerfile — seafox sandbox image: the OpenShell base + a baked-in toolchain.
#
# Built by ./build-image.sh (and ./create-sandbox.sh) into the local Docker
# daemon, then used via `openshell sandbox create --from`. apt runs here at
# BUILD time as root — no sudo password is needed, and the packages survive
# sandbox recreates. Edit the package list in packages.txt, not here.
ARG BASE=ghcr.io/nvidia/openshell-community/sandboxes/base:latest
FROM ${BASE}

USER root

# packages.txt is one package per line; '#' comments and blanks are stripped.
COPY packages.txt /tmp/packages.txt
RUN apt-get update \
    && grep -vE '^\s*(#|$)' /tmp/packages.txt | xargs \
       env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* /tmp/packages.txt
