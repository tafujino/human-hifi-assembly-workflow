#!/usr/bin/env bash
# Runs inside the mito-blast-filter image, with this directory as the working
# directory. Invoked by ../test.sh; see that script for how to run it by hand.
set -euo pipefail

failures=0

report() {
  if [[ "$1" == pass ]]; then
    printf 'ok    %s\n' "$2"
  else
    printf 'FAIL  %s\n' "$2" >&2
    failures=$((failures + 1))
  fi
}

# --- unit tests: the summary TSV must match byte for byte ---------------------
# These use hand-written BLAST output, so the expected numbers are exact and do
# not depend on the BLAST version.
for case_name in unit_merge unit_length unit_empty; do
  mito_blast_filter \
    --blast-output "${case_name}.blast.tsv" \
    --ids-out "/tmp/${case_name}.ids.txt" \
    --summary-out "/tmp/${case_name}.summary.tsv"

  if diff -u "${case_name}.expected.tsv" "/tmp/${case_name}.summary.tsv" > "/tmp/${case_name}.diff"; then
    report pass "${case_name}: summary matches"
  else
    report fail "${case_name}: summary differs"
    cat "/tmp/${case_name}.diff" >&2
  fi

  # The ID list must be exactly the contigs marked "yes" in the summary.
  awk -F'\t' 'NR > 1 && $7 == "yes" { print $1 }' "${case_name}.expected.tsv" \
    | LC_ALL=C sort > "/tmp/${case_name}.ids.want"
  LC_ALL=C sort "/tmp/${case_name}.ids.txt" > "/tmp/${case_name}.ids.got"
  if diff -u "/tmp/${case_name}.ids.want" "/tmp/${case_name}.ids.got" > "/tmp/${case_name}.ids.diff"; then
    report pass "${case_name}: ID list matches"
  else
    report fail "${case_name}: ID list differs"
    cat "/tmp/${case_name}.ids.diff" >&2
  fi
done

# --- integration test: real blastn, then the filter ---------------------------
# Only the removal decisions are asserted, not the exact covered_bp, because BLAST
# may shift an alignment boundary by a few bases between versions.
mkdir -p /tmp/blastdb
makeblastdb -in integration_subject.fa -dbtype nucl -out /tmp/blastdb/mito > /dev/null

blastn \
  -query integration_query.fa \
  -db /tmp/blastdb/mito \
  -num_threads 1 \
  -dust no \
  -soft_masking false \
  -outfmt '6 std qlen slen' \
  > /tmp/integration.blast.tsv

mito_blast_filter \
  --blast-output /tmp/integration.blast.tsv \
  --ids-out /tmp/integration.ids.txt \
  --summary-out /tmp/integration.summary.tsv

LC_ALL=C sort integration_expected_ids.txt > /tmp/integration.ids.want
LC_ALL=C sort /tmp/integration.ids.txt > /tmp/integration.ids.got
if diff -u /tmp/integration.ids.want /tmp/integration.ids.got > /tmp/integration.ids.diff; then
  report pass "integration: flagged contigs match"
else
  report fail "integration: flagged contigs differ"
  cat /tmp/integration.summary.tsv >&2
  cat /tmp/integration.ids.diff >&2
fi

# A contig with no HSP at all must not appear in the summary.
if grep -q '^autosome' /tmp/integration.summary.tsv; then
  report fail "integration: a contig without any HSP leaked into the summary"
else
  report pass "integration: contigs without an HSP are absent from the summary"
fi

# --- argument handling -------------------------------------------------------
if mito_blast_filter --blast-output /tmp/integration.blast.tsv --ids-out /tmp/x 2>/dev/null; then
  report fail "usage: a missing --summary-out should be rejected"
else
  report pass "usage: a missing --summary-out is rejected"
fi

if mito_blast_filter --blast-output /nonexistent --ids-out /tmp/x --summary-out /tmp/y 2>/dev/null; then
  report fail "usage: a missing BLAST output file should be rejected"
else
  report pass "usage: a missing BLAST output file is rejected"
fi

# Wrong -outfmt (fewer than 14 columns) must fail loudly rather than divide by zero.
cut -f1-12 unit_merge.blast.tsv > /tmp/too_few_columns.tsv
if mito_blast_filter --blast-output /tmp/too_few_columns.tsv \
     --ids-out /tmp/x --summary-out /tmp/y 2>/dev/null; then
  report fail "usage: a 12-column BLAST output should be rejected"
else
  report pass "usage: a 12-column BLAST output is rejected"
fi

if [[ "$failures" -gt 0 ]]; then
  printf '\n%d test(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall tests passed\n'
