# Image that decides which assembly contigs are mitochondrial from BLAST output.
#
# Built on top of the BLAST biocontainer so that a single WDL task can run makeblastdb,
# blastn and the filter without pulling two images. The base image already provides
# bash, awk, sort and gunzip, so nothing has to be installed.
#
# NOTE: unlike the rest of this repository, which is MIT, the contents of this directory
# are licensed under GPL-3.0-or-later. See LICENSE and NOTICE for why.
# quay.io/biocontainers/blast:2.17.0--h66d330f_0
FROM quay.io/biocontainers/blast@sha256:78e8ebf231ce498b0015100a891693ef2acbbf7df60b33299517ca2b4891e567

COPY mito_blast_filter /usr/local/bin/mito_blast_filter
COPY LICENSE NOTICE /usr/local/share/licenses/mito-blast-filter/

RUN chmod 0755 /usr/local/bin/mito_blast_filter

WORKDIR /data
