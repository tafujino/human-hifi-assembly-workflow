# Image containing the yak (https://github.com/lh3/yak) executable and
# groupxy.pl (the chrX/chrY partitioning script included in the same repository).
# Since the bioconda yak package does not include groupxy.pl, both are obtained
# by building from source.
#
# yak has not been tagged since the sexchr subcommand/groupxy.pl were added
# (the latest tag, v0.1, predates those additions and is from 2020), so a
# specific commit is pinned for reproducibility.
#
# yak is MIT-licensed (Copyright (c) 2019- Dana-Farber Cancer Institute). Since this
# image is published, its licence text is kept under /usr/local/share/licenses/yak/
# rather than being discarded together with the build tree.
# ubuntu:22.04
FROM ubuntu@sha256:0e0a0fc6d18feda9db1590da249ac93e8d5abfea8f4c3c0c849ce512b5ef8982

ARG YAK_COMMIT=ef033d720e229593b32ad454af14ccea2120ec13

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      zlib1g-dev \
      ca-certificates \
      git \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/lh3/yak.git /opt/yak \
    && git -C /opt/yak checkout "${YAK_COMMIT}" \
    && make -C /opt/yak \
    && install -m 0755 /opt/yak/yak /usr/local/bin/yak \
    && install -m 0755 /opt/yak/groupxy.pl /usr/local/bin/groupxy.pl \
    && install -D -m 0644 /opt/yak/LICENSE.txt /usr/local/share/licenses/yak/LICENSE.txt \
    && rm -rf /opt/yak

WORKDIR /data
