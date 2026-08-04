#!/usr/bin/env bash
# See the NOTICE file distributed with this work for additional information
# regarding copyright ownership.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# enabling failing on error
set -o errexit
set -o pipefail
set -o xtrace


# failsafe grep
function grep () {
  local params=''
  for param in "$@"; do
    params="${params} \"${param}\""
  done

  sh -c -- "grep $params" || :
}

# get wd
WDIR="$1"
mkdir -p "${WDIR}"

GFF_PARSE_ID_SCRIPT="$2"
TRIM_SCRIPT="$3"
TRIM_EXPR="$4"
TRIM_OPTS="$5"

# get gff3 from STDIN
cat | gzip - > ${WDIR}/raw.gff3.gz 

# get duplicated genes
zcat ${WDIR}/raw.gff3.gz |
  awk -F "\t" '$3 == "gene"' |
  cut -f 1,9 |
  perl -pe 's/\t.*?(?<=\t|;)(ID=[^;]+).*/\t$1/' |
  sort | uniq -c | sort -nr |
  awk '$1 > 1 {print $2"\t"$3}' | 
  cat > ${WDIR}/duplicated.gene.reg_ids

# check only one region per gene even for duplicates  
cat ${WDIR}/duplicated.gene.reg_ids |
  cut -f 2 |
  sort | uniq -c | sort -nr |
  awk '$1 > 1 {print $2}' | 
  cat > ${WDIR}/duplicated.gene.ids.on_different_regions

ABNORMAL_DUPS=$(cat ${WDIR}/duplicated.gene.ids.on_different_regions | wc -l)

if [  "${ABNORMAL_DUPS}" -gt "0" ]; then
  echo "found ${ABNORMAL_DUPS} genes with duplicated IDs on different regions" >> /dev/stderr
  echo "see ${WDIR}/duplicated.gene.ids.on_different_regions, head: " >> /dev/stderr
  head ${WDIR}/duplicated.gene.ids.on_different_regions >> /dev/stderr
  echo "failing..." >> /dev/stderr
  false
  exit 1
fi

# keep IDs only
cat ${WDIR}/duplicated.gene.reg_ids |
  cut -f 2 | sort | uniq |
  cut -f 2 -d '=' |
  cat > ${WDIR}/duplicated.gene.ids


# get *RNAs and transcripts with ? strand
zcat ${WDIR}/raw.gff3.gz |
  grep -v '#' |
  awk -F "\t" 'tolower($3) ~ /rna$|^transcript$/ && $7 == "?"' |
  cat > ${WDIR}/tr.nostrand.raw.gff3

cat ${WDIR}/tr.nostrand.raw.gff3 |
  python "$GFF_PARSE_ID_SCRIPT" --dump_only "ID" |
  sort | uniq > ${WDIR}/tr.nostrand.ids

cat ${WDIR}/tr.nostrand.raw.gff3 |
  python "$GFF_PARSE_ID_SCRIPT" --dump_only "Parent" |
  sort | uniq > ${WDIR}/tr.nostrand.parents.ids

# get all features with ";exception=trans-splicing"
zcat ${WDIR}/raw.gff3.gz |
  grep -v '#' |
  awk -F "\t" '$9 ~ /(^|;)exception=trans-splicing/' |
  cat > ${WDIR}/all.exception.raw.gff3

# we assume correct gene/transcript/exon model trees
# get transcripts from exons/CDSs
cat ${WDIR}/all.exception.raw.gff3 |
  awk -F "\t" '$3 == "exon" || $3 == "CDS"' |
  python "$GFF_PARSE_ID_SCRIPT" --dump_only "Parent" |
  sort | uniq > ${WDIR}/exon.ex.parents.ids

# get all mRNA/transcipt IDS
cat ${WDIR}/all.exception.raw.gff3 | 
  awk -F "\t" 'tolower($3) ~ /rna$|^transcript$/' |
  python "$GFF_PARSE_ID_SCRIPT" --dump_only "ID" |
  sort | uniq > ${WDIR}/tr.ex.ids

# merge and get parents (aka genes)
cat ${WDIR}/tr.ex.ids ${WDIR}/exon.ex.parents.ids |
  sort | uniq > ${WDIR}/tr.ex.joined.ids

cat ${WDIR}/all.exception.raw.gff3 |
  python "$GFF_PARSE_ID_SCRIPT" --dump_only "Parent" --check_keys "ID" --ids_file ${WDIR}/tr.ex.joined.ids |
  sort | uniq > ${WDIR}/tr.ex.parents.ids


# look for all gene and mrna IDS
cat \
    ${WDIR}/duplicated.gene.ids \
    ${WDIR}/tr.nostrand.ids \
    ${WDIR}/tr.nostrand.parents.ids \
    ${WDIR}/exon.ex.parents.ids \
    ${WDIR}/tr.ex.ids \
    ${WDIR}/tr.ex.parents.ids |
  sort | uniq > ${WDIR}/combined.ids

SEEDS_CNT=$(cat ${WDIR}/combined.ids | wc -l)

if [ "$SEEDS_CNT" -gt 0 ]; then
  zcat ${WDIR}/raw.gff3.gz |
    python "$GFF_PARSE_ID_SCRIPT" --dump_only "ID" --check_keys "ID,Parent" --ids_file ${WDIR}/combined.ids |
    sort | uniq > ${WDIR}/seed.ids

  # gen pat once again and get all the features for further preprocessing
  zcat ${WDIR}/raw.gff3.gz |
    python "$GFF_PARSE_ID_SCRIPT" --check_keys "ID,Parent" --ids_file ${WDIR}/seed.ids |
    cat > ${WDIR}/features.tr_spliced.gff3

  # fix
  zcat ${WDIR}/raw.gff3.gz |
      python $TRIM_SCRIPT \
          --features_of_interest ${WDIR}/features.tr_spliced.gff3 \
          $TRIM_EXPR $TRIM_OPTS 2>  ${WDIR}/fix.stderr |
      cat

  tail ${WDIR}/fix.stderr >> /dev/stderr
  cat ${WDIR}/fix.stderr |
      grep -P '^#CONF\tTR_TRANS_SPLICED\t' |
      cat > ${WDIR}/fixed_tr.stable_ids.meta
else
  echo "no trans-splicing related artifacts found..." >> /dev/stderr
  echo -n > ${WDIR}/fixed_tr.stable_ids.meta
  zcat ${WDIR}/raw.gff3.gz |
    cat
fi # SEEDS_CNT
