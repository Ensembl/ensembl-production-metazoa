NCBI_FTP_URL="https://ftp.ncbi.nlm.nih.gov/genomes/all/"

SCRIPTS="."

# try to find "NCBI" datasets to use
DATASETS_ON_PATH=$(command -v datasets 2>/dev/null)
DATASETS_IMG="$NXF_SINGULARITY_CACHEDIR/datasets-cli.latest.sif"

if [ -n "$DATASETS" ]; then
  # user provided
  echo using user provided path to datasets binary: $DATASETS >> /dev/stderr
  DATASETS_BIN="$DATASETS"
elif [ -f "$DATASETS_IMG" ]; then
  # check if we have anything in the singularity hash
  echo "using datasest from the singularity image: $DATASETS_IMG" >> /dev/stderr
  DATASETS_BIN="singularity run $NXF_SINGULARITY_CACHEDIR/datasets-cli.latest.sif datasets" >> /dev/stderr
elif [ -n "$DATASETS_ON_PATH" ]; then
  # check if we have anything on PATH
  echo "no singularity image found, using available binary..." >> /dev/stderr
  DATASETS_BIN="datasets"
else
  # grumble
  echo "please, ensure the 'datasests' binary is on PATH or provide 'DATASETS' variable with its path... exiting..." >> /dev/stderr
  exit 1
fi


# working dir
WD="."

cat > "$WD"/acc.lst

# get data using NCBI datasets
cat acc.lst |
  xargs -n 10 \
    "$DATASETS_BIN" summary genome accession |
  cat > "$WD"/ds.raw

# turn into jsonl
cat "$WD"/ds.raw | jq -c -f $SCRIPTS/template/ds_raw2jsonl.jq > "$WD"/ds.jsonl.raw

# add ftp and assembly report urls
cat "$WD"/ds.jsonl.raw | python3 $SCRIPTS/template/add_urls.py "$NCBI_FTP_URL" > "$WD"/ds.jsonl.urls

# fetch assembly reports
REPORTS_DIR="$WD"/reports
mkdir -p "$REPORTS_DIR"
cat "$WD"/ds.jsonl.urls |
  jq -c '{ (._GENOME_ACCESSION_) : .assembly_report_url }' |
  tr -d '{}' |
  xargs -n 1 -I XXX sh -c '
    echo XXX
    wget -O '"${REPORTS_DIR}"'/$(echo XXX | cut -f 1 -d :) $(echo XXX | cut -f 2- -d :)
    sleep 2
  '

# add submitter and common name
grep -e '^# Organism name:' -e '^# Submitter:' "$REPORTS_DIR"/* |
  perl -pe 's,.*/([^/]+:),$1,' |
  python3 $SCRIPTS/template/add_submitter_and_common.py "$WD"/ds.jsonl.urls |
  cat > "$WD"/ds.jsonl.urls_names

# generate a tsv file
cat "$WD"/ds.jsonl.urls_names | jq -c -r -f $SCRIPTS/template/jsonl2tsv.jq  > "$WD"/ds.tsv.pre

# form header
grep -P '^\s*\.' $SCRIPTS/template/jsonl2tsv.jq |
  perl -pe 's/^\s*\.//; s/,?\s*$/\t/' |
  perl -pe 's/\s*$/\n/' > "$WD"/ds.tsv

# reorder according to the source list and append after the header
cat "$WD"/ds.tsv.pre acc.lst |
  awk -F "\t" '(NF > 1) {stash[$5] = $0} NF == 1 {print stash[$1]}' >> "$WD"/ds.tsv

# print out
cat "$WD"/ds.tsv
