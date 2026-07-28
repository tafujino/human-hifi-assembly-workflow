# Image containing the yak (https://github.com/lh3/yak) executable and
# groupxy.pl (the chrX/chrY partitioning script included in the same repository).
# Since the bioconda yak package does not include groupxy.pl, both are obtained
# by building from source.
#
# yak has not been tagged since the sexchr subcommand/groupxy.pl were added
# (the latest tag, v0.1, predates those additions and is from 2020), so a
# specific commit is pinned for reproducibility.
FROM ubuntu:22.04

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
    && rm -rf /opt/yak

WORKDIR /data
