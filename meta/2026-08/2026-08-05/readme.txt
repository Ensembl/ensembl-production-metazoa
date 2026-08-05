DATASETS_BIN="singularity run $NXF_SINGULARITY_CACHEDIR/datasets-cli.latest.sif datasets"
JQ_BIN="singularity run $NXF_SINGULARITY_CACHEDIR/datasets-cli.latest.sif jq"

URL="https://ftp.ebi.ac.uk/pub/databases/wormbase/parasite/releases/WBPS19/species"
WBPS_SFX="WBPS19"
GFF_SFX="annotations.gff3.gz"
PEP_SFX="protein.fa.gz"

echo _GENOME_ACCESSION_ _ANNOTATION_GFF3_ _ANNOTATION_PEP_ _REFSEQ_ANN_REPORT_URL_ |
  perl -pe 's/ /\t/g' >  acc_gff3_pep.tsv

cat wb.acc.lst |
  xargs -n 1 |
  tee acc.lst.stashed |
  xargs -n 50 \
  $DATASETS_BIN summary genome accession |
  tee ds.raw |
  $JQ_BIN -c '.reports.[] | {
      accession: .accession,
      scientific_name: .organism.organism_name,
      bioproject: .assembly_info.bioproject_accession
  }' |
  tee ds.jsonl |
  $JQ_BIN -c -r '[
    .accession,
    .scientific_name,
    .bioproject
  ] | join(\"\\t\")' |
  tee ds.tsv |
  awk -F "\t" \
    -v url="$URL" -v wb_sfx="$WBPS_SFX" -v gff_sfx="$GFF_SFX" -v pep_sfx="$PEP_SFX" '{
      acc = $1;
      name = tolower($2); gsub("_", "", name); gsub(" sp. ", " ", name); gsub(" ", "_", name)
      prj = $3;
      printf("%s\t", $1);
      printf("%s/%s/%s/", url, name, prj);
      printf("%s.%s.%s.%s\t", name, prj, wb_sfx, gff_sfx);
      printf("%s/%s/%s/", url, name, prj);
      printf("%s.%s.%s.%s\t", name, prj, wb_sfx, pep_sfx);
      printf("%s/%s/%s\n", url, name, prj);
    }' |
 tee acc_gff3_pep.pre |
 cat - acc.lst.stashed |
   awk -F "\t" '(NF > 1) {stash[$1] = $0} NF == 1 {print stash[$1]}' >> acc_gff3_pep.tsv

# create genomes.lst, rename to genomes.lst.raw
cat genomes.lst.raw acc_gff3_pep.tsv |
   awk -F "\t" '(NF > 5) {stash[$5] = $0} NF == 4 {OFS="\t"; print stash[$1], $2, $3, $4;}' |
   cut -f 1-6,9,16-18 |
   awk -F "\t" '{abbr = $4; if (seen[abbr]) {$4 = abbr""seen[abbr];}; seen[abbr]++; OFS="\t"; print}'> wb.genomes.lst

