NCBI_FTP_URL="https://ftp.ncbi.nlm.nih.gov/genomes/all/"

SCRIPTS="../"

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
  DATASETS_BIN="singularity run $NXF_SINGULARITY_CACHEDIR/datasets-cli.latest.sif datasets"
elif [ -n "$DATASETS_ON_PATH" ]; then
  # check if we have anything on PATH
  echo "no singularity image found, using available binary..." >> /dev/stderr
  DATASETS_BIN="datasets"
else
  # grumble
  echo "please, ensure the 'datasests' binary is on PATH or provide 'DATASETS' variable with its path... exiting..." >> /dev/stderr
  exit 1
fi

# same with jq
if [ -n "$JQ" ]; then
  # user provided
  echo using user provided path to jq binary: $JQ>> /dev/stderr
  JQ_BIN="$JQ"
elif [ -f "$DATASETS_IMG" ]; then
  # check if we have anything in the singularity hash
  echo "using jq from the singularity image: $DATASETS_IMG" >> /dev/stderr
  JQ_BIN="singularity run $NXF_SINGULARITY_CACHEDIR/datasets-cli.latest.sif jq"
else
  # grumble
  echo "using 'jq' whatever version you have as jq..." >> /dev/stderr
  JQ_BIN="jq"
fi

echo "using '$DATASETS_BIN' as datasets binary" >> /dev/stderr
echo "using '$JQ_BIN' as jq binary" >> /dev/stderr

# working dir
WD="tmp"
mkdir -p $WD

cat > "$WD"/acc.lst

# get data using NCBI datasets
echo "querying datasets info from NCBI..." >> /dev/stderr
cat "$WD"/acc.lst |
  xargs -n 50 \
    $DATASETS_BIN summary genome accession |
  cat > "$WD"/ds.raw

# turn into jsonl
cat "$WD"/ds.raw | $JQ_BIN -c -f $SCRIPTS/template/ds_raw2jsonl.jq > "$WD"/ds.jsonl.raw


# add ftp and assembly report urls
cat "$WD"/ds.jsonl.raw | python3 $SCRIPTS/template/add_urls.py "$NCBI_FTP_URL" > "$WD"/ds.jsonl.urls

# fetch assembly reports
REPORTS_DIR="$WD"/reports
mkdir -p "$REPORTS_DIR"

echo "fetching assembly reports from NCBI into $REPORTS_DIR..." >> /dev/stderr
cat "$WD"/ds.jsonl.urls |
  $JQ_BIN -c '{ (._GENOME_ACCESSION_) : .assembly_report_url }' |
  tr -d '{}' |
  xargs -n 1 -I XXX sh -c '
    echo XXX
    wget -O '"${REPORTS_DIR}"'/$(echo XXX | cut -f 1 -d :) $(echo XXX | cut -f 2- -d :)
    sleep 2
  '

# add submitter and common name
echo "adding bits from assembly reports..." >> /dev/stderr

# add fake  report for grep to work properly
touch "$REPORTS_DIR/"_tech_report_stub

grep -e '^# Organism name:' -e '^# Submitter:' "$REPORTS_DIR"/* |
  perl -pe 's,.*/([^/]+:),$1,' |
  python3 $SCRIPTS/template/add_submitter_and_common.py "$WD"/ds.jsonl.urls |
  cat > "$WD"/ds.jsonl.urls_names

# generate a tsv file
echo "generating a tsv file..." >> /dev/stderr
cat "$WD"/ds.jsonl.urls_names | $JQ_BIN -c -r -f $SCRIPTS/template/jsonl2tsv.jq  > "$WD"/ds.tsv.pre

# form header
grep -P '^\s*\.' $SCRIPTS/template/jsonl2tsv.jq |
  perl -pe 's/^\s*\.//; s/,?\s*$/\t/' |
  perl -pe 's/\s*$/\n/' > "$WD"/ds.tsv

# reorder according to the source list and append after the header
cat "$WD"/ds.tsv.pre "$WD"/acc.lst |
  awk -F "\t" '(NF > 1) {stash[$5] = $0} NF == 1 {print stash[$1]}' >> "$WD"/ds.tsv

# print out
cat "$WD"/ds.tsv

# usage: echo GCF_023614345.1 GCA_023614345.1 | xargs -n 1 | bash ./gen_template.sh
