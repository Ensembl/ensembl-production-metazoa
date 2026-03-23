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

TRIM_SCPRIPT="$2"
TRIM_EXPR="$3"

# get gff3 from STDIN
cat | gzip - > ${WDIR}/raw.gff3.gz 

# get duplicated genes
zcat ${WDIR}/raw.gff3.gz |
  awk -F "\t" '$3 == "gene"' |
  cut -f 1,9 |
  perl -pe 's/\t(?:[^\t]+;?)?(ID=[^;]+).*/\t$1/' |
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
  cat > ${WDIR}/duplicated.gene.ids


# get *RNAs and transcripts with ? strand
zcat ${WDIR}/raw.gff3.gz |
  grep -v '#' |
  awk -F "\t" 'tolower($3) ~ /rna$|^transcript$/ && $7 == "?"' |
  cat > ${WDIR}/tr.nostrand.raw

cat ${WDIR}/tr.nostrand.raw |
  cut -f 9 |
  perl -pe 's/^(?:.+;?)?(ID=[^;]+).*/$1/' |
  sort | uniq > ${WDIR}/tr.nostrand.ids

cat ${WDIR}/tr.nostrand.raw |
  cut -f 9 |
  perl -pe 's/^(?:.+;?)?(Parent=[^;]+).*/$1/' |
  sort | uniq > ${WDIR}/tr.nostrand.parents

# get all features with ";exception=trans-splicing"
zcat ${WDIR}/raw.gff3.gz |
  grep -v '#' |
  awk -F "\t" '$9 ~ /(^|;)exception=trans-splicing/' |
  cat > ${WDIR}/all.exception.raw


# we assume correct gene/transcript/exon model trees
# get transcripts from exons/CDSs
cat ${WDIR}/all.exception.raw |
  awk -F "\t" '$3 == "exon" || $3 == "CDS"' |
  cut -f 9 |
  perl -pe 's/^(?:.+;?)?(Parent=[^;]+).*/$1/' |
  sort | uniq > ${WDIR}/exon.ex.parents

# there could be mulitple parents:
#    Parent=FBtr0078166,FBtr0078167
cat ${WDIR}/exon.ex.parents |
  cut -f 2 -d '=' |
  perl -pe 's/,/\n/g' |
  sort | uniq > ${WDIR}/exon.ex.parents.ids 

# get all mRNA/transcipt IDS
cat ${WDIR}/all.exception.raw | 
  awk -F "\t" 'tolower($3) ~ /rna$|^transcript$/' |
  cut -f 9 |
  perl -pe 's/^(?:.+;?)?(ID=[^;]+).*/$1/' |
  sort | uniq > ${WDIR}/tr.ex

# merge and get parents (aka genes)
cat ${WDIR}/tr.ex | cut -f 2 -d '=' |
  cat - ${WDIR}/exon.ex.parents.ids |
  sort | uniq |
  awk '{print "[\\t|;]ID="$1"(;|$)"; }' | perl -pe 's/\n/|/' | perl -pe 's/\|$//' |
  grep -Pf - ${WDIR}/all.exception.raw |
  cut -f 9 |
  perl -pe 's/^(?:.+;?)?(Parent=[^;]+).*/$1/' |
  sort | uniq > ${WDIR}/tr.ex.parents


# look for all gene and mrna IDS
cat \
    ${WDIR}/tr.ex \
    ${WDIR}/tr.ex.parents \
    ${WDIR}/tr.nostrand.ids \
    ${WDIR}/tr.nostrand.parents \
    ${WDIR}/duplicated.gene.ids | 
  cut -f 2 -d '=' |
  cat - ${WDIR}/exon.ex.parents.ids |
  sort | uniq |
  awk '{print "[\\t;]ID="$1"(?:;|$)"; print "[\\t;]Parent=(?:[^;]+,)?"$1"(?:[,;]|$)";} ' |
  cat > ${WDIR}/seed.pat

SEEDS_CNT=$(cat ${WDIR}/seed.pat | wc -w)

# Split into 300-pattern chunks and make valid regex lines
split -l 300 ${WDIR}/seed.pat ${WDIR}/seed.chunk.
for f in ${WDIR}/seed.chunk.*; do
    paste -sd'|' "$f" > "${f}.pat"
    rm "$f"
done

# Only run if seeds exist
if [ "$SEEDS_CNT" -gt 0 ]; then
    tmpfile="${WDIR}/seed.ids.tmp"
    > "$tmpfile"

    # Loop over chunked pattern files
    for f in ${WDIR}/seed.chunk.*.pat; do
        zcat ${WDIR}/raw.gff3.gz |
        grep -v '^#' |
        grep -Pf "$f" >> "$tmpfile"
    done

    # Extract ID= field, deduplicate
    cut -f 9 "$tmpfile" |
    perl -pe 's/^(?:.+;?)?(ID=[^;]+).*/$1/' |
    sort -u > "${WDIR}/seed.ids"

    rm "$tmpfile"

  cut -f2 -d '=' "${WDIR}/seed.ids" | sort -u > ${WDIR}/ids.list
  awk -F'\t' 'NR==FNR { ids[$0]; next }
  !/^#/ {
    split($9, a, ";")
    id=""; parent=""

    for(i in a){
        if(a[i] ~ /^ID=/) id=substr(a[i],4)
        if(a[i] ~ /^Parent=/) parent=substr(a[i],8)
    }

    if(id in ids) print
    else {
        n=split(parent,p,",")
        for(j=1;j<=n;j++){
            if(p[j] in ids){ print; break }
        }
    }
  }
  ' ${WDIR}/ids.list <(zcat ${WDIR}/raw.gff3.gz) \
  > ${WDIR}/features.gff3.tr_spliced
  # fix
  zcat ${WDIR}/raw.gff3.gz |
      python $TRIM_SCPRIPT \
          --features_of_interest ${WDIR}/features.gff3.tr_spliced \
          $TRIM_EXPR 2>  ${WDIR}/fix.stderr |
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
