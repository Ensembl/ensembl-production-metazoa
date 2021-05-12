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

spec="$1"
stdin="$2"
stderr="$3"
outdir="$4"

mkdir -p $outdir

function grep () {
  # failsafe grep
  local params=''
  for param in "$@"; do
    params="${params} \"${param}\""
  done

  sh -c -- "grep $params" || :
}

(cat $stdin | grep -P '^TRANSCRIPT\t' | grep -P '^TRANSCRIPT\tSTATUS\t' | sort | uniq | tail -n 1;
 cat $stdin | grep -P '^TRANSCRIPT\t' | grep -vP '^TRANSCRIPT\tSTATUS\t' ) |
    gzip - > ${outdir}/${spec}.tr.stat.tsv.gz
( cat $stdin | grep -P '^GENE\t' | grep -P '^GENE\tSTATUS\t' | sort | uniq | tail -n 1;
  cat $stdin | grep -P '^GENE\t' | grep -vP '^GENE\tSTATUS\t' ) |
    gzip - > ${outdir}/${spec}.gene.stat.tsv.gz

( echo "PAIR_GENE TYPE
        GENE_1_NAME GENE_1_ID GENE_1_CTG GENE_1_START GENE_1_END GENE_1_STRAND
        GENE_2_NAME GENE_2_ID GENE_2_CTG GENE_2_START GENE_2_END GENE_2_STRAND
       " | xargs echo |  perl -pe 's/ /\t/g';
  cat $stdin | grep -P '^PAIR_GENE\t' ) |
    gzip - > ${outdir}/${spec}.gene_pairs.stat.tsv.gz

( echo "OVERLAP_FILTER FILTER
        GENE_NAME GENE_ID GENE_CTG GENE_START GENE_END GENE_STRAND
       " | xargs echo |  perl -pe 's/ /\t/g';
  cat $stdin | grep -P '^OVERLAP_FILTER\t' ) |
    gzip - > ${outdir}/${spec}.overlap_filter.stat.tsv.gz

( echo "MERGED_LOCI TYPE
        GENE_NAME GENE_SRC_ID CTG START END STRAND MERGED_FOR_THIS_LOCI IGNORED
       " | xargs echo |  perl -pe 's/ /\t/g';
  cat $stdin | grep -P '^MERGED_LOCI\t' | sort -k5,5 -k6,6n -k7,7n -k2,2 -k8,8 -k3,3) |
    gzip - > ${outdir}/${spec}.merged_loci.stat.tsv.gz

cat $stdin | grep -P '^GFF3\t' | cut -f 2- |
  gt gff3 -tidy -sort -retainids - |  gzip - > ${outdir}/${spec}.gff3.gz

cat $stderr | grep '^#STAT' | grep gene > ${outdir}/${spec}.stat.log
cat $stderr | grep '^#STAT' | grep -v gene >> ${outdir}/${spec}.stat.log

cat $stderr | grep '^#CONF' > ${outdir}/${spec}.conf.log

# usage: 
#  zcat transcripts.gff3.gz | perl compara_projection2gff3.pl \
#    $($CMD details script_from_) -from_dbname <from_db_name> \
#    $($CMD details script_to_) -to_dbname <to_db_name> \
#    -calc_spliced_distance 0 \
#    -exon_inflation_max 2.0 \
#    -exons_lost_max 1 \
#    -exons_gained_max 3 \
#    -tra_dist_rel_max 0.47 \
#    -unplaced_ctg UNK1 \
#    -unplaced_ctg UNK2 \
#    -top_genes 10 \
#    -source_gff - \
#    > patched.pre_gff3  2> from_to_log 
#
#  ./projections_gff3_pre2gff3.sh 'species_name' patche.pre_gff3 from_to_log outdir
#
