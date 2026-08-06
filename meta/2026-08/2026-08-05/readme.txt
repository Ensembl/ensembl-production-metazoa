DATASETS_BIN="singularity run $NXF_SINGULARITY_CACHEDIR/datasets-cli.latest.sif datasets"
JQ_BIN="singularity run $NXF_SINGULARITY_CACHEDIR/datasets-cli.latest.sif jq"

URL="https://ftp.ebi.ac.uk/pub/databases/wormbase/parasite/releases/WBPS19/species"
WBPS_SFX="WBPS19"
GFF_SFX="annotations.gff3.gz"
PEP_SFX="protein.fa.gz"

echo _GENOME_ACCESSION_ _ANNOTATION_GFF3_ _ANNOTATION_PEP_ _REFSEQ_ANN_REPORT_URL_ assembly_name |
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
      bioproject: .assembly_info.bioproject_accession,
      assembly_name: .assembly_info.assembly_name
  }' |
  tee ds.jsonl |
  $JQ_BIN -c -r '[
    .accession,
    .scientific_name,
    .bioproject,
    .assembly_name
  ] | join(\"\\t\")' |
  tee ds.tsv |
  awk -F "\t" \
    -v url="$URL" -v wb_sfx="$WBPS_SFX" -v gff_sfx="$GFF_SFX" -v pep_sfx="$PEP_SFX" '{
      acc = $1;
      name = tolower($2); gsub("_", "", name); gsub(" sp. ", " ", name); gsub(" ", "_", name)
      prj = $3;
      asm_name = $4;
      printf("%s\t", $1);
      printf("%s/%s/%s/", url, name, prj);
      printf("%s.%s.%s.%s\t", name, prj, wb_sfx, gff_sfx);
      printf("%s/%s/%s/", url, name, prj);
      printf("%s.%s.%s.%s\t", name, prj, wb_sfx, pep_sfx);
      printf("%s/%s/%s\t", url, name, prj);
      printf("%s\n", asm_name);
    }' |
 tee acc_gff3_pep.pre |
 cat - acc.lst.stashed |
   awk -F "\t" '(NF > 1) {stash[$1] = $0} NF == 1 {print stash[$1]}' >> acc_gff3_pep.tsv

# update urls, fix missing
cat acc_gff3_pep.tsv |
  cut -f 4 |
  xargs -n  1 -I XXX sh -c 'sleep 2; wget -O - "XXX" > /dev/null 2>&1 || echo missing XXX ' | tee wrong.urls


# create genomes.lst, rename to genomes.lst.raw
cat genomes.lst.raw acc_gff3_pep.tsv |
   awk -F "\t" '(NF > 5) {stash[$5] = $0} NF == 5 {OFS="\t"; print stash[$1], $2, $3, $4;}' |
   cut -f 1-6,9,16-18 |
   awk -F "\t" '{abbr = $4; if (seen[abbr]) {$4 = abbr""seen[abbr];}; seen[abbr]++; OFS="\t"; print}' |
   cat - anno_provider_name.tsv |
   awk -F "\t" '(NF > 5) {stash[$5] = $0} NF == 2 {OFS="\t"; print stash[$1], $2;}' |
   cat > wb.genomes.lst

# check for duplicated abbrebs
cut -f 4 wb.genomes.lst | sort | uniq | wc -l

# check counts
cat $METACONF_DIR/wb.genomes.lst |
  grep -vF '#' |
  grep -vP '^\s*$' |
  awk -F "\t" '{print NF}' |
  sort | uniq -c
    188 10

# gen configs
python3 ./ensembl-production-metazoa/scripts/tmpl2meta.py   \
  --template $METACONF_DIR/wormbase_import.tmpl \
  --param_table $METACONF_DIR/wb.genomes.lst \
  --output_dir $METACONF_DIR/wb \
  --out_file_pfx wbi_ \
  --keep_empty_values
 



