# CHM13 reference (flagger projection / asmgene)

## Obtaining the reference

`projection_reference_fasta` is T2T-CHM13v2.0's analysis-set FASTA, used both as the
HMM-Flagger annotation-projection reference and as asmgene's reference-side mapping target
(the same file the vendored flagger workflow's own README lists for `projectionReferenceFasta`).

```sh
curl -O https://s3-us-west-2.amazonaws.com/human-pangenomics/T2T/CHM13/assemblies/analysis_set/chm13v2.0.fa.gz
```

No need to decompress: both minimap2 (asmgene) and the vendored flagger workflow read gzipped
FASTA natively (the same way `reference_cdna_fasta` is normally supplied as a `.fa.gz`; see
[cdna_reference.md](cdna_reference.md)).

The CHM13 annotation BEDs used alongside it (`bias_annotations_bed_array_to_be_projected`,
`cntr_bed_to_be_projected`, `sd_bed_to_be_projected`, `sex_bed_to_be_projected`,
`annotations_bed_array_to_be_projected`) do not need a separate download: they are vendored
inside the `workflows/imports/flagger` git submodule under `misc/`, already pinned to this
project's flagger version (see [example_inputs.md](example_inputs.md) for the real paths).
Only the CHM13 FASTA itself is too large to vendor and must be fetched separately.
