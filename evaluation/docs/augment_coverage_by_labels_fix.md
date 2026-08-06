# augmentCoverageByLabels memory crash (fixed)

`augmentCoverageByLabels` is the HMM-Flagger task that merges truth/prediction labels into
the coverage file (`workflows/imports/flagger`'s `augment_coverage_by_labels` C program). On
large, highly fragmented genome assemblies it used to fail with a `malloc`/`realloc` failure,
occasionally after running for a long time, in a way that looked non-deterministic (varying
by node, time of day, thread count...). **This is fixed** as of this fork's
`fix-augment-coverage-by-labels-crash` branch and requires no action from users of this
project's workflows -- the fix is already the default.

## Root cause

The C program builds an internal list of "chunks" (contiguous stretches of a contig, up to
40 Mb each) before it starts reading the actual coverage data. For historical reasons, chunk
construction also allocated three integer arrays per chunk -- scratch space meant for a
*window*-based statistic that `augmentCoverageByLabels` never actually uses -- but sized off
the *chunk* length (40,000,000) instead of a real window size (which would be a few thousand
elements). That's 3 × 160 MB of unused memory per chunk.

For a genome with a handful of large contigs this goes unnoticed (a few GB). But real
diploid assemblies typically have hundreds of small, fragmented contigs (unplaced sequence,
haplotype-specific tigs, etc.) in addition to the main chromosome-scale ones, and each one
still gets its own full-size, unused allocation. On a real ~500-chunk human genome this added
up to roughly **230+ GB of reserved (but never touched) virtual memory** -- routinely enough
to exceed the memory an HPC scheduler's `s_vmem`/`ulimit -v`-style limit will allow, even
though actual resident memory use stayed under 10 GB throughout. Environments that don't
enforce a virtual-memory ceiling this way (e.g. a bare VM under Docker, which only cares
about memory actually touched) never hit this at all, which is why the crash looked
environment- and timing-dependent rather than deterministic.

## Fix

Fixed directly in this fork rather than worked around from this project's WDL: the unused
allocation is now skipped entirely for `augmentCoverageByLabels`'s call path (other tasks
that genuinely use per-window buffers with a real window size, like `hmmFlagger`, are
unaffected). On the same ~500-chunk genome, peak memory dropped from ~230 GB to ~8 GB.
Verified to produce byte-identical output before and after the fix, at multiple input sizes
including the full untruncated genome, and independent of thread count.

Two related bugs in the same code path were fixed alongside it (a memory leak in the output
writer, and per-line allocation churn in the coverage-file parser); neither was the cause of
the crash on its own, but both are cleaned up as good practice.

## For users

Nothing to configure -- `augmentCoverageByLabels`'s Docker image and memory default already
point at the fixed build. If you ever see a similar `malloc failed`/out-of-memory error from
a flagger C program on an unusually fragmented assembly, the contig/chunk count (visible in
the task's own stderr log, `Parsing cov: submitted job for parsing chunk index:N/M ...`) is
the first thing worth checking -- a chunk count in the hundreds, not the size of the input
file, was the actual driver of memory use here.
