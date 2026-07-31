# cDNA reference (asmgene)

## Obtaining the reference

`reference_cdna_fasta` is Ensembl's GRCh38 cDNA/transcript FASTA, `cdna.all` (every transcript
of every Ensembl gene, excluding ncRNA -- not `cdna.abinitio`, which is ab initio gene
predictions rather than real transcripts). The same file is used for both the
CHM13-reference-side and each haplotype's asmgene mapping.

```sh
curl -O https://ftp.ensembl.org/pub/current_fasta/homo_sapiens/cdna/Homo_sapiens.GRCh38.cdna.all.fa.gz
```

No need to decompress: `MapCdnaSplice` passes it straight to minimap2, which reads gzipped
FASTA natively (the same way `projection_reference_fasta` is normally supplied as a
`.fa.gz`).

`current_fasta` is Ensembl's symlink to whatever the latest release is, so the exact file it
resolves to changes over time. For a reproducible run, pin an explicit release number instead,
e.g.:

```sh
curl -O https://ftp.ensembl.org/pub/release-116/fasta/homo_sapiens/cdna/Homo_sapiens.GRCh38.cdna.all.fa.gz
```
