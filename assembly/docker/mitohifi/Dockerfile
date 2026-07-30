# Image that runs MitoHiFi (https://github.com/marcelauliano/MitoHiFi).
#
# The official image is only published under the moving ":master" tag, which is
# unsuitable for reproducible pipeline runs. MitoHiFi's own dependency stack
# (MitoFinder, cdhit, hifiasm, minimap2, two separate conda environments, and
# reference HMM databases) is large and fragile to rebuild from scratch, so
# instead of reimplementing it, this image is built on top of the upstream
# "mitohifi-base" image, which is published under a version-pinned tag that
# matches a specific MitoHiFi release tag. Only the MitoHiFi source itself
# (pinned to a specific git tag) is added on top, mirroring what upstream's own
# environment/code/Dockerfile does for its ":master" image.
#
# The sed calls below modify GPL-3.0-or-later files, and this image is published, so
# GPL-3 section 5(a) requires the modifications to be stated. They are recorded in the
# NOTICE file in this directory, which is copied into the image. Keep NOTICE in step
# with any change to the RUN block.
# ghcr.io/marcelauliano/mitohifi-base:b3.2.3
FROM ghcr.io/marcelauliano/mitohifi-base@sha256:017b4b77ea54bfe0cc829469b04c1a530cad0d5397832fc719e00a2ca51fe14b

ARG MITOHIFI_TAG=v3.2.3

RUN git clone --branch "${MITOHIFI_TAG}" --depth 1 https://github.com/marcelauliano/MitoHiFi.git /opt/MitoHiFi \
    && cd /opt/MitoHiFi/src \
    && chmod +x *.py \
    && sed -i '1i#!/usr/bin/env python3' mitohifi.py findFrameShifts.py fixContigHeaders.py \
    && sed -i '1 s/python\>/python3/' *.py \
    && sed -i 's/"python2",\s//' parallel_annotation_mitos.py \
    && sed -i 's/MITOS\/data/\/opt\/databases/' parallel_annotation_mitos.py

COPY NOTICE /opt/MitoHiFi/NOTICE.modifications

ENV PATH=/opt/wrappers:/opt/cdhit/:/opt/hifiasm-0.16.1/:/opt/MitoHiFi/src/:/opt/MitoFinder/:/opt/minimap2-2.24_x64-linux/:${PATH}

WORKDIR /data
