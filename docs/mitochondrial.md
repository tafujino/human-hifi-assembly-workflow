# Mitochondrial reference and removal

## Obtaining the reference

The human rCRS, `NC_012920.1`, becomes `mito_reference_fasta` and `mito_reference_gb`:

```sh
E="https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"

curl -s "$E?db=nuccore&id=NC_012920.1&rettype=fasta&retmode=text" -o rCRS.fasta
curl -s "$E?db=nuccore&id=NC_012920.1&rettype=gb&retmode=text"    -o rCRS.gb
```

## What mitochondrial removal does and does not remove

`mitohifi_assembly.wdl` assembles the mitogenome from the trimmed HiFi reads, and
`mito_contig_removal.wdl` removes predominantly mitochondrial contigs from the two nuclear
haplotypes. A contig is removed when all three of these hold:

```
contig_len                     <  subject_len * max_subject_multiple   (default 10)
contig_len * 100 / subject_len >  min_contig_perc                      (default 80)
covered_bp  * 100 / contig_len >  min_coverage_perc                    (default 70)
```

`covered_bp` counts the contig bases covered by at least one BLAST HSP, computed by
merging overlapping query intervals. All three thresholds are workflow inputs. The subject
is the sample's own assembled mitogenome where one was produced, and the supplied
reference otherwise.

### Two deliberate omissions

Both are policy choices, not oversights, and both follow the Human Pangenome Project's
`findMitoContigs.wdl`:

* **NUMTs are not removed.** mtDNA embedded in a large nuclear contig is genuine nuclear
  sequence. Such a contig covers only a negligible fraction of its length with
  mitochondrial matches, so the coverage threshold excludes it.
* **Short mitochondrial fragments are not removed.** Anything shorter than 80% of the
  subject (~13.3 kb against the rCRS) is kept however purely mitochondrial it looks,
  because deleting real nuclear sequence is a worse error than leaving a redundant
  fragment — especially as the assembled mitogenome is delivered separately.

### One known miss

A contig that is entirely mitochondrial but longer than `max_subject_multiple` times the
subject (~165.7 kb against the rCRS) is kept, because the length ceiling is applied
irrespective of coverage. Since mtDNA sits at extreme copy number, hifiasm can emit such a
contig as a long tandem concatemer.

The ceiling exists as a proxy for excluding NUMTs, a job the coverage criterion now does
directly and better, so for this workflow it mostly just loses recall. It is kept at HPP's
value for comparability; raise `max_subject_multiple` if you would rather remove these.

### Removal is whole-contig

A removed contig is dropped in its entirety, so a contig at, say, 72% coverage takes its
remaining 28% of non-mitochondrial sequence with it. Nothing is trimmed or split.

`hap1_mito_blast_summary` / `hap2_mito_blast_summary` list every contig with a BLAST hit,
removed or not, together with its length, covered bases and coverage percentage. A
`removed=yes` row whose `coverage_perc` is well below 100 is where sequence was discarded
as collateral; raising `min_coverage_perc` makes that rarer.

### Where the details are

`workflows/mito_contig_removal.wdl` documents the criteria and their provenance at the top
of the file. `docker/mito-blast-filter/NOTICE` covers where the parameter choices came from
and how the implementation differs from its upstreams, and that directory's `tests/` pin
the behaviour described here — including the concatemer miss.
