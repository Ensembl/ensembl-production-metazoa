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


# globals
if [ -z "$PROD_SERVER" ]; then
  echo 'no db server alias "$PROD_SERVER" is provided' > /dev/stderr
  false
  exit 1
fi

if [ -z "$PROD_DBNAME" ]; then
  PROD_DBNAME=ensembl_production
fi

if [ -z "$TAXONOMY_DBNAME" ]; then
  TAXONOMY_DBNAME=ncbi_taxonomy
fi

REPUTIL_PATH="$(brew --prefix repeatmasker)"/libexec/util

# utils

set -o pipefail

function grep () {
  # failsafe grep
  local params=''
  for param in "$@"; do
    params="${params} \"${param}\""
  done

  sh -c -- "grep $params" || :
}

# create directory structure

function populate_dirs () {
  local BASE=$1
  mkdir -p $BASE
  mkdir -p $BASE/done
  mkdir -p $BASE/bup
  mkdir -p $BASE/data/raw
  mkdir -p $BASE/data/pipeline_out

  export DONE_TAGS_DIR=$BASE/done
  export PIPELINE_OUT_DIR=$BASE/data/pipeline_out
}

function get_ensembl_prod () {
  local BASE=$1
  local EG_RELEASE=$2
  local CHECKOUT_SCRIPT=$3
  local CREATE_SETUP_SCRIPT=$4

  mkdir -p $BASE
  if [ ! -f $BASE/_CAN_USE ]; then
    pushd $BASE
    "$CHECKOUT_SCRIPT" "$CREATE_SETUP_SCRIPT" .

    for d in  $(find * -maxdepth 0 -type d); do
      echo $d
      pushd $d
      git checkout origin/release/${EG_RELEASE} || true
      popd
    done

    # make ensembl-production-imported symlink
    local MZPPL_PATH=$(realpath $BASH_SOURCE | perl -pe 's,ensembl-production-metazoa/.*,ensembl-production-metazoa,')
    if [ -n "$MZPPL_PATH" ]; then
      mv ./ensembl-production-metazoa ./ensembl-production-metazoa.unused
      ln -s "$MZPPL_PATH" ./ensembl-production-metazoa
    fi

    popd

# legacy
#    echo "patching $BASE/ensembl-production-imported/modules/Bio/EnsEMBL/EGPipeline/FileDump/GenomicFeatureDumper.pm line 88" > /dev/stderr
#    echo "commenting \$seq_obj->add_keyword('.');" > /dev/stderr
#
#    cat "$BASE"/ensembl-production-imported/modules/Bio/EnsEMBL/EGPipeline/FileDump/GenomicFeatureDumper.pm |
#      perl -pe 's/^/#COMMENTED: / if m/seq_obj->add_keyword\('\''\.'\''\)/' > "$BASE/tmp"
#    mv "$BASE"/tmp "$BASE"/ensembl-production-imported/modules/Bio/EnsEMBL/EGPipeline/FileDump/GenomicFeatureDumper.pm
#
#    cat "$BASE"/setup.sh |
#      perl -pe 's/^/#/ if m,/bioperl/stable,; s,bioperl/run-stable,bioperl/ensembl-stable,' > "$BASE"/tmp
#    mv "$BASE"/tmp "$BASE"/setup.sh

    touch $BASE/_CAN_USE
  fi

  source $BASE/setup.sh
  export PROD_DB_SCRIPTS=${ENSEMBL_ROOT_DIR}/ensembl-production/scripts/production_database
}

function get_metazoa_scripts () {
  local FROM="$1"
  local BASE="$2"

  mkdir -p "$BASE"
  if [ ! -f "$BASE"/_CAN_USE ]; then
    cp -pR "$FROM"/* "$BASE"
    # fix: } elsif ( $substring_sequence =~ m/^[ACGTN]+$/i ) {
    #      } elsif ( $substring_sequence =~ m/^[ACGTNBDHKMRSWY]+$/i ) {
    cat "$BASE"/misc/fasta2agp.pl |
      perl -pe 's/ACGTN/ACGTNBDHKMRSWY/ if (m,\$substring_sequence =~ m/\^\[ACGTN\]\+\$/i,)' > "$BASE"/tmp
    mv "$BASE"/tmp "$BASE"/misc/fasta2agp.pl

    cat "$BASE"/core/project_genes.pl |
      perl -pe 's/^/# COMMENTED # / if m/last\s+if\s+\$counter\s+>\s+5000;/' > "$BASE"/tmp

    mv "$BASE"/tmp "$BASE"/core/project_genes.pl

    touch "$BASE"/_CAN_USE
  fi

  export METAZOA_SCRIPTS="$BASE"
}

function get_meta_str () {
  local META_FILE="$1"
  local META_KEY="$2"
  cat $META_FILE |
    grep -vP '^\s*#' |
    grep -vP '^\s*$' |
    perl -pe 's/\s*\t\s*/\t/g; s/^\s*//; s/\s*$/\n/' |
    grep -F "$META_KEY" |
    awk -v key="$META_KEY" '($1 == key) {$1=""; print}' |
    perl -pe 's/^\s*//'
}

function get_meta_conf () {
  local META_FILE="$1"
  local CONF_KEY="$2"
  cat $META_FILE |
    grep -P '^\s*#\s*CONF\s+' |
    grep -F "$CONF_KEY" |
    awk -v key="$CONF_KEY" '($2 == key) {$1=""; $2=""; print}' |
    perl -pe 's/^\s*//'
}



function gen_db_name () {
  local META_FILE=$1
  local VB_RELEASE=$2
  local EG_VERSION=$3
  local ASM_VERSION=$4
  local DATA_DIR=$5

  export SPECIES="$(get_meta_str ${META_FILE} 'species.production_name')"
  echo $SPECIES > $DATA_DIR/_species
  export SPECIES_NAME="$(get_meta_str ${META_FILE} 'species.scientific_name')"
  echo $SPECIES_NAME > $DATA_DIR/_species_name
  export DBNAME=${SPECIES}_core_${VB_RELEASE}_${EG_VERSION}_${ASM_VERSION}
  echo $DBNAME > ${DATA_DIR}/_db_name
}

function touch_done () {
  touch "$DONE_TAGS_DIR"/"$1"
}

function clean_done () {
  [ -f "$DONE_TAGS_DIR"/"$1" ] && rm "$DONE_TAGS_DIR"/"$1" || true
}

function check_done () {
  [ -f "$DONE_TAGS_DIR"/"$1" ]
}

function create_db_stub () {
  local CMD=$1
  local DBNAME=$2
  local ENS_DIR=$3
  local BUP_DIR=$4

  echo ENS_DIR $ENS_DIR

  if ! check_done _create_db_stub; then
    # CREATE DB STUB
    echo creating stub for $DBNAME at $CMD > /dev/stderr

    $CMD -e "DROP DATABASE IF EXISTS $DBNAME;"
    $CMD -e "CREATE DATABASE IF NOT EXISTS $DBNAME;"
    $CMD $DBNAME < $ENS_DIR/ensembl/sql/table.sql

    mkdir -p $BUP_DIR
    perl $ENS_DIR/ensembl-production/scripts/production_database/populate_production_db_tables.pl \
      $($CMD details script) \
      $($PROD_SERVER details prefix_m) \
      --database $DBNAME \
      --mdatabase $PROD_DBNAME \
      --dumppath $BUP_DIR \
      --dropbaks

    touch_done _create_db_stub
  fi
}


function backup_relink () {
  local DBNAME=$1
  local CMD=$2
  local TAG=$3
  local BUP_DIR=$4

  # probable race and not full backing up

  local bup_name=$DBNAME.$(date +'%Y%m%d').$TAG.gz
  echo backing up $bup_name > /dev/stderr
  local similar=$(ls $BUP_DIR | grep -F "$DBNAME." | grep -F ".$TAG.gz")
  if [ -n "$similar" ] ; then
    echo " skipping because of the $similar backup..." > /dev/stderr
    return
  fi

  $CMD mysqldump --single-transaction --max_allowed_packet=2024M $DBNAME |
    gzip - > $BUP_DIR/$bup_name

  pushd $BUP_DIR
    [ -L $DBNAME.gz ] && rm $DBNAME.gz
    ln -s $bup_name $DBNAME.gz; cd -
  popd
}
#backup norelink ##backup relink #restore #restore latest #restore ...

function dir_backup_relink () {
  local DIR_PATH=$1
  local TAG=$2
  local BUP_DIR=$3

  # probable race and not full backing up

  local DIRNAME=$(basename $DIR_PATH)
  local bup_name=${DIRNAME}.$(date +'%Y%m%d').$TAG.tgz
  echo backing up $bup_name > /dev/stderr
  local similar=$(ls $BUP_DIR | grep -F "$DIRNAME." | grep -F ".$TAG.tgz")
  if [ -n "$similar" ] ; then
    echo " skipping because of the $similar backup..." > /dev/stderr
    return
  fi

  pushd $(dirname $DIR_PATH)
    tar -zcf $BUP_DIR/${bup_name} $DIRNAME
  popd

  pushd $BUP_DIR
    [ -L $DIRNAME.tgz ] && rm $DIRNAME.tgz
    ln -s $bup_name $DIRNAME.tgz; cd -
  popd
}

function restore () {
  local DBNAME="$1"
  local CMD="$2"
  local BUP_DIR="$3"

  echo restore > /dev/stderr
    ls -lt $BUP_DIR/ > /dev/stderr
  echo "uploading $BUP_DIR/${DBNAME}.gz to $DBNAME"
    echo "drop database if exists $DBNAME; create database $DBNAME;" |
      $CMD
    zcat $BUP_DIR/${DBNAME}.gz |
      $CMD -D $DBNAME
}

function get_asm_ftp () {
  local URL="$1"
  local RAW_DIR="$2"

  ftp_prefix=$(dirname "$URL")
  asm_name=$(basename "$URL")
  if ! check_done _get_asm_ftp; then
    echo getting "$URL" into "$RAW_DIR" > /dev/stderr
    pushd $RAW_DIR
    lftp -e 'mirror '"$asm_name"' ; bye' "$ftp_prefix"
    ln -s "$asm_name" asm
    chmod u+w "$asm_name"
    popd

    touch_done _get_asm_ftp
  fi

  export  ASM_DIR=$RAW_DIR/asm
}

function get_asm_dir () {
  local URL="$1"
  local RAW_DIR="$2"

  ftp_prefix=$(dirname "$URL")
  asm_name=$(basename "$URL")
  if ! check_done _get_asm_ftp; then
    echo getting "$URL" into "$RAW_DIR" > /dev/stderr
    pushd $RAW_DIR
    cp -r "$URL" .
    ln -s "$asm_name" asm
    popd

    touch_done _get_asm_ftp
  fi

  export  ASM_DIR=$RAW_DIR/asm
}

function get_file_to_asm () {
  local URL="$1"
  local ASM_DIR="$2"

  name="$(basename $URL)"
  echo getting "$URL" into "$ASM_DIR" > /dev/stderr
  wget -O $ASM_DIR/$(basename $URL) "$URL"
}

function get_individual_files_to_asm () {
  local ASM_DIR="$1"
  local META_FILE="$2"
  if ! check_done _get_individual_files_to_asm; then
    for url in $(get_meta_conf $META_FILE 'ASM_SINGLE'); do
      get_file_to_asm $url $ASM_DIR
    done

    touch_done _get_individual_files_to_asm
  fi
}



function fill_taxonomy () {
  local CMD="$1"
  local DBNAME="$2"
  local TAXON_ID="$3"
  local ENS_DIR="$4"

  if ! check_done _fill_taxonomy; then
    echo "filling taxonomy for ${TAXON_ID} into $DBNAME" > /dev/stderr
    perl "$ENS_DIR"/ensembl-pipeline/scripts/load_taxonomy.pl \
      -taxon_id "${TAXON_ID}" \
      $($PROD_SERVER details prefix_taxondb) \
      -taxondbname ncbi_taxonomy \
      $($CMD details prefix_db) \
      -dbname "$DBNAME"
    touch_done _fill_taxonomy
  fi
}

function fill_meta () {
  local CMD="$1"
  local DBNAME="$2"
  local META_FILE="$3"
  local BUP_DIR="$4"

  if ! check_done _fill_meta; then
    echo "filling meta from $META_FILE into $DBNAME" > /dev/stderr

    mkdir -p "$BUP_DIR"
    # storing previous version of meta
    old_file="$BUP_DIR"/"$DBNAME".meta.$(date +'%Y%m%d%H%M%S').gz
    echo "backing up meta to " > /dev/stderr
    $CMD $DBNAME -e 'select * from meta;' > $old_file

    # droping previous versions of meta pairs
    echo "removing clashing keys from $DBNAME.meta " > /dev/stderr
    cat $META_FILE |
      grep -v -P '^\s*#' |
      grep -vP '^\s*$' |
      perl -pe 's/\s*\t\s*/\t/g; s/^\s*//; s/\s*$/\n/' |
      cut -f 1  |
      python -c 'import sys; print("delete from meta where meta_key in (\"{}\")".format("\", \"".join(map(lambda x: x.strip(), sys.stdin)))) ' |
      $CMD $DBNAME

    # fill
    echo "filling meta into $DBNAME.meta " > /dev/stderr
    cat $META_FILE |
      grep -v -P '^\s*#' |
      grep -vP '^\s*$' |
      perl -pe 's/\s*\t\s*/\t/g; s/^\s*//; s/\s*$/\n/' |
      awk -F "\t" '{print "insert into meta (species_id, meta_key, meta_value) values (1, \""$1"\", \""$2"\");"}' |
     $CMD $DBNAME

    touch_done _fill_meta
  fi
}


function load_dna_sequences () {
  local CMD="$1"
  local DBNAME="$2"
  local META_FILE="$3"
  local ASSEMBLY="$4"
  local FNA_FILE="$5"
  local ENS_DIR="$6"
  local METAZOA_DIR="$7"
  local PIPELINE_DIR="$8"
  local LOWER_CS_RANK="$9"
  local ASM_DIR="${10}"

  if ! check_done _load_dna_sequences; then
    echo "loading sequences into  into $DBNAME" > /dev/stderr

    local RANK=11
    if [ -n "$LOWER_CS_RANK" ]; then
      RANK="$LOWER_CS_RANK"
      # TODO: estimate
    fi

    mkdir -p "$PIPELINE_DIR"

    gzipped=$(file "$FNA_FILE" | grep -F 'gzip compressed data')
    if [ -n "$gzipped" ]; then
      zcat "$FNA_FILE" > "${PIPELINE_DIR}/input.fa"
    else
      cat "$FNA_FILE" > "${PIPELINE_DIR}/input.fa"
    fi
    local READY_FNA_FILE="${PIPELINE_DIR}/input.fa"

    # set ENA flags
    local set_ena_contigs=''
    local set_ena_scaffolds=''
    local set_ena_chromosomes=''

    # split into contigs
    local split_into_contigs=$(get_meta_conf $META_FILE SPLIT_INTO_CONTIGS)
    if [ -n "$split_into_contigs" -a "$split_into_contigs" -ne 0 ]; then
      perl $METAZOA_DIR/misc/fasta2agp.pl \
        -i $READY_FNA_FILE \
        -o $PIPELINE_DIR \
        -name $ASSEMBLY
      # creates $ASSEMBLY.contigs.fa and $ASSEMBLY.agp

      local has_non_ref=$(get_meta_conf $META_FILE 'HAS_NON_REF')
      if [ -n "$has_non_ref" -a "$has_non_ref" -ne 0 ]; then
        cat $PIPELINE_DIR/$ASSEMBLY.agp > $PIPELINE_DIR/$ASSEMBLY.agp.after_ctg_split
        local NON_REF_IDS_CMD=$(get_meta_conf $META_FILE 'NON_REF_IDS_CMD')
        if [ -z "$NON_REF_IDS_CMD" ]; then
          NON_REF_IDS_CMD='echo'
        fi
        local IDS_LIST="$PIPELINE_DIR/non_ref_ids.lst"
        local cmd2run="cd $ASM_DIR; $NON_REF_IDS_CMD > $IDS_LIST"
        echo "$cmd2run" > $PIPELINE_DIR/non_red_ids.cmd2run
        bash -c "$cmd2run"
        # split agp
        cat $PIPELINE_DIR/$ASSEMBLY.agp.after_ctg_split |
          grep -vF '#' |
          grep -wFf $IDS_LIST > $PIPELINE_DIR/$ASSEMBLY.non_ref_scaffolds.agp
        cat $PIPELINE_DIR/$ASSEMBLY.agp.after_ctg_split |
          grep -vF '#' |
          grep -vwFf $IDS_LIST > $PIPELINE_DIR/$ASSEMBLY.agp
      fi
      set_ena_scaffolds=1
    else
      cat $READY_FNA_FILE > "$PIPELINE_DIR"/${ASSEMBLY}.contigs.fa
      # use existing contigs 2 scaffolds agp
      local CONTIGS_TO_SCAFFOLDS_AGP_FILE=$(get_meta_conf $META_FILE 'CONTIGS_TO_SCAFFOLDS_AGP_FILE')
      if [ -f "$CONTIGS_TO_SCAFFOLDS_AGP_FILE" ]; then
        less "$CONTIGS_TO_SCAFFOLDS_AGP_FILE" > $PIPELINE_DIR/${ASSEMBLY}.agp
      fi
      # same for the non-ref
      local CONTIGS_TO_NON_REF_SCAFFOLDS_AGP_FILE=$(get_meta_conf $META_FILE 'CONTIGS_TO_NON_REF_SCAFFOLDS_AGP_FILE')
      if [ -f "$CONTIGS_TO_NON_REF_SCAFFOLDS_AGP_FILE" ]; then
        less "$CONTIGS_TO_NON_REF_SCAFFOLDS_AGP_FILE" > $PIPELINE_DIR/${ASSEMBLY}.non_ref_scaffolds.agp
      fi
      set_ena_contigs=1
    fi

    # change IUPAC RYKMSWBDHV to N
    cat "$PIPELINE_DIR"/${ASSEMBLY}.contigs.fa |
      gzip - >"$PIPELINE_DIR"/${ASSEMBLY}.contigs.fa.orig.gz
    zcat "$PIPELINE_DIR"/${ASSEMBLY}.contigs.fa.orig.gz |
      perl -pe 'if (!m/^>/) {s/[RYKMSWBDHV]/N/g; s/[rykmswbdhv]/n/g } ' > "$PIPELINE_DIR"/${ASSEMBLY}.contigs.fa

    # no chunking as for now

    SCAFFOLDS_TO_CHROMOSOMES_AGP_FILE=$(get_meta_conf $META_FILE 'SCAFFOLDS_TO_CHROMOSOMES_AGP_FILE')
    if [ -f "$SCAFFOLDS_TO_CHROMOSOMES_AGP_FILE" ]; then
      less "$SCAFFOLDS_TO_CHROMOSOMES_AGP_FILE" > $PIPELINE_DIR/${ASSEMBLY}.chromosome.agp
      set_ena_chromosomes=1
    else
      # load chromosome names as syns
      # change coord systems to chomosome
      cat $META_FILE |
        grep '#CONF' |
        grep 'CONTIG_CHR' |
        perl -pe 's/^\s*#\s*CONF\s+(CONTIG_CHR_[^\s]+)\s.*/$1/' > $PIPELINE_DIR/chr_tags
      local pre_chr_syns=$PIPELINE_DIR/${ASSEMBLY}.chromosome_syns.pre
      local chr_tag=''
      echo -n > $pre_chr_syns
      for chr_tag in $(cat $PIPELINE_DIR/chr_tags); do
        local chr_name=$(echo $chr_tag | cut -f 3 -d '_')
        local ctg_id="$(get_meta_conf $META_FILE $chr_tag)"
        echo -e "$ctg_id\t$chr_name" >> $pre_chr_syns
        # gen_agp_from_scaf $READY_FNA_FILE $ctg_id $chr_name >> $pre_chr_agp
      done
      local pre_chr_syns_lines=$(cat "$pre_chr_syns" | wc -l)
      if [ -s "$pre_chr_syns" -a "$pre_chr_syns_lines" -gt 0 ]; then
        echo -n > $PIPELINE_DIR/${ASSEMBLY}.chromosome.agp
        cat $pre_chr_syns > $PIPELINE_DIR/${ASSEMBLY}.chromosome_syns.tsv
      fi
    fi

    # FN
    # estimate LOWER_CS_RANK
    # circular mt ??

    # load shortcuts
    LOAD_SEQ_REGION_SHORTCUT="perl $ENS_DIR/ensembl-pipeline/scripts/load_seq_region.pl \
      $($CMD details prefix_db) \
      -dbname $DBNAME \
      -coord_system_version $ASSEMBLY \
      -default_version "
    LOAD_AGP_SHORTCUT="perl $ENS_DIR/ensembl-pipeline/scripts/load_agp.pl \
      $($CMD details prefix_db) \
      -dbname $DBNAME \
      -assembled_version $ASSEMBLY "

    # load contigs / sequence data
    $LOAD_SEQ_REGION_SHORTCUT \
      -rank ${RANK} \
      -coord_system_name 'contig' \
      -sequence_level \
      -fasta_file "$PIPELINE_DIR"/${ASSEMBLY}.contigs.fa > "$PIPELINE_DIR"/load_contigs.stdout 2> "$PIPELINE_DIR"/load_contigs.stderr
    tail "$PIPELINE_DIR"/load_contigs.stdout "$PIPELINE_DIR"/load_contigs.stderr
    RANK=$(($RANK - 1))

    # load non_ref_scaffoldss if exist AGP
    if [ -f "${PIPELINE_DIR}/${ASSEMBLY}.non_ref_scaffolds.agp" ] ; then
      $LOAD_SEQ_REGION_SHORTCUT \
        -rank ${RANK} \
        -coord_system_name 'non_ref_scaffold' \
        -agp_file "${PIPELINE_DIR}/${ASSEMBLY}.non_ref_scaffolds.agp" > "$PIPELINE_DIR"/load_non_ref_scaffolds.stdout 2> "$PIPELINE_DIR"/load_non_ref_scaffolds.stderr
      tail "$PIPELINE_DIR"/load_non_ref_scaffolds.stdout "$PIPELINE_DIR"/load_non_ref_scaffolds.stderr
      RANK=$(($RANK - 1))

      ${LOAD_AGP_SHORTCUT} \
        -assembled_name 'non_ref_scaffold' \
        -component_name 'contig' \
        -agp_file "${PIPELINE_DIR}/${ASSEMBLY}.non_ref_scaffolds.agp" > "$PIPELINE_DIR"/load_non_ref_scaffolds_agp.stdout 2> "$PIPELINE_DIR"/load_non_ref_scaffolds_agp.stderr
      tail "$PIPELINE_DIR"/load_non_ref_scaffolds_agp.stdout "$PIPELINE_DIR"/load_non_ref_scaffolds_agp.stderr
    fi

    # load scaffolds if exist AGP
    if [ -f "${PIPELINE_DIR}/${ASSEMBLY}.agp" ] ; then
      $LOAD_SEQ_REGION_SHORTCUT \
        -rank ${RANK} \
        -coord_system_name 'scaffold' \
        -agp_file "${PIPELINE_DIR}/${ASSEMBLY}.agp"  > "$PIPELINE_DIR"/load_scaffold.stdout 2> "$PIPELINE_DIR"/load_scaffold.stderr
      tail "$PIPELINE_DIR"/load_scaffold.stdout "$PIPELINE_DIR"/load_scaffold.stderr

      RANK=$(($RANK - 1))

      ${LOAD_AGP_SHORTCUT} \
        -assembled_name 'scaffold' \
        -component_name 'contig' \
        -agp_file "${PIPELINE_DIR}/${ASSEMBLY}.agp" > "$PIPELINE_DIR"/load_scaffold_agp.stdout 2> "$PIPELINE_DIR"/load_scaffold_agp.stderr
      tail "$PIPELINE_DIR"/load_scaffold_agp.stdout "$PIPELINE_DIR"/load_scaffold_agp.stderr

    fi

    # load linkage groups???
    # chromosome from contigs ???

    # load chromosomes if exists AGP
    if [ -f "${PIPELINE_DIR}/${ASSEMBLY}.chromosome.agp" ] ; then
      if [ "$RANK" -lt 1 ]; then
        echo "failing. rank for 'crhomosome' CS is $RANK" > /dev/stderr
      fi

      RANK=1
      $LOAD_SEQ_REGION_SHORTCUT \
        -rank ${RANK} \
        -coord_system_name 'chromosome' \
        -agp_file "${PIPELINE_DIR}/${ASSEMBLY}.chromosome.agp" > "$PIPELINE_DIR"/load_chromosome.stdout 2> "$PIPELINE_DIR"/load_chromosome.stderr
      tail "$PIPELINE_DIR"/load_chromosome.stdout "$PIPELINE_DIR"/load_chromosome.stderr

      ${LOAD_AGP_SHORTCUT} \
        -assembled_name 'chromosome' \
        -component_name 'scaffold' \
        -agp_file "${PIPELINE_DIR}/${ASSEMBLY}.chromosome.agp" > "$PIPELINE_DIR"/load_chromosome_agp.stdout 2> "$PIPELINE_DIR"/load_chromosome_agp.stderr
      tail "$PIPELINE_DIR"/load_chromosome_agp.stdout "$PIPELINE_DIR"/load_chromosome_agp.stderr
    fi

    # update ENA seq_region_attrib
    local not_set_ena=$(get_meta_conf $META_FILE NOT_SET_ENA)
    if [ -n "$not_set_ena" -a "$not_set_ena" -ne 0 ]; then
      echo NOT SETTING ENA SYNONIMS FLAGS because of the META:CONF:NOT_SET_ENA > /dev/stderr
    else
      [ -n "$set_ena_contigs" ] && update_ena_attrib_for_cs $CMD $DBNAME 'contig' || true
      [ -n "$set_ena_scaffolds" ] && update_ena_attrib_for_cs $CMD $DBNAME 'scaffold' || true
      [ -n "$set_ena_scaffolds" ] && update_ena_attrib_for_cs $CMD $DBNAME 'non_ref_scaffold' || true
      [ -n "$set_ena_chromosomes" ] && update_ena_attrib_for_cs $CMD $DBNAME 'chromosome' || true
    fi

    # set non_ref (16) seq_region_attrib
    $CMD -D $DBNAME -e 'insert into seq_region_attrib (seq_region_id, attrib_type_id, value) select sr.seq_region_id, "16", "1" from seq_region sr, coord_system cs where sr.coord_system_id = cs.coord_system_id and cs.name = "non_ref_scaffold";'

    # set top_level(6) seq_region_attrib
    perl $ENSEMBL_ROOT_DIR/ensembl-pipeline/scripts/set_toplevel.pl \
       $($CMD details prefix_db) \
       -dbname $DBNAME \
       -ignore_coord_system contig \
       -ignore_coord_system non_ref_scaffold \
       >  "$PIPELINE_DIR"/set_toplevel.stdout 2> "$PIPELINE_DIR"/set_toplevel.stderr
       # ???
    tail "$PIPELINE_DIR"/set_toplevel.stdout "$PIPELINE_DIR"/set_toplevel.stderr

    # add chromosome synonyms if exist, using VB_Community_Symbol (211) as external_db_id
    # change coord sys to chromosome
    echo -n > $PIPELINE_DIR/update_chromosome_syns.sql
    if [ -f  "$PIPELINE_DIR/${ASSEMBLY}.chromosome_syns.tsv" ]; then
      non_ref_cs_id=$($CMD -D $DBNAME -N -e 'select coord_system_id from coord_system where name = "non_ref_scaffold"')
      chr_cs_id=$($CMD -D $DBNAME -N -e 'select coord_system_id from coord_system where name = "chromosome"')
      cat "$PIPELINE_DIR/${ASSEMBLY}.chromosome_syns.tsv" |
        awk -F "\t" -v non_ref_cs_id=$non_ref_cs_id -v chr_cs_id=$chr_cs_id '($2 != $1) {
            printf("insert into seq_region_synonym (seq_region_id, synonym, external_db_id) select sr.seq_region_id, \"%s\", 211 from seq_region sr where sr.name = \"%s\";\n", $2 , $1); }
            { if (chr_cs_id) {
              printf("update seq_region set coord_system_id = %s where name = \"%s\";\n", chr_cs_id, $1);
              printf("insert into seq_region_attrib (seq_region_id, attrib_type_id, value) select sr.seq_region_id, 367, %d from seq_region sr where sr.name = \"%s\";\n", NR,$1); # 367 karyotype_rank
            }
          }' > $PIPELINE_DIR/update_chromosome_syns.sql

      if  [ -s $PIPELINE_DIR/update_chromosome_syns.sql ]; then
        echo 'insert into meta (species_id, meta_key, meta_value) values (1, "assembly.mapping", "chromosome:'${ASSEMBLY}'|contig");' >> $PIPELINE_DIR/update_chromosome_syns.sql

        cat $PIPELINE_DIR/update_chromosome_syns.sql | $CMD -D $DBNAME
      fi
    fi

    # add circular and alt coded attribs for MT
    echo -n > $PIPELINE_DIR/update_mt_attribs.sql
    MT_CIRCULAR="$(get_meta_conf $META_FILE 'MT_CIRCULAR')"
    MT_CODON_TABLE="$(get_meta_conf $META_FILE 'MT_CODON_TABLE')"
    if [ -n "$MT_CIRCULAR" -a "$MT_CIRCULAR" = "YES" ]; then
      cat "$PIPELINE_DIR/${ASSEMBLY}.chromosome_syns.tsv" |
        grep -iP '\tMT$' | cut -f 1 |
        awk -F "\t" '{
              printf("insert into seq_region_attrib (seq_region_id, attrib_type_id, value) select sr.seq_region_id, 316, 1 from seq_region sr where sr.name = \"%s\";\n", $1); # 316 circular_seq
            }' >> $PIPELINE_DIR/update_mt_attribs.sql
    fi
    if [ -n "$MT_CODON_TABLE" ]; then
      cat "$PIPELINE_DIR/${ASSEMBLY}.chromosome_syns.tsv" |
        grep -iP '\tMT$' | cut -f 1 |
        awk -F "\t" -v codon_table="$MT_CODON_TABLE" '{
              printf("insert into seq_region_attrib (seq_region_id, attrib_type_id, value) select sr.seq_region_id, 11, %s from seq_region sr where sr.name = \"%s\";\n", codon_table, $1); # 11 codon_table
            }' >> $PIPELINE_DIR/update_mt_attribs.sql
    fi
    if  [ -s $PIPELINE_DIR/update_mt_attribs.sql ]; then
      cat $PIPELINE_DIR/update_mt_attribs.sql | $CMD -D $DBNAME
    fi

    # nullify contig version
    $CMD $DBNAME -e "update meta set meta_value=replace(meta_value, \"|contig:$ASSEMBLY\", \"|contig\") where meta_key=\"assembly.mapping\";"
    $CMD $DBNAME -e "update coord_system set version = NULL where name=\"contig\";"

    if [ -f "${PIPELINE_DIR}/${ASSEMBLY}.agp" ] ; then
      $CMD $DBNAME -e "insert ignore into meta (species_id, meta_key, meta_value) values (1, \"assembly.mapping\", \"scaffold:$ASSEMBLY|contig\");"
    fi
    if [ -f "${PIPELINE_DIR}/${ASSEMBLY}.non_ref_scaffolds.agp" ] ; then
      $CMD $DBNAME -e "insert ignore into meta (species_id, meta_key, meta_value) values (1, \"assembly.mapping\", \"non_ref_scaffold:$ASSEMBLY|contig\");"
    fi
    if [ -f "${PIPELINE_DIR}/${ASSEMBLY}.chromosome.agp" ] ; then
      local keep_ctg_scf_chr_mapping=$(get_meta_conf $META_FILE KEEP_CTG_SCF_CHR_MAPPING)
      if [ -s $PIPELINE_DIR/update_chromosome_syns.sql -a -n "$keep_ctg_scf_chr_mapping" -a "$keep_ctg_scf_chr_mapping" -ne 0 ]; then
          echo 'keeping "chromosome:'${ASSEMBLY}'|scaffold:'${ASSEMBLY}'|contig" assembly mapping path ("assembly.mapping")' > /dev/stderr
          $CMD $DBNAME -e "insert ignore into meta (species_id, meta_key, meta_value) values (1, \"assembly.mapping\", \"chromosome:$ASSEMBLY|scaffold:$ASSEMBLY|contig\");"
        else
          echo 'removing "chromosome:'${ASSEMBLY}'|scaffold:'${ASSEMBLY}'|contig" assembly mapping path ("assembly.mapping")' > /dev/stderr
          $CMD $DBNAME -e 'delete from meta where meta_key="assembly.mapping" and meta_value="chromosome:'${ASSEMBLY}'|scaffold:'${ASSEMBLY}'|contig";'
        fi
    fi
    # update INSDC synonims
    local i=''
    for i in {1..9}; do
      $CMD -D $DBNAME -e 'insert into seq_region_synonym (seq_region_id, synonym, external_db_id) select sr.seq_region_id, sr.name as synonym, edb.external_db_id from seq_region as sr, external_db as edb where edb.db_name = "INSDC" and sr.name like "%.'${i}'" and sr.coord_system_id in (select coord_system_id from coord_system where version = "'${ASSEMBLY}'") '
      $CMD -D $DBNAME -e 'update seq_region set name = replace(name, ".'${i}'", "") where name like  "%.'${i}'" and coord_system_id in (select coord_system_id from coord_system where version = "'${ASSEMBLY}'") '
    done

    touch_done _load_dna_sequences
  fi
}


function gen_agp_from_scaf () {
  local FNA_FILE="$1"
  local CONTIG_ID="$2"
  local CHR_NAME="$3"
  cat $FNA_FILE |
   fasta2sl |
   grep -wF "$CONTIG_ID" |
   awk -F "\t" \
     -v chr_name="$CHR_NAME" \
     -v contig_id="$CONTIG_ID" \
     '{OFS="\t"; len = length($2); print chr_name, 1, len, 0, "W", contig_id, 1, len, "+"}'
}

function get_old_syns_from_db () {
  local CMD="$1"
  local DBNAME="$2"
  local OUTFILE="$3"

  if ! check_done _get_old_syns_from_db; then
    echo "saving old syns from $CMD:$DBNAME to $OUTFILE" > /dev/stderr
      local outdir=$(dirname $OUTFILE)
      mkdir -p $outdir
      $CMD $DBNAME -e "select sr.name, srs.synonym, srs.external_db_id from seq_region sr, seq_region_synonym srs where sr.seq_region_id = srs.seq_region_id" > $OUTFILE
    touch_done _get_old_syns_from_db
  fi
}

function load_region_syns () {
  local CMD="$1"
  local DBNAME="$2"
  local SYNS_FILE="$3"
  local OUT_DIR="$4"
  local TAG="$5"

  local DONE_TAG='_load_region_syns'${TAG}
  if ! check_done "$DONE_TAG"; then
    echo "loading region syns from $SYNS_FILE" > /dev/stderr
    mkdir -p $OUT_DIR
    $CMD $DBNAME -e "select sr.name, srs.synonym from seq_region sr, seq_region_synonym srs where sr.seq_region_id = srs.seq_region_id" -N  > $OUT_DIR/new_syns.tsv
    cat "$SYNS_FILE" | grep -vwFf $OUT_DIR/new_syns.tsv > $OUT_DIR/syns_filtered.tsv

    $CMD $DBNAME -e 'drop table if exists tmp_map;'
    $CMD $DBNAME -e 'create table tmp_map (seqname varchar(255), acc varchar(255), ext_db_id int(10) );'
    $CMD $DBNAME -e 'load data local infile "'${OUT_DIR}/syns_filtered.tsv'" into table tmp_map ignore 1 lines;'
    $CMD $DBNAME -e 'insert into seq_region_synonym (seq_region_id, synonym, external_db_id) select sr.seq_region_id, tmp.acc, tmp.ext_db_id from seq_region sr, tmp_map tmp where tmp.seqname = sr.name'
    $CMD $DBNAME -e 'drop table tmp_map;'
    touch_done "$DONE_TAG"
  fi
}

function update_ena_attrib_for_cs () {
  local CMD="$1"
  local DBNAME="$2"
  local CSNAME="$3"

  echo "updating seq_region ENA attributes in $DBNAME for $CSNAME" > /dev/stderr
  $CMD -D $DBNAME -e 'insert into seq_region_attrib (seq_region_id, attrib_type_id, value) select sr.seq_region_id, "317", "ENA" from seq_region sr, coord_system cs where sr.coord_system_id = cs.coord_system_id and cs.name = "'"$CSNAME"'";'
}

function update_ena_seq_attrib () {
  local CMD="$1"
  local DBNAME="$2"
  if ! check_done _update_ena_seq_attrib; then
    echo "updating seq_region ENA attributes in $DBNAME" > /dev/stderr
    # Set ENA attrib for non chromosomal ids (i.e. contigs +supercontigs)
    $CMD -D $DBNAME -e 'insert into seq_region_attrib (seq_region_id, attrib_type_id, value) select sr.seq_region_id, "317", "ENA" from seq_region sr  where sr.name not in ("X", "2R", "2L", "3R", "3L", "2RL", "3RL", "MT", "Mt");'
    touch_done _update_ena_seq_attrib
  fi
}

function gff_keep_only_tags () {
  local PAT="$1"
  perl -ne 'use strict; if (m/^\s*#/) { print; } else {
    chomp;
    my @all = split /\t/;
    my $last = pop @all;
    $last = join(";", grep( /^(?:'"$PAT"')=/, split(/;/, $last)));
    print join ("\t", @all, $last), "\n";
  } '
}

function filter_gff () {
  local GFF_FILE="$1"
  local IGNORE_FILE="$2"
  local OUT_DIR="$3"
  local OUT_FILE="$4"
  local KEEP_TAGS_OVRRD="$5"
  local TAG="$6"

  local KEEP_TAGS='ID|Parent|protein_id|Name|product|description'
  if [ -n "$KEEP_TAGS_OVRRD" ]; then
    KEEP_TAGS="$KEEP_TAGS_OVRRD"
  fi

  local DONE_TAG='_filter_gff'${TAG}
  if ! check_done "$DONE_TAG"; then
    echo "filtering GFF3 file $GFF_FILE into " > /dev/stderr
    echo "leaving only $KEEP_TAGS tags " > /dev/stderr
    mkdir -p "$OUT_DIR"
    cat $IGNORE_FILE |
      perl -pe 's/#.*$/\n/; s/^\s+//; s/ +$//; s/ +/ /g;' |
      grep -vP '^\s*$' |
      perl -pe 's/^/\t/; s/$/\t/' > "$OUT_DIR/tmp.pat"

    # remove ignored entities
    # change VectorBase to vectorbase_maker
    # remove everything but ID|Parent|protein_id|product
    # remove IDs for introns,exons,CDS
    # change "nontranslating_CDS" to mRNA biotype="nontranslating_CDS"
    # change "pseudogene" to "pseudogenic_trascript"
    # fix ensembl protein ids for CDS
    # xref display ID /??
    less $GFF_FILE |
      grep -viF -f "$OUT_DIR/tmp.pat" |
      perl -pe 's/VectorBase/vectorbase_maker/' |
      gff_keep_only_tags "$KEEP_TAGS" |
      perl -pe 's/ID=[^;]+;// if m/\t(?:Intron|exon|CDS)\t/' |
      perl -pe '$p = "nontranslating_CDS"; if (m/\t$p\t/) {s/$p/mRNA/; s/$/;biotype=$p/;}' |
      perl -pe 's/\tpseudogene\t/\tpseudogenic_transcript\t/' |
      perl -pe 's/ID=\w+-PA;?//g' |
      perl -pe 'if (m/\tCDS\t/ && m/Parent=([^-\s;]+)-R(\w)/) {chomp; my $id = $1."-P".$2; s/(\t|;)ID=[^;]+(?:;|$)/$1/; $_ = $_ . ";ID=$id;protein_id=$id\n";}' > "${OUT_DIR}/${OUT_FILE}"
      # sort | uniq |
      # sort -k1,1 -k4,4n -k5,5nr

    touch_done "$DONE_TAG"
  fi
}

function fix_gff_ids () {
  local GENE_FROM_PFX="$1"
  local GENE_TO_PFX="$2"
  local GFF_FILE="$3"
  local OUT_DIR="$4"
  local OUT_FILE="$5"
  # local MAX_HISTORICAL_GENE_ID="$6"

  if ! check_done _fix_gff_ids; then
    echo "filtering GFF3 file $GFF_FILE into " > /dev/stderr

    local max_seen_gene_id=$(less $GFF_FILE | perl -e '
        use strict;
        my $gene_cnt = 0;
        my $max_num_part = 0;
        while(<STDIN>) {
          if (m/\tgene\t/) {
            my $id = $1 if m/ID=([^;]+)/;
            my $num_part = $1 if ($id =~ m/(\d+)(?:_|$)/);
            $max_num_part = $num_part if ($num_part && $num_part > $max_num_part);
            $gene_cnt++;
          }
        }
        printf "%d\n", (($gene_cnt > $max_num_part)? $gene_cnt : $max_num_part);
      ')

    # TODO: get max ids from old_core_db:
    # select max(stable_id) from gene;
    # select max(old_stable_id) from stable_id_event where type = "gene";
    # select max(new_stable_id) from stable_id_event where type = "gene";
    # select max(gene_stable_id) from gene_archive;


    less $GFF_FILE |
      perl -e '
        my $gene_cnt = 1;
        my $next_max_gene_id = '${max_seen_gene_id}'+100;
        while (<STDIN>) {
          if (m/\tgene\t/) {
            $old_gene_id = $1 if m/ID=([^;]+)/;
            $seen = 0;
            ($num_part, $gene_part) = ($1, $2) if ($old_gene_id =~  m/'"$GENE_FROM_PFX"'(\d+)(?:_p(\d+))?/ );
            $num_part = $gene_cnt if (length("$num_part") < 6);
            $num_part = $next_max_gene_id++ if ($gene_part && $gene_part > 1);

            $gene_id = sprintf("'"$GENE_TO_PFX"'%06d", $num_part);
            $gene_cnt++;
            s/(;|\t)(ID=[^;]+)/$1ID=$gene_id;orig_$2/;
          }
          if (m/\tmRNA\t/) {
            $old_mrna_id = $1 if m/ID=([^;]+);/;
            # TODO: keep if name is ok
            $mrna_id = $old_mrna_id;
            $mrna_id = $gene_id."-R".chr(ord("A") + $seen) if ($mrna_id !~ m/${gene_id}-R/);
            $seen++;
            s/(;|\t)(ID=[^;]+)/$1ID=$mrna_id;orig_$2/;
            s/(;|\t)(Parent=[^;]+)/$1Parent=$gene_id;orig_$2/
          }
          if (m/\t(?:exon|CDS)\t/) {
            s/(;|\t)(Parent=[^;]+)/$1Parent=$mrna_id;orig_$2/;
            s/(;|\t)(ID=[^;]+)(?:;|$)/$1/;
            s/(;|\t)(protein_id=[^;]+)(?:;|$)/$1/;
          }
          s/[\n\r]*$/\n/;
          print $_;
        }
        ' > "$OUT_DIR/$OUT_FILE"

    touch_done _fix_gff_ids
  fi
}

function interpolate_reg_conf () {
  local CMD_SERVER="$1"
  local DBNAME="$2"
  local SPECIES="$3"
  local DBNAME_2="$4"
  local SPECIES_2="$5"
  local COMPARA_NAME="$6"
  local DB_PREFIX="$7"
  perl -pe 's/CMD_SERVER/'"$CMD_SERVER"'/g' |
    perl -pe 's/PROD_SERVER/'"$PROD_SERVER"'/g' |
    perl -pe 's/PROD_DBNAME/'"$PROD_DBNAME"'/g' |
    perl -pe 's/SPECIES_DB_NAME/'"$DBNAME"'/g' |
    perl -pe 's/SPECIES_NAME/'"$SPECIES"'/g' |
    perl -pe 's/SPECIES_2_DB_NAME/'"$DBNAME_2"'/g' |
    perl -pe 's/SPECIES_2_NAME/'"$SPECIES_2"'/g' |
    perl -pe 's/COMPARA_NAME/'"$COMPARA_NAME"'/g' |
    perl -pe 's/DB_PREFIX/'"$DB_PREFIX"'/g' |
    perl -pe 'if (m/^\s*SUB/) {s/^\s*SUB\s+(.+)\s*$/@{[eval {`$1`}]}/;}'
}

function gen_one_db_reg_conf () {
  local CMD="$1"
  local DBNAME="$2"
  local SPECIES="$3"
  local OUTFILE="$4"

  local outdir=$(dirname $OUTFILE)
  mkdir -p $outdir

  cat > ${OUTFILE}.pre << 'EOF'
    use strict;
    use warnings;
    use Bio::EnsEMBL::DBSQL::DBAdaptor;
    use Bio::EnsEMBL::Registry;
    Bio::EnsEMBL::Registry->no_version_check(1);
    Bio::EnsEMBL::Registry->no_cache_warnings(1);
    {
      Bio::EnsEMBL::DBSQL::DBAdaptor->new(
        SUB CMD_SERVER details env | perl -pe '$_=lc($_); s/^/-/;  s/=/ => "/; s/$/", / '
        -dbname  => 'SPECIES_DB_NAME',
        -species => 'SPECIES_NAME',
        -group   => 'core',
      );
      Bio::EnsEMBL::DBSQL::DBAdaptor->new(
        SUB PROD_SERVER details env | perl -pe '$_=lc($_); s/^/-/;  s/=/ => "/; s/$/", / '
        -dbname  => 'PROD_DBNAME',
        -species => 'multi',
        -group   => 'production',
      );
      Bio::EnsEMBL::Registry->load_registry_from_db(
        SUB PROD_SERVER details env | perl -pe '$_=lc($_); s/^/-/;  s/=/ => "/; s/$/", / '
        -species => 'multi',
        -group   => 'metadata',
      );
      Bio::EnsEMBL::Registry->load_registry_from_db(
        SUB PROD_SERVER details env | perl -pe '$_=lc($_); s/^/-/;  s/=/ => "/; s/$/", / '
        -species => 'multi',
        -group   => 'taxonomy',
      );
    }
    1;
EOF

cat ${OUTFILE}.pre |
  interpolate_reg_conf "$CMD" "$DBNAME" "$SPECIES" > ${OUTFILE}
}

function print_ontology_reg_entry () {
  local CMD="$1"
  local DBNAME="$2"

  cat << 'EOF' | interpolate_reg_conf "$CMD" "$DBNAME"
    use Bio::EnsEMBL::DBSQL::OntologyDBAdaptor;
    {
      Bio::EnsEMBL::DBSQL::OntologyDBAdaptor->new(
        SUB CMD_SERVER details env | perl -pe '$_=lc($_); s/^/-/;  s/=/ => "/; s/$/", / '
        -dbname  => 'SPECIES_DB_NAME',
        -species => 'multi',
        -group   => 'ontology',
      );
    }
    1;
EOF
}

function gen_one_species_reg_conf () {
  local CMD="$1"
  local SPECIES="$2"
  local OUTFILE="$3"

  local outdir=$(dirname $OUTFILE)
  mkdir -p $outdir

  cat > ${OUTFILE}.pre << 'EOF'
    use strict;
    use warnings;
    use Bio::EnsEMBL::Registry;
    Bio::EnsEMBL::Registry->no_version_check(1);
    Bio::EnsEMBL::Registry->no_cache_warnings(1);
    {
      Bio::EnsEMBL::Registry->load_registry_from_db(
        SUB CMD_SERVER details script | perl -pe 's/--/-/g; s/(?:[ ^])-/\n-/g' | perl -pe 's/^(-\S+)\s+(\S+)$/\U$1\E => "$2",/;';
        -SPECIES => 'SPECIES_NAME',
        -VERBOSE => 1,
      );
      Bio::EnsEMBL::DBSQL::DBAdaptor->new(
        SUB PROD_SERVER details env | perl -pe '$_=lc($_); s/^/-/;  s/=/ => "/; s/$/", / '
        -dbname  => 'PROD_DBNAME',
        -species => 'multi',
        -group   => 'production'
      );
    }
    1;
EOF

cat ${OUTFILE}.pre |
  interpolate_reg_conf "$CMD" "" "$SPECIES" > ${OUTFILE}
}

function gen_two_db_compara_reg_conf () {
  local CMD="$1"
  local DBNAME="$2"
  local SPECIES="$3"
  local DBNAME_2="$4"
  local SPECIES_2="$5"
  local COMPARA_NAME="$6"
  local OUTFILE="$7"

  local outdir=$(dirname $OUTFILE)
  mkdir -p $outdir

  cat > ${OUTFILE}.pre << 'EOF'
    use strict;
    use warnings;
    use Bio::EnsEMBL::Compara::DBSQL::DBAdaptor;
    use Bio::EnsEMBL::DBSQL::DBAdaptor;
    use Bio::EnsEMBL::Registry;
    Bio::EnsEMBL::Registry->no_version_check(1);
    Bio::EnsEMBL::Registry->no_cache_warnings(1);
    {
      Bio::EnsEMBL::DBSQL::DBAdaptor->new(
        SUB CMD_SERVER details env | perl -pe '$_=lc($_); s/^/-/;  s/=/ => "/; s/$/", / '
        -dbname  => 'SPECIES_DB_NAME',
        -species => 'SPECIES_NAME',
        -group   => 'core',
      );
      Bio::EnsEMBL::DBSQL::DBAdaptor->new(
        SUB CMD_SERVER details env | perl -pe '$_=lc($_); s/^/-/;  s/=/ => "/; s/$/", / '
        -dbname  => 'SPECIES_2_DB_NAME',
        -species => 'SPECIES_2_NAME',
        -group   => 'core',
      );
      Bio::EnsEMBL::Compara::DBSQL::DBAdaptor->new(
        SUB CMD_SERVER details env | perl -pe '$_=lc($_); s/^/-/;  s/=/ => "/; s/$/", / '
        -dbname  => 'COMPARA_NAME',
        -group   => 'compara',
        -species => 'multi',
      );
    }
    1;
EOF

cat ${OUTFILE}.pre |
  interpolate_reg_conf "$CMD" "$DBNAME" "$SPECIES" "$DBNAME_2" "$SPECIES_2" "$COMPARA_NAME" "" > ${OUTFILE}
}

function gen_pfx_reg_conf () {
  local CMD="$1"
  local DB_PREFIX="$2"
  local OUTFILE="$3"

  local outdir=$(dirname $OUTFILE)
  mkdir -p $outdir

  cat > ${OUTFILE}.pre << 'EOF'
    use strict;
    use warnings;
    use Bio::EnsEMBL::DBSQL::DBAdaptor;
    use Bio::EnsEMBL::Registry;
    Bio::EnsEMBL::Registry->no_version_check(1);
    Bio::EnsEMBL::Registry->no_cache_warnings(1);
    {
      Bio::EnsEMBL::DBSQL::DBAdaptor->new(
        SUB PROD_SERVER details env | perl -pe '$_=lc($_); s/^/-/;  s/=/ => "/; s/$/", / '
        -dbname  => 'PROD_DBNAME',
        -species => 'multi',
        -group   => 'production',
      );
      Bio::EnsEMBL::Registry->load_registry_from_db(
        SUB PROD_SERVER details env | perl -pe '$_=lc($_); s/^/-/;  s/=/ => "/; s/$/", / '
        -species => 'multi',
        -group   => 'metadata',
      );
      Bio::EnsEMBL::Registry->load_registry_from_db(
        SUB PROD_SERVER details env | perl -pe '$_=lc($_); s/^/-/;  s/=/ => "/; s/$/", / '
        -species => 'multi',
        -group   => 'taxonomy',
      );
      Bio::EnsEMBL::Registry->load_registry_from_db(
        SUB CMD_SERVER details env | perl -pe '$_=lc($_); s/^/-/;  s/=/ => "/; s/$/", / '
        -db_prefix => 'DB_PREFIX',
        -group   => 'core',
      );

    }
    1;
EOF

cat ${OUTFILE}.pre |
  interpolate_reg_conf "$CMD" "$DBNAME" "$SPECIES" '' '' '' "$DB_PREFIX" > ${OUTFILE}
}

function gen_pep_mapping () {
   grep -v '#' |
     awk -F "\t" '$3 == "CDS" {print $9}' |
     perl -ne '
       chomp;
       $data = { map {  m/(.*)=(.*)/; $1 => $2 } grep /^(?:ID|Name|Parent|orig_Parent|product|description)=/, split /;/, $_ };
       if (!$data->{Name}) {
         $data->{Name} = $data->{orig_Parent};
         #$data->{Name} =~ s/-R/-P/;
       }
       $data->{product} = $data->{description} if (!$data->{product});
       print join("\t", @$data{qw/Parent Name Parent orig_Parent product/}), "\n"' |
     perl -pe 's/^([^\t]+)-R(\w)\t/$1-P$2\t/' |
     sort | uniq
}

function gen_gene_mapping () {
   grep -v '#' |
     awk -F "\t" '$3 == "gene" {print $9}' |
     perl -ne '
       chomp;
       $data = { map {  m/(.*)=(.*)/; $1 => $2 } grep /^(?:ID|orig_ID|Name|description)=/, split /;/, $_ };
       $data->{Name} = $data->{orig_ID} if (!$data->{Name});
       print join("\t", @$data{qw/ID Name orig_ID description/}), "\n"' |
     sort | uniq
}

function gen_mappings_from_gff () {
  local GFF="$1"
  local OUT_DIR="$2"

  local DONE_TAG='_gen_mappings_from_gff'
  if ! check_done "$DONE_TAG"; then
    mkdir -p "$OUT_DIR"
    echo "generating gene mappings from $GFF" > /dev/stderr
    cat $GFF | gen_gene_mapping > $OUT_DIR/gene_orig_mapping.tsv
    echo "generating peptides mappings from $GFF" > /dev/stderr
    cat $GFF | gen_pep_mapping > $OUT_DIR/pep_orig_mapping.tsv
    touch_done "$DONE_TAG"
  fi
}

function fix_pep_names () {
  local MAP="$1"
  local PEP_FILE="$2"
  local OUTFILE="$3"

  local DONE_TAG='_fix_pep_names'
  if ! check_done "$DONE_TAG"; then
    if [ ! -s "$PEP_FILE"  ]; then
      PEP_FILE=/dev/null
    fi
    echo "fixing pep names in $PEP_FILE using $MAP to $OUTFILE" > /dev/stderr
      local outdir=$(dirname $OUTFILE)
      mkdir -p $outdir
      ( cut -f 1,2 $MAP; less $PEP_FILE ) |
          awk 'BEGIN {go = 0 } (!go) {r[">"$2] = ">"$1} (/^>/) {go = 1; $1 = r[$1]; if ($1) {print} else {go = 0}} (!/^>/ && go) {print}' > $OUTFILE

    touch_done "$DONE_TAG"
  fi
}

function load_gff () {
  local CMD="$1"
  local DBNAME="$2"
  local SPECIES="$3"
  local GFF_FILE="$4"
  local FNA_FILE="$5"
  local PEP_FILE="$6"
  local EG_DIR="$7"
  local OUT_DIR="$8"
  local LOGIC_NAME_O="$9"
  local GENE_SOURCE_O="${10}"

  local LOGIC_NAME='vectorbase_maker'
  if [ -n "$LOGIC_NAME_O" ]; then
    LOGIC_NAME="$LOGIC_NAME_O"
  fi

  local GENE_SOURCE='VectorBase'
  if [ -n "$GENE_SOURCE_O" ]; then
    GENE_SOURCE="$GENE_SOURCE_O"
  fi

  if ! check_done _load_gff; then
    echo "loading GFF3 file $GFF_FILE into $DBNAME " > /dev/stderr

    mkdir -p $OUT_DIR/prereqs

    local fna_gzipped=$(file -b $FNA_FILE | grep -o ^gzip)
    if [ -n "$fna_gzipped" -a "$fna_gzipped" = "gzip" ]; then
      zcat $FNA_FILE > $OUT_DIR/prereqs/fna.fasta
    else
      cat $FNA_FILE > $OUT_DIR/prereqs/fna.fasta
    fi

    local pep_gzipped=$(file -b $PEP_FILE | grep -o ^gzip)
    if [ -n "$pep_gzipped" -a "$pep_gzipped" = "gzip" ]; then
      zcat $PEP_FILE > $OUT_DIR/prereqs/pep.fasta
    else
      cat $PEP_FILE > $OUT_DIR/prereqs/pep.fasta
    fi

    local REG_FILE=$OUT_DIR/prereqs/reg.conf
    gen_one_db_reg_conf $CMD $DBNAME $SPECIES $REG_FILE

    init_pipeline.pl Bio::EnsEMBL::EGPipeline::PipeConfig::LoadGFF3_conf \
      $($CMD details script) \
      -production_db "$($PROD_SERVER details url)""$PROD_DBNAME" \
      -hive_force_init 1 \
      -registry $REG_FILE \
      -pipeline_dir $OUT_DIR \
      -species $SPECIES \
      -gff3_file $GFF_FILE \
      -fasta_file $OUT_DIR/prereqs/fna.fasta \
      -protein_fasta_file $OUT_DIR/prereqs/pep.fasta \
      -gene_source ${GENE_SOURCE} \
      -logic_name ${LOGIC_NAME} \
      -ignore_types golden_path_region \
      -ignore_types intron \
      -ignore_types orthologous_to \
      -biotype_report_filename $OUT_DIR/reports/biotype_report.txt \
      -seq_edit_tt_report_filename $OUT_DIR/reports/seq_edit_tt_report.txt \
      -seq_edit_tn_report_filename $OUT_DIR/reports/seq_edit_tn_report.txt \
      -protein_seq_report_filename $OUT_DIR/reports/protein_seq_report.txt \
      -protein_seq_fixes_filename $OUT_DIR/reports/protein_seq_fixes.txt \
      2> $OUT_DIR/init.stderr \
      1> $OUT_DIR/init.stdout
    tail $OUT_DIR/init.stderr $OUT_DIR/init.stdout

    local SYNC_CMD=$(cat $OUT_DIR/init.stdout | grep -- -sync'$' | perl -pe 's/^\s*//')
    local LOOP_CMD=$(cat $OUT_DIR/init.stdout | grep -- -loop | perl -pe 's/^\s*//; s/\s*#.*$//')

    echo "$SYNC_CMD" > $OUT_DIR/_continue_pipeline
    echo "$LOOP_CMD" >> $OUT_DIR/_continue_pipeline
    echo "touch $DONE_TAGS_DIR/_load_gff" >> $OUT_DIR/_continue_pipeline

    echo Running pipeline...  > /dev/stderr
    echo See $OUT_DIR/_continue_pipeline if failed...  > /dev/stderr
    cat $OUT_DIR/_continue_pipeline > /dev/stderr

    $SYNC_CMD \
      2> $OUT_DIR/sync.stderr \
      1> $OUT_DIR/sync.stdout
    tail $OUT_DIR/sync.stderr $OUT_DIR/sync.stdout

    $LOOP_CMD \
      2> $OUT_DIR/loop.stderr \
      1> $OUT_DIR/loop.stdout
    tail $OUT_DIR/loop.stderr $OUT_DIR/loop.stdout

    export PROTEIN_SEQEDITS_FILE="$OUT_DIR/reports/protein_seq_fixes.txt"
    echo "$PROTEIN_SEQEDITS_FILE" > $OUT_DIR/_protein_seqedits_file

    touch_done _load_gff
  fi
}

function apply_protein_seq_fixes () {
  local CMD="$1"
  local DBNAME="$2"
  local FIXFILE="$3"

  local DONE_TAG='_apply_protein_seq_fixes'
  if ! check_done "$DONE_TAG"; then
    echo "applying protein seq edits $FIX_FILE to $DBNAME" > /dev/stderr
      cat $FIXFILE |
        $CMD $DBNAME
    touch_done "$DONE_TAG"
  fi
}

function find_missing_canonical_tr () {
  local CMD="$1"
  local DBNAME="$2"
  local OUT_DIR="$3"
  local OUT_FILE="$4"

  local DONE_TAG='_find_missing_canonical_tr'
  if ! check_done "$DONE_TAG"; then
    echo "finding missing canonical transcripts in $DBNAME" > /dev/stderr
      mkdir -p "$OUT_DIR"
      $CMD -D $DBNAME -e '
          select
            tr.seq_region_id,
            tr.transcript_id,
            tr.gene_id,
            tr.stable_id,
            tr.seq_region_end - tr.seq_region_start as len,
            tr.biotype,
            gene.canonical_transcript_id
          from
            transcript tr,
            gene
          where
            gene.gene_id = tr.gene_id
            and gene.canonical_transcript_id = 0' |
        tail -n +2  |
        sort -k1,1 -k3,3n -k6,6 -k5,5nr |
        awk -F "\t" '($6 == "protein_coding" && !seen[$3]) { seen[$3] = $0 }
                     (!seen[$3] && !seen_nc[$3]) { seen_nc[$3] = $0 }
                     END { for (k in seen) { print seen[k] }
                           for (k in seen_nc) {if (!seen[k]) {print seen_nc[k]} }
                     }' > "$OUT_DIR/$OUT_FILE"
      # seq_region_id transcript_id gene_id stable_id len biotype canonical_transcript_id
    touch_done "$DONE_TAG"
  fi
}

function fix_missing_canonical_tr () {
  local CMD="$1"
  local DBNAME="$2"
  local FIXFILE="$3"

  local DONE_TAG='_fix_missing_canonical_tr'
  if ! check_done "$DONE_TAG"; then
    echo "finding missing canonical transcripts in $DBNAME" > /dev/stderr
      # seq_region_id transcript_id gene_id stable_id len biotype canonical_transcript_id
      cat $FIXFILE | awk -F "\t" \
         '{printf("UPDATE gene SET canonical_transcript_id = %s WHERE gene_id = %s;\n", $2, $3)}' |
         $CMD -D $DBNAME
    touch_done "$DONE_TAG"
  fi
}


function run_xref () {
  local CMD="$1"
  local DBNAME="$2"
  local SPECIES="$3"
  local EG_DIR="$4"
  local OUT_DIR="$5"
  local PARAMS="$6"

  if ! check_done _run_xref; then
    echo "storing old xref primary_ids for $DBNAME " > /dev/stderr
    mkdir -p $OUT_DIR/prev_xrefs
    perl ${EG_DIR}/ensembl-production-metazoa/scripts/get_gene_tr_pri_xref.pl \
      $($CMD details script) \
      -dbname "$DBNAME" > $OUT_DIR/prev_xrefs/"${DBNAME}.ids_xref.txt" \
      2> $OUT_DIR/prev_xrefs/prev_xrefs.stderr

    echo "running xref pipelines on $DBNAME " > /dev/stderr
    mkdir -p $OUT_DIR/prereqs
    local REG_FILE=$OUT_DIR/prereqs/reg.conf
    gen_one_db_reg_conf $CMD $DBNAME $SPECIES $REG_FILE

    local SPECIES_TAG=$(echo $SPECIES | perl -pe 's/^([^_]{3})[^_]+(?:_([^_]{3}))?.*(_[^_]+)$/$1_$2$3/')

    init_pipeline.pl Bio::EnsEMBL::EGPipeline::PipeConfig::AllXref_conf \
      $($CMD details script) \
      -pipeline_tag "_${SPECIES_TAG}" \
      -registry $REG_FILE \
      -production_db "$($PROD_SERVER details url)""$PROD_DBNAME" \
      -hive_force_init 1 \
      -pipeline_dir $OUT_DIR \
      -species $SPECIES \
      $PARAMS \
      2> $OUT_DIR/init.stderr \
      1> $OUT_DIR/init.stdout
    tail $OUT_DIR/init.stderr $OUT_DIR/init.stdout

    local SYNC_CMD=$(cat $OUT_DIR/init.stdout | grep -- -sync'$' | perl -pe 's/^\s*//; s/"//g')
    local LOOP_CMD=$(cat $OUT_DIR/init.stdout | grep -- -loop | perl -pe 's/^\s*//; s/\s*#.*$//; s/"//g')

    echo "$SYNC_CMD" > $OUT_DIR/_continue_pipeline
    echo "$LOOP_CMD" >> $OUT_DIR/_continue_pipeline
    echo "touch $DONE_TAGS_DIR/_run_xref" >> $OUT_DIR/_continue_pipeline

    echo Running pipeline...  > /dev/stderr
    echo See $OUT_DIR/_continue_pipeline if failed...  > /dev/stderr
    cat $OUT_DIR/_continue_pipeline > /dev/stderr

    $SYNC_CMD \
      2> $OUT_DIR/sync.stderr \
      1> $OUT_DIR/sync.stdout
    tail $OUT_DIR/sync.stderr $OUT_DIR/sync.stdout

    $LOOP_CMD \
      2> $OUT_DIR/loop.stderr \
      1> $OUT_DIR/loop.stdout
    tail $OUT_DIR/loop.stderr $OUT_DIR/loop.stdout

    touch_done _run_xref
  fi
}


function run_xref_vb () {
  local CMD="$1"
  local DBNAME="$2"
  local SPECIES="$3"
  local EG_DIR="$4"
  local OUT_DIR="$5"

  if ! check_done _run_xref_vb; then
    echo "running xref VB pipelines on $DBNAME " > /dev/stderr

    mkdir -p $OUT_DIR/prereqs
    local REG_FILE=$OUT_DIR/prereqs/reg.conf
    gen_one_db_reg_conf $CMD $DBNAME $SPECIES $REG_FILE

    local SPECIES_TAG=$(echo $SPECIES | perl -pe 's/^([^_]{3})[^_]+(?:_([^_]{3}))?.*(_[^_]+)$/$1_$2$3/')

    init_pipeline.pl Bio::EnsEMBL::EGPipeline::PipeConfig::Xref_VB_conf \
      $($CMD details script) \
      -pipeline_tag "_${SPECIES_TAG}" \
      -hive_force_init 1 \
      -registry $REG_FILE \
      -production_db "$($PROD_SERVER details url)""$PROD_DBNAME" \
      -species $SPECIES \
      -pipeline_dir $OUT_DIR \
      2> $OUT_DIR/init.stderr \
      1> $OUT_DIR/init.stdout
    tail $OUT_DIR/init.stderr $OUT_DIR/init.stdout

    local SYNC_CMD=$(cat $OUT_DIR/init.stdout | grep -- -sync'$' | perl -pe 's/^\s*//')
    local LOOP_CMD=$(cat $OUT_DIR/init.stdout | grep -- -loop | perl -pe 's/^\s*//; s/\s*#.*$//')

    echo "$SYNC_CMD" > $OUT_DIR/_continue_pipeline
    echo "$LOOP_CMD" >> $OUT_DIR/_continue_pipeline
    echo "touch $DONE_TAGS_DIR/_run_xref_vb" >> $OUT_DIR/_continue_pipeline

    echo Running pipeline...  > /dev/stderr
    echo See $OUT_DIR/_continue_pipeline if failed...  > /dev/stderr
    cat $OUT_DIR/_continue_pipeline > /dev/stderr

    $SYNC_CMD \
      2> $OUT_DIR/sync.stderr \
      1> $OUT_DIR/sync.stdout
    tail $OUT_DIR/sync.stderr $OUT_DIR/sync.stdout

    $LOOP_CMD \
      2> $OUT_DIR/loop.stderr \
      1> $OUT_DIR/loop.stdout
    tail $OUT_DIR/loop.stderr $OUT_DIR/loop.stdout

    touch_done _run_xref_vb
  fi
}

function load_xrefs () {
  local CMD="$1"
  local DBNAME="$2"
  local GENE_MAP="$3"
  local PEP_MAP="$4"

  local DONE_TAG='_load_xref'
  if ! check_done "$DONE_TAG"; then
    echo "loading xref for genes into $DBNAME" > /dev/stderr
    # for the list of xref names see:
    #   d3 -D dinothrombium_tinctorium_core_1904_95_1 -e 'select * from external_db'
    if [ -s "$GENE_MAP" ]; then
      less "$GENE_MAP" |
        cut -f 1,2 |
        perl $SCRIPTS/load_xref.pl $($CMD details script) -dbname $DBNAME -object 'Gene' -xref_name 'RefSeq_gene_name'
    fi

    echo "loading xref for proteins into $DBNAME" > /dev/stderr
    if [ -s "$PEP_MAP" ]; then
      less "$PEP_MAP" |
        cut -f 1,2 |
        perl $SCRIPTS/load_xref.pl $($CMD details script) -dbname $DBNAME -object 'Translation' -xref_name 'RefSeq_peptide'
    fi

    touch_done "$DONE_TAG"
  fi
}


function load_descriptions () {
  local CMD="$1"
  local DBNAME="$2"
  local PEP_MAP="$3"

  local DONE_TAG='_load_descr'
  if ! check_done "$DONE_TAG"; then
    echo "loading gene descriptions into $DBNAME" > /dev/stderr
    ( $CMD -D $DBNAME -e '
      select
        g.stable_id as gene_stable_id,
        tn.stable_id as translation_stable_id
      from
        translation as tn,
        transcript as tt, gene as g
      where
        tn.transcript_id = tt.transcript_id
        and tt.gene_id = g.gene_id;
    ' | sort | uniq;
      echo GO;
      cut -f 1,5  $PEP_MAP
    ) | awk -F "\t" 'BEGIN {go = 0} (/^GO$/) {go = 1} (!go) {gene[$2] = $1} (go && $2 != "") {
                      printf("update gene set description = \"%s\" where (description is null or description = \"\") and stable_id = \"%s\";\n", $2, gene[$1]);
                     }'  |
       $CMD -D $DBNAME

    touch_done "$DONE_TAG"
  fi
}

function load_descriptions_from_gene_map () {
  local CMD="$1"
  local DBNAME="$2"
  local GENE_MAP="$3"

  local DONE_TAG='_load_descr'
  if ! check_done "$DONE_TAG"; then
    echo "loading gene descriptions into $DBNAME" > /dev/stderr
    cut -f 1,4 $GENE_MAP |
      awk -F "\t"  '($2 != "" && $1 != "") {
                      printf("update gene set description = \"%s\" where (description is null or description = \"\") and stable_id = \"%s\";\n", $2, $1);
                     }'  |
      $CMD -D $DBNAME

    touch_done "$DONE_TAG"
  fi
}

function nonref_set_toplevel () {
  local CMD="$1"
  local DBNAME="$2"
  echo "setting toplevel for non_ref_scaffolds of $DBNAME" > /dev/stderr
  # 6 toplevel, 16 non_ref
  $CMD -D $DBNAME -e 'insert ignore
                        into seq_region_attrib (seq_region_id, attrib_type_id, value)
                        select seq_region_id, 6, 1
                        from seq_region sr, coord_system cs
                        where sr.coord_system_id = cs.coord_system_id
                        and cs.name = "non_ref_scaffold";'
  $CMD -D $DBNAME -e 'delete seq_region_attrib from seq_region_attrib
                      left join seq_region using (seq_region_id)
                      left join coord_system using (coord_system_id)
                      where coord_system.name = "non_ref_scaffold"
                      and seq_region_attrib.attrib_type_id = 16
                      and seq_region_attrib.value = 1;'
}

function nonref_unset_toplevel () {
  local CMD="$1"
  local DBNAME="$2"
  echo "unsetting toplevel for non_ref_scaffolds of $DBNAME" > /dev/stderr
  # 6 toplevel, 16 non_ref
  $CMD -D $DBNAME -e 'insert ignore
                        into seq_region_attrib (seq_region_id, attrib_type_id, value)
                        select seq_region_id, 16, 1
                        from seq_region sr, coord_system cs
                        where sr.coord_system_id = cs.coord_system_id
                        and cs.name = "non_ref_scaffold";'
  $CMD -D $DBNAME -e 'delete seq_region_attrib from seq_region_attrib
                      left join seq_region using (seq_region_id)
                      left join coord_system using (coord_system_id)
                      where coord_system.name = "non_ref_scaffold"
                      and seq_region_attrib.attrib_type_id = 6
                      and seq_region_attrib.value = 1;'
}

function clean_neg_start_repeats () {
  local CMD="$1"
  local DBNAME="$2"
  echo "removing repeats with negative starts for $DBNAME" > /dev/stderr
  $CMD -D $DBNAME -e 'delete from repeat_feature where repeat_start < 1'
}

function construct_repeat_libraries () {
  local CMD="$1"
  local DBNAME="$2"
  local SPECIES="$3"
  local OUT_DIR="$4"
  local REPEAT_MODELLER_OPTIONS="$5"

  local DONE_TAG='_construct_repeat_libraries'
  if ! check_done "$DONE_TAG"; then
    echo "loading gene descriptions into $DBNAME" > /dev/stderr

    mkdir -p $OUT_DIR

    pushd $OUT_DIR

    nonref_set_toplevel $CMD $DBNAME

    # RepeatModeller
    local REG_FILE=$OUT_DIR/prereqs/reg.conf
    gen_one_db_reg_conf $CMD $DBNAME $SPECIES $REG_FILE

    local SPECIES_TAG=$(echo $SPECIES | perl -pe 's/^([^_]{3})[^_]+(?:_([^_]{3}))?.*(_[^_]+)$/$1_$2$3/')

    init_pipeline.pl Bio::EnsEMBL::EGPipeline::PipeConfig::RepeatModeler_conf \
      $($CMD details script) \
      -pipeline_tag "_${SPECIES_TAG}" \
      -hive_force_init 1 \
      -registry $REG_FILE \
      -results_dir $OUT_DIR \
      -species $SPECIES \
      ${REPEAT_MODELLER_OPTIONS} \
      -do_clustering 1 \
      2> $OUT_DIR/init.stderr \
      1> $OUT_DIR/init.stdout
    tail $OUT_DIR/init.stderr $OUT_DIR/init.stdout

    local SYNC_CMD=$(cat $OUT_DIR/init.stdout | grep -- -sync'$' | perl -pe 's/^\s*//; s/"//g')
    local LOOP_CMD=$(cat $OUT_DIR/init.stdout | grep -- -loop | perl -pe 's/^\s*//; s/\s*#.*$//; s/"//g')

    echo "$SYNC_CMD" > $OUT_DIR/_continue_pipeline
    echo "$LOOP_CMD" >> $OUT_DIR/_continue_pipeline
    echo "nonref_unset_toplevel $CMD $DBNAME" >> $OUT_DIR/_continue_pipeline
    echo "popd" >> $OUT_DIR/_continue_pipeline
    echo "touch $DONE_TAGS_DIR/${DONE_TAG}" >> $OUT_DIR/_continue_pipeline

    echo Running pipeline...  > /dev/stderr
    echo See $OUT_DIR/_continue_pipeline if failed...  > /dev/stderr
    cat $OUT_DIR/_continue_pipeline > /dev/stderr

    $SYNC_CMD \
      2> $OUT_DIR/sync.stderr \
      1> $OUT_DIR/sync.stdout
    tail $OUT_DIR/sync.stderr $OUT_DIR/sync.stdout

    $LOOP_CMD \
      2> $OUT_DIR/loop.stderr \
      1> $OUT_DIR/loop.stdout
    tail $OUT_DIR/loop.stderr $OUT_DIR/loop.stdout

    nonref_unset_toplevel $CMD $DBNAME

    popd
    touch_done "$DONE_TAG"
  fi

}

function fasta2sl () {
  awk -F "\t" '/^>/ {printf "\n%s\t", $1} !/>/ {printf "%s", $1} END {print ""}' |
    tail -n +2
}

function filter_repeat_library () {
  local LIB_IN="$1"
  local REPBASE_FILE="$2"
  local PEP_FILE="$3"
  local RNA_FILE="$4"
  local OUT_NAME="$5"
  local OUT_DIR="$6"
  local CONVERT_PEP_TO_RNA_EXCLUDE_PAT="$7"

  local DONE_TAG='_filter_repeat_library'
  if ! check_done "$DONE_TAG"; then
    echo "cleaning repeat library $LIB_IN using peptides $PEP_FILE and transcripts $RNA_FILE" > /dev/stderr

    # convert simple
    # perl -pe 's/-P(\w)$/-R$1/'
    # or get old pep id based on a new one ie
    if [ -z "$CONVERT_PEP_TO_RNA_EXCLUDE_PAT" ]; then
      CONVERT_PEP_TO_RNA_EXCLUDE_PAT=cat
    fi

    mkdir -p $OUT_DIR/filtering
    local WD=$OUT_DIR/filtering

    # blast proteins against giriRepbase
    makeblastdb -in $REPBASE_FILE -dbtype nucl -input_type fasta -out $WD/repbase.db
    less $PEP_FILE |
      tblastn -query - \
      -db $WD/repbase.db \
      -evalue 1e-5 \
      -culling_limit 2 \
      -max_target_seqs 10 \
      -outfmt '6 qseqid staxids bitscore std sscinames sskingdoms stitle' \
      -num_threads 4 \
      -out $WD/pep_vs_repbase.blast_res \
      > $WD/pep_vs_repbase.stdout \
      2> $WD/pep_vs_repbase.stderr
    # get peptides that have hits
    cut -f 1 $WD/pep_vs_repbase.blast_res |
      sort | uniq |
      $CONVERT_PEP_TO_RNA_EXCLUDE_PAT > $WD/rna.exclude.pat


    # filter out these hits from transcriptome
    less $RNA_FILE |
      fasta2sl |
      grep -vwFf $WD/rna.exclude.pat |
      perl -pe 's/\t/\n/g' > $WD/rna_clean.fa

    # blast new repeats against transcriptome
    makeblastdb -in $WD/rna_clean.fa -dbtype nucl -out $WD/rna_clean.db
    less $LIB_IN |
      blastn -task megablast \
        -query - \
        -db $WD/rna_clean.db \
        -outfmt '6 qseqid staxids bitscore std sscinames sskingdoms stitle' \
        -max_target_seqs 25 \
        -culling_limit 2 \
        -num_threads 4 \
        -evalue 1e-10 \
        -out $WD/lib_vs_cleantr.blast_res \
        > $WD/lib_vs_cleantr.stdout \
        2> $WD/lib_vs_cleantr.stderr
    # get repeats, hitting filtered transcriptome
    cut -f 1 $WD/lib_vs_cleantr.blast_res |
      sort | uniq > $WD/lib.exclude.pat

    # finally clean library
    less $LIB_IN |
      fasta2sl |
      grep -vwFf $WD/lib.exclude.pat |
      perl -pe 's/\t/\n/g' > $OUT_DIR/$OUT_NAME

    echo filtering done > /dev/stderr
    grep -c '>' $LIB_IN $OUT_DIR/$OUT_NAME > /dev/stderr

    touch_done "$DONE_TAG"
  fi
}

function run_repeat_masking () {
  local CMD="$1"
  local DNMAME="$2"
  local SPECIES="$3"
  local REP_LIB="$4"
  local OUT_DIR="$5"
  local REPBASE_SPECIES_NAME="$6"

  local DONE_TAG='_run_repeat_masking'
  if ! check_done "$DONE_TAG"; then
    echo "running repeat masking on $DBNAME" > /dev/stderr
    echo "using repeatmasker_repbase_species '$REPBASE_SPECIES_NAME'" > /dev/stderr

    mkdir -p $OUT_DIR
    mkdir -p $OUT_DIR/reports

    pushd $OUT_DIR

    nonref_set_toplevel $CMD $DBNAME

    # RepeatModeller
    local REG_FILE=$OUT_DIR/prereqs/reg.conf
    gen_one_db_reg_conf $CMD $DBNAME $SPECIES $REG_FILE

    local REP_LIB_OPT="-repeatmasker_library ${SPECIES}=${REP_LIB}"
    if [ "$REP_LIB" = "NO" ]; then
      REP_LIB_OPT=
    fi

    local SPECIES_TAG=$(echo $SPECIES | perl -pe 's/^([^_]{3})[^_]+(?:_([^_]{3}))?.*(_[^_]+)$/$1_$2$3/')

    init_pipeline.pl Bio::EnsEMBL::EGPipeline::PipeConfig::DNAFeatures_conf \
      $($CMD details script) \
      -registry $REG_FILE \
      -production_db "$($PROD_SERVER details url)""$PROD_DBNAME" \
      -hive_force_init 1\
      -pipeline_tag "_${SPECIES_TAG}" \
      -pipeline_dir $OUT_DIR \
      -report_dir $OUT_DIR/reports \
      -species $SPECIES \
      -redatrepeatmasker 0 \
      -always_use_repbase 1 \
      -repeatmasker_timer '10H' \
      $REP_LIB_OPT \
      -repeatmasker_repbase_species "$REPBASE_SPECIES_NAME" \
      -max_seq_length 300000 \
      2> $OUT_DIR/init.stderr \
      1> $OUT_DIR/init.stdout
    tail $OUT_DIR/init.stderr $OUT_DIR/init.stdout

    local SYNC_CMD=$(cat $OUT_DIR/init.stdout | grep -- -sync'$' | perl -pe 's/^\s*//; s/"//g')
    local LOOP_CMD=$(cat $OUT_DIR/init.stdout | grep -- -loop | perl -pe 's/^\s*//; s/\s*#.*$//; s/"//g')

    echo "$SYNC_CMD" > $OUT_DIR/_continue_pipeline
    echo "$LOOP_CMD" >> $OUT_DIR/_continue_pipeline
    echo "clean_neg_start_repeats $CMD $DBNAME" >> $OUT_DIR/_continue_pipeline
    echo "nonref_unset_toplevel $CMD $DBNAME" >> $OUT_DIR/_continue_pipeline
    echo "popd" >> $OUT_DIR/_continue_pipeline
    echo "touch $DONE_TAGS_DIR/${DONE_TAG}" >> $OUT_DIR/_continue_pipeline

    echo Running pipeline...  > /dev/stderr
    echo See $OUT_DIR/_continue_pipeline if failed...  > /dev/stderr
    cat $OUT_DIR/_continue_pipeline > /dev/stderr

    $SYNC_CMD \
      2> $OUT_DIR/sync.stderr \
      1> $OUT_DIR/sync.stdout
    tail $OUT_DIR/sync.stderr $OUT_DIR/sync.stdout

    $LOOP_CMD \
      2> $OUT_DIR/loop.stderr \
      1> $OUT_DIR/loop.stdout
    tail $OUT_DIR/loop.stderr $OUT_DIR/loop.stdout

    echo 'update meta set species_id = 1 where meta_key = "repeat.analysis" and species_id is null' | $CMD -D "$DBNAME"

    clean_neg_start_repeats $CMD $DBNAME

    nonref_unset_toplevel $CMD $DBNAME

    popd
    touch_done "$DONE_TAG"
  fi
}

function run_core_stats () {
  local CMD="$1"
  local DBNAME="$2"
  local SPECIES="$3"
  local OUT_DIR="$4"

  local DONE_TAG='_run_core_stats'
  if ! check_done "$DONE_TAG"; then
    echo "running core stats pipeline on $DBNAME" > /dev/stderr

    mkdir -p $OUT_DIR

    # RepeatModeller
    local REG_FILE=$OUT_DIR/prereqs/reg.conf
    gen_one_db_reg_conf $CMD $DBNAME $SPECIES $REG_FILE

    local SPECIES_TAG=$(echo $SPECIES | perl -pe 's/^([^_]{3})[^_]+(?:_([^_]{3}))?.*(_[^_]+)$/$1_$2$3/')

    init_pipeline.pl Bio::EnsEMBL::EGPipeline::PipeConfig::CoreStatistics_conf \
      $($CMD details script) \
      -registry $REG_FILE \
      -hive_force_init 1\
      -pipeline_tag "_${SPECIES_TAG}" \
      -pipeline_dir $OUT_DIR \
      -species $SPECIES \
      2> $OUT_DIR/init.stderr \
      1> $OUT_DIR/init.stdout

    tail $OUT_DIR/init.stderr $OUT_DIR/init.stdout

    local SYNC_CMD=$(cat $OUT_DIR/init.stdout | grep -- -sync'$' | perl -pe 's/^\s*//; s/"//g')
    local LOOP_CMD=$(cat $OUT_DIR/init.stdout | grep -- -loop | perl -pe 's/^\s*//; s/\s*#.*$//; s/"//g')

    echo "$SYNC_CMD" > $OUT_DIR/_continue_pipeline
    echo "$LOOP_CMD" >> $OUT_DIR/_continue_pipeline
    echo "touch $DONE_TAGS_DIR/${DONE_TAG}" >> $OUT_DIR/_continue_pipeline

    echo Running pipeline...  > /dev/stderr
    echo See $OUT_DIR/_continue_pipeline if failed...  > /dev/stderr
    cat $OUT_DIR/_continue_pipeline > /dev/stderr

    $SYNC_CMD \
      2> $OUT_DIR/sync.stderr \
      1> $OUT_DIR/sync.stdout
    tail $OUT_DIR/sync.stderr $OUT_DIR/sync.stdout

    $LOOP_CMD \
      2> $OUT_DIR/loop.stderr \
      1> $OUT_DIR/loop.stdout
    tail $OUT_DIR/loop.stderr $OUT_DIR/loop.stdout

    touch_done "$DONE_TAG"
  fi
}

function set_core_random_samples () {
  local CMD="$1"
  local DBNAME="$2"
  local SAMPLE_GENE="$3"
  local SCRIPTS="$4"

  local SET_CORE_SAMPLE_PL=${SCRIPTS}/ensembl-production-metazoa/scripts/legacy/set_core_samples.pl

  local DONE_TAG='_set_core_random_samples'
  if ! check_done "$DONE_TAG"; then
    echo "running rundom core sample for $DBNAME" > /dev/stderr

    if [ -n "$SAMPLE_GENE" ]; then
      SAMPLE_GENE=$($CMD -D "$DBNAME" -N -e "select stable_id from gene where stable_id = '${SAMPLE_GENE}' limit 1;")
    fi

    if [ -z "$SAMPLE_GENE" ]; then
      local RAND_GENE=$($CMD -D "$DBNAME" -N -e 'select stable_id from gene order by rand() limit 1;')
      echo "using $RAND_GENE as sample" > /dev/stderr
      SAMPLE_GENE="$RAND_GENE"
    fi

    perl ${SET_CORE_SAMPLE_PL} \
      -gene_id "$SAMPLE_GENE" \
      $($CMD details script) \
      -dbname "$DBNAME"

    touch_done "$DONE_TAG"
  fi

}


function project_toplevel_by_atac () {
  local FROM_CMD="$1"
  local FROM_DBNAME="$2"
  local CMD="$3"
  local DBNAME="$4"
  local OUT_DIR="$5"
  local ENS_DIR="$6"
  local TAG="$7"

  local DONE_TAG='_project_toplevel_by_atac'${TAG}
  if ! check_done "$DONE_TAG"; then
    echo "projecting toplevel cs by atac from ${FROM_CMD}:${FROM_DBNAME} to ${CMD}:${DBNAME}" > /dev/stderr

    mkdir -p "$OUT_DIR"

    local MAP_SCRIPT=$ENS_DIR/eg-assemblyconverter/map_explicit.py
    local MAP_CMD="python $MAP_SCRIPT \
      $($FROM_CMD details prefix_from_) --from_db $FROM_DBNAME \
      $($CMD details script) --to_db $DBNAME \
      --output_dir $OUT_DIR"

    local BSUB_OPTS="-q production-rh74 -R 'rusage[mem=16000]' -M 16000"

    bsub $BSUB_OPTS \
      -o $OUT_DIR/bsub.out -e $OUT_DIR/bsub.err \
      -Is "source $ENS_DIR/setup.sh; eval \"\$(pyenv init -)\"; pyenv shell atac_assembly_mapping; $MAP_CMD; exit"
   tail $OUT_DIR/bsub.out $OUT_DIR/bsub.err

    touch_done "$DONE_TAG"
  fi
}

function make_tmpdb_4_projections () {
  local FROM_CMD="$1"
  local FROM_DBNAME="$2"
  local CMD="$3"
  local DBNAME="$4"
  local TAG="$5"

  local DONE_TAG='_make_tmpdb_4_projections'"$TAG"
  if ! check_done "$DONE_TAG"; then
    echo "copying ${FROM_CMD}:${FROM_DBNAME} to ${CMD}:${DBNAME}" > /dev/stderr
    $CMD -e "drop database if exists $DBNAME;"
    $CMD -e "create database $DBNAME;"
    $FROM_CMD mysqldump --single-transaction --max_allowed_packet=2024M  $FROM_DBNAME |
      $CMD -D $DBNAME

    touch_done "$DONE_TAG"
  fi
}

function patch_species_name_tmpdb_4_projections () {
  local CMD="$1"
  local DBNAME="$2"
  local SPECIES="$3"
  local TAG="$4"

  local DONE_TAG='_patch_trgdb_4_compara_projections'"$TAG"
  if ! check_done "$DONE_TAG"; then
    echo "updating species.production_name for  ${CMD}:${DBNAME} to ${SPECIES}" > /dev/stderr
    $CMD -D $DBNAME -e "update meta set meta_value = '${SPECIES}' where meta_key = 'species.production_name'"
    $CMD -D $DBNAME -e "update meta set meta_value = '${SPECIES}' where meta_key = 'species.display_name'"
    touch_done "$DONE_TAG"
  fi
}

function filter_src_tmpdb_4_projections () {
  local CMD="$1"
  local DBNAME="$2"
  local TAG="$3"

  local DONE_TAG='_filter_srcdb_4_compara_projections'"$TAG"
  if ! check_done "$DONE_TAG"; then
    echo "removing regions with no genes from ${CMD}:${DBNAME}" > /dev/stderr
    $CMD -D $DBNAME -e 'insert into seq_region_attrib (seq_region_id, attrib_type_id, value) select distinct sr.seq_region_id, "6", "2" from seq_region sr, gene g where sr.seq_region_id = g.seq_region_id;'
    $CMD -D $DBNAME -e 'delete from seq_region_attrib where attrib_type_id = 6 and value = 1;'
    $CMD -D $DBNAME -e 'update seq_region_attrib set value = 1 where attrib_type_id = 6 and value = 2;'
    touch_done "$DONE_TAG"
  fi
}


function clean_tmpdb_4_projections () {
  local CMD="$1"
  local DBNAME="$2"
  local TAG="$3"

  local DONE_TAG='_clean_tmpdb_4_projections'"$TAG"
  if ! check_done "$DONE_TAG"; then
    echo "dropping tmp (?!) ${CMD}:${DBNAME}" > /dev/stderr
    $CMD -e "drop database $DBNAME;" # no if exists

    touch_done "$DONE_TAG"
  fi
}

function project_genes () {
  local FROM_CMD="$1"
  local FROM_DBNAME="$2"
  local CMD="$3"
  local DBNAME="$4"
  local OUT_DIR="$5"
  local SCRIPTS="$6"

  local DONE_TAG='_project_genes'
  if ! check_done "$DONE_TAG"; then
    mkdir -p $OUT_DIR

    echo "getting assembly.name for ${CMD}:${DBNAME}" > /dev/stderr
    local NEW_ASM_NAME=$($CMD -D $DBNAME -e 'select meta_value from meta where meta_key = "assembly.name";' -N)

    echo "getting toplevel coord_systems for ${CMD}:${DBNAME}" > /dev/stderr
    local TOPLEVEL_CS_SQL='select distinct cs.name
      from seq_region sr, seq_region_attrib sra, coord_system cs
      where sr.seq_region_id = sra.seq_region_id
      and cs.coord_system_id = sr.coord_system_id
      and sra.attrib_type_id = 6 and sra.value = 1
      order by cs.rank;'
    local TOPLEVEL_CS=$($CMD -D $DBNAME -e "$TOPLEVEL_CS_SQL" -N)

    local rank=01
    local cs
    for cs in $TOPLEVEL_CS; do
      echo "projecting from ${FROM_CMD}:${FROM_DBNAME} to ${CMD}:${DBNAME} $cs $NEW_ASM_NAME" > /dev/stderr
      echo "see tail -f $OUT_DIR/log_${rank}_${cs}.out $OUT_DIR/log_${rank}_${cs}.err" > /dev/stderr
      perl $SCRIPTS/core/project_genes.pl \
        $($CMD details script) \
        -old_dbname $FROM_DBNAME -new_dbname $DBNAME \
        -to_cs $cs -to_assembly $NEW_ASM_NAME \
        -results_dir $OUT_DIR/${rank}_${cs}_mapping \
        > $OUT_DIR/log_${rank}_${cs}.out \
        2> $OUT_DIR/log_${rank}_${cs}.err
      tail $OUT_DIR/log_${rank}_${cs}.out $OUT_DIR/log_${rank}_${cs}.err
      rank=0$(($rank + 1))
    done

    touch_done "$DONE_TAG"
  fi
}

function analyze_projections () {
  local CMD="$1"
  local DBNAME="$2"
  local FROM_DIR="$3"
  local TO_CMD="$4"
  local TO_DBNAME="$5"
  local OUT_DIR="$6"
  local TAG="$7"

  local DONE_TAG='_analyze_projections'"${TAG}"
  if ! check_done "$DONE_TAG"; then
    mkdir -p $OUT_DIR

    $CMD -D $DBNAME -e 'select stable_id from gene' -N > $OUT_DIR/known_genes
    echo "$DBNAME has  $(cat $OUT_DIR/known_genes | wc -l) genes" > /dev/stderr

    echo -n > $OUT_DIR/projected.gff3
    echo -n > $OUT_DIR/unprojected.gff3

    cat $OUT_DIR/known_genes > $OUT_DIR/look_for.pat

    pushd $FROM_DIR
      local res_dir=''
      # gather projections from all cs
      for res_dir in $(ls --color=none -1 -d 0*_mapping | sort -n); do
        cat $res_dir/projected.gff3 | grep -Ff $OUT_DIR/look_for.pat >> $OUT_DIR/projected.gff3
        cat $OUT_DIR/projected.gff3 |
          awk -F "\t" '(!/^#/ && $3 == "gene" ) {print $9}' |
          cut -f 2 -d '=' | cut -f 1 -d '-' > $OUT_DIR/ignore.pat
        cat $OUT_DIR/look_for.pat | grep -vwFf  $OUT_DIR/ignore.pat > $OUT_DIR/look_for.pat.tmp
        mv $OUT_DIR/look_for.pat.tmp $OUT_DIR/look_for.pat
      done
      echo "  projected  $(grep -Pc '\tgene\t' $OUT_DIR/projected.gff3) genes" > /dev/stderr

      # gather unprojected from all cs (the initial list is in  look_for.pat)
      for res_dir in $(ls --color=none -1 -d 0*_mapping | sort -n); do
        cat $res_dir/unprojected.gff3 | grep -Ff $OUT_DIR/look_for.pat >> $OUT_DIR/unprojected.gff3
        cat $OUT_DIR/unprojected.gff3 |
          awk -F "\t" '(!/^#/ && $3 == "gene" ) {print $9}' |
          cut -f 2 -d '=' | cut -f 1 -d '-' > $OUT_DIR/ignore.pat
        cat $OUT_DIR/look_for.pat | grep -vwFf  $OUT_DIR/ignore.pat > $OUT_DIR/look_for.pat.tmp
        mv $OUT_DIR/look_for.pat.tmp $OUT_DIR/look_for.pat
      done
      echo "  unprojected  $(grep -Pc '\tgene\t' $OUT_DIR/unprojected.gff3) genes" > /dev/stderr

      cat $OUT_DIR/look_for.pat > $OUT_DIR/missing_genes
      echo "  missing $( cat $OUT_DIR/missing_genes | wc -l ) genes" > /dev/stderr
    popd

    # compare whole gene sequences for new coord and the old one. ok if the same
    # find hanging Ns in source models and total number of Ns
    # try to extend new models on both ends (add hanging Ns) and see if sequences are equal
    # if fixed just use shifted coordinates of the previous version
    # ? try just shift old coordinates to the current begining
    cat $OUT_DIR/unprojected.gff3 |
      awk -F "\t" '($3 == "gene" && !/^#/)' |
      perl $SCRIPTS/gene_projections_cmp.pl \
        $($CMD details prefix_from_)  -from_dbname $DBNAME \
        $($TO_CMD details prefix_to_) -to_dbname $TO_DBNAME \
        > $OUT_DIR/fixed_genes.txt  2> $OUT_DIR/genes_projections_cmp.stderr
    tail $OUT_DIR/fixed_genes.txt $OUT_DIR/genes_projections_cmp.stderr | cut -f 1
    # old gff ???
    # get old gff and compare raw dna fastas, OK if fastas are the same

    # finalize projected_all
#cat projected_all.gff3 | sort | uniq | sort -k1,1 -k4,4n -k5,5nr  > projected_all.gff3.tmp
#mv projected_all.gff3.tmp projected_all.gff3

    touch_done "$DONE_TAG"
  fi
}

function get_db_eg_version () {
    local CMD="$1"
    local DBNAME="$2"
    local get_eg_version_sql='select meta_value from meta where meta_key = "schema_version";'
    $CMD -D $DBNAME -e "$get_eg_version_sql" -N
}

function get_db_prod_name () {
    local CMD="$1"
    local DBNAME="$2"
    local get_name_sql='select meta_value from meta where meta_key = "species.production_name";'
    $CMD -D $DBNAME -e "$get_name_sql" -N
}

function get_db_asm () {
    local CMD="$1"
    local DBNAME="$2"
    local get_asm_sql='select meta_value from meta where meta_key = "assembly.name";'
    $CMD -D $DBNAME -e "$get_asm_sql" -N
}

function make_compara_lastz () {
  local CMD="$1"
  local COMPARA_DBNAME="$2"
  local FROM_DBNAME="$3"
  local TO_DBNAME="$4"
  local OUT_DIR="$5"
  local ENS_DIR="$6"
  local TAG="$7"

  local DONE_TAG='_compara_lastz'"${TAG}"
  if ! check_done "$DONE_TAG"; then
    mkdir -p $OUT_DIR

    echo "running compara based lastz alignmebts on $COMPARA_DBNAME" > /dev/stderr

    local source_species=$(get_db_prod_name $CMD $FROM_DBNAME)
    local target_species=$(get_db_prod_name $CMD $TO_DBNAME)

    local source_asm=$(get_db_asm $CMD $FROM_DBNAME)
    local target_asm=$(get_db_asm $CMD $TO_DBNAME)

    echo "using source $source_species:$source_asm from $FROM_DBNAME" > /dev/stderr
    echo "using target $target_species:$target_asm from $TO_DBNAME" > /dev/stderr

    mkdir -p $OUT_DIR/prereqs
    local REG_FILE=$OUT_DIR/prereqs/reg.conf
    gen_two_db_compara_reg_conf $CMD \
      $FROM_DBNAME $source_species \
      $TO_DBNAME $target_species \
      $COMPARA_DBNAME \
      $REG_FILE

    local COLLECTION_NAME="collection_${source_asm}_${target_asm}"
    local COLLECTION_FILE=$OUT_DIR/prereqs/collection.txt
    echo -e "${source_species}\n${target_species}" > $COLLECTION_FILE

    local compara_url="$($CMD details url)${COMPARA_DBNAME}"

    pushd $OUT_DIR
      echo "adding $target_species to $compara_url" > /dev/stderr

      perl $ENS_DIR/ensembl-compara/scripts/pipeline/update_genome.pl \
        --reg_conf $REG_FILE \
        --compara "$compara_url" \
        --species "$target_species"

      local source_db_id=$($CMD -D $COMPARA_DBNAME -e "select genome_db_id from genome_db where name = '$source_species' and assembly = '$source_asm'" -N)
      local target_db_id=$($CMD -D $COMPARA_DBNAME -e "select genome_db_id from genome_db where name = '$target_species' and assembly = '$target_asm'" -N)

      echo "adding LASTZ_NET link (target:source) $target_db_id:$source_db_id from $FROM_DBNAME" > /dev/stderr
      perl $ENS_DIR/ensembl-compara/scripts/pipeline/create_mlss.pl \
        --method_link_type LASTZ_NET \
        --genome_db_id "$target_db_id,$source_db_id" \
        --source "ensembl" \
        --reg_conf $ENS_DIR/ensembl-compara/scripts/pipeline/production_reg_conf.pl \
        --compara $compara_url \
        --use_genomedb_ids \
        --species_set_name "$COLLECTION_NAME" \
        --name "lastz_${COLLECTION_NAME}" \
        --url "" \
        --force


      echo "adding new collection '$COLLECTION_NAME' to $compara_url" > /dev/stderr
      perl $ENS_DIR/ensembl-compara/scripts/pipeline/edit_collection.pl \
        --new \
        --compara $compara_url \
        --collection "$COLLECTION_NAME" \
        --nodry-run \
        --file_of_production_name $COLLECTION_FILE

# $ENSCODE/ensembl-compara/modules/Bio/EnsEMBL/Compara/PipeConfig/EBI/Ensembl/Lastz_conf.pm - you shouldn't need to change anything
# $ENSCODE/ensembl-analysis/modules/Bio/EnsEMBL/Analysis/Config/General.pm exists in your enscode (you're likely to have a copy called General.pm.example, just copy this to General.pm)

      echo "creating lastz pipeline" > /dev/stderr
# Bio::EnsEMBL::Compara::PipeConfig::EBI::EG::Lastz_conf
      init_pipeline.pl Bio::EnsEMBL::Compara::PipeConfig::EBI::Ensembl::Lastz_conf \
        $($CMD details script | perl -pe 's/--pass /--password /') \
        -pipeline_name "${COLLECTION_NAME}_lastz" \
        -hive_force_init 1 \
        -reg_conf $REG_FILE \
        -pipeline_dir $OUT_DIR \
        -ref_species $source_species \
        -collection $COLLECTION_NAME \
        -ensembl_cvs_root_dir $ENS_DIR \
        -master_db $compara_url \
        -do_compare_to_previous_db 0 \
        2> $OUT_DIR/init.stderr \
        1> $OUT_DIR/init.stdout
      tail $OUT_DIR/init.stderr $OUT_DIR/init.stdout

      local SYNC_CMD=$(cat $OUT_DIR/init.stdout | grep -- -sync'$' | perl -pe 's/^\s*//')
      local LOOP_CMD=$(cat $OUT_DIR/init.stdout | grep -- -loop | perl -pe 's/^\s*//; s/\s*#.*$//')

      echo "$SYNC_CMD" > $OUT_DIR/_continue_pipeline
      echo "$LOOP_CMD" >> $OUT_DIR/_continue_pipeline
      echo "popd" >> $OUT_DIR/_continue_pipeline
      echo "touch $DONE_TAGS_DIR/${DONE_TAG}" >> $OUT_DIR/_continue_pipeline

      echo Running pipeline...  > /dev/stderr
      echo See $OUT_DIR/_continue_pipeline if failed...  > /dev/stderr
      cat $OUT_DIR/_continue_pipeline > /dev/stderr

      $SYNC_CMD \
        2> $OUT_DIR/sync.stderr \
        1> $OUT_DIR/sync.stdout
      tail $OUT_DIR/sync.stderr $OUT_DIR/sync.stdout

      $LOOP_CMD \
        2> $OUT_DIR/loop.stderr \
        1> $OUT_DIR/loop.stdout
      tail $OUT_DIR/loop.stderr $OUT_DIR/loop.stdout

      local LASTZ_DB_URL=$(cat $OUT_DIR/init.stdout | grep 'export EHIVE_URL' | cut -f 2 -d '=' | perl -pe 's/\s+/\t/' | cut -f 1)
      local LASTZ_DB_NAME=$(echo $LASTZ_DB_URL | perl -pe 's,.*/,,')
      echo $LASTZ_DB_URL > $OUT_DIR/_lastz_db_url
      echo $LASTZ_DB_NAME > $OUT_DIR/_lastz_db_name

    popd
    touch_done "$DONE_TAG"
  fi
}

function make_compara_projections () {
  local CMD="$1"
  local LASTZ_DBNAME="$2"
  local FROM_DBNAME="$3"
  local TO_DBNAME="$4"
  local RES_DBNAME="$5"
  local OUT_DIR="$6"
  local ENS_DIR="$7"
  local TAG="$8"

  local DONE_TAG='_compara_projections'"${TAG}"
  if ! check_done "$DONE_TAG"; then
    mkdir -p $OUT_DIR

    local asm_from=$(get_db_asm $CMD $FROM_DBNAME)
    local asm_to=$(get_db_asm $CMD $TO_DBNAME)
    echo "running $asm_from to $asm_to projections using compara based lastz alignments from $LASTZ_DBNAME" > /dev/stderr

    init_pipeline.pl Bio::EnsEMBL::EGPipeline::PipeConfig::WGA2GenesDirect_conf \
      --hive_force_init 1 \
      --pipeline_tag "_${asm_from}2${asm_to}" \
      $($CMD details script) \
      $($CMD details script_compara_) \
      $($CMD details script_source_) \
      $($CMD details script_target_) \
      $($CMD details script_result_) \
      --compara_dbname $LASTZ_DBNAME \
      --source_dbname $FROM_DBNAME \
      --target_dbname $TO_DBNAME \
      --result_dbname $RES_DBNAME \
      --result_force_rewrite 1 \
      --result_clone_mode 'dna_db' \
      --reg_conf 'none' \
      2> $OUT_DIR/init.stderr \
      1> $OUT_DIR/init.stdout
    tail $OUT_DIR/init.stderr $OUT_DIR/init.stdout

    local SYNC_CMD=$(cat $OUT_DIR/init.stdout | grep -- -sync'$' | perl -pe 's/^\s*//')
    local LOOP_CMD=$(cat $OUT_DIR/init.stdout | grep -- -loop | perl -pe 's/^\s*//; s/\s*#.*$//')

    echo "$SYNC_CMD" > $OUT_DIR/_continue_pipeline
    echo "$LOOP_CMD" >> $OUT_DIR/_continue_pipeline
    echo "touch $DONE_TAGS_DIR/${DONE_TAG}" >> $OUT_DIR/_continue_pipeline

    echo Running pipeline...  > /dev/stderr
    echo See $OUT_DIR/_continue_pipeline if failed...  > /dev/stderr
    cat $OUT_DIR/_continue_pipeline > /dev/stderr

    $SYNC_CMD \
      2> $OUT_DIR/sync.stderr \
      1> $OUT_DIR/sync.stdout
    tail $OUT_DIR/sync.stderr $OUT_DIR/sync.stdout

    $LOOP_CMD \
      2> $OUT_DIR/loop.stderr \
      1> $OUT_DIR/loop.stdout
    tail $OUT_DIR/loop.stderr $OUT_DIR/loop.stdout

    src_transcripts=$($CMD -D $FROM_DBNAME -e 'select count(*) from transcript' -N)
    src_pc_transcripts=$($CMD -D $FROM_DBNAME -e 'select count(*) from transcript where biotype = "protein_coding"' -N)
    trg_transcripts=$($CMD -D $RES_DBNAME -e 'select count(*) from transcript' -N)
    echo "projected $trg_transcripts out of $src_pc_transcripts protein coding ($src_transcripts total) " > /dev/stderr

    touch_done "$DONE_TAG"
  fi
}

function dump_translations () {
  local CMD="$1"
  local DBNAME="$2"
  local OUT_DIR="$3"
  local ENS_DIR="$4"
  local TR_OR_CDS="$5"
  local TAG="$6"

  local DONE_TAG='_dump_translations'"${TAG}"
  if ! check_done "$DONE_TAG"; then
    mkdir -p $OUT_DIR

    local trg_transcripts=$($CMD -D $DBNAME -e 'select count(*) from transcript' -N)

    echo "dumping translations for $trg_transcripts transcripts from $DBNAME" > /dev/stderr
    local asm_to=$(get_db_asm $CMD $DBNAME)

    local TR_PARTS="transcript"
    if [ -n "$TR_OR_CDS" ]; then
      TR_PARTS="$TR_OR_CDS"
    fi

    perl $ENS_DIR/ensembl-production-imported/scripts/misc_scripts/get_trans.pl -type translation \
      $($CMD details script) \
      -dbname $DBNAME > $OUT_DIR/pep.faa

    perl $ENS_DIR/ensembl-production-imported/scripts/misc_scripts/get_trans.pl -type $TR_PARTS -ignore_biotypes transposable_element \
      $($CMD details script) \
      -dbname $DBNAME > $OUT_DIR/tr.fna

    touch_done "$DONE_TAG"
  fi
}


function dump_translations_and_gff3 () {
  local CMD="$1"
  local DBNAME="$2"
  local OUT_DIR="$3"
  local ENS_DIR="$4"
  local TAG="$5"
  local OPTIONS="$6"

  local DONE_TAG='_dump_translations_and_gff3'"${TAG}"
  if ! check_done "$DONE_TAG"; then
    mkdir -p $OUT_DIR

    local trg_transcripts=$($CMD -D $DBNAME -e 'select count(*) from transcript' -N)

    echo "dumping translations for $trg_transcripts transcripts from $DBNAME" > /dev/stderr
    local asm_to=$(get_db_asm $CMD $DBNAME)

    perl $ENS_DIR/ensembl-production-imported/scripts/misc_scripts/get_trans.pl -type translation \
      $($CMD details script) \
      -dbname $DBNAME > $OUT_DIR/${asm_to}_projected.pep.fasta

    perl $ENS_DIR/ensembl-production-imported/scripts/misc_scripts/get_trans.pl -type transcript \
      $($CMD details script) \
      -dbname $DBNAME > $OUT_DIR/${asm_to}_projected.tr.fasta

    echo "dumping gff3 for $DBNAME" > /dev/stderr
    local res_species=$(get_db_prod_name $CMD $DBNAME)
    local res_eg_version=$(get_db_eg_version $CMD $DBNAME)

    mkdir -p $OUT_DIR/prereqs
    local REG_FILE=$OUT_DIR/prereqs/reg.conf
    gen_one_db_reg_conf $CMD $DBNAME $res_species $REG_FILE
    print_ontology_reg_entry 'vb-p' "ensembl_ontology_${res_eg_version}" >> $REG_FILE

    local SPECIES_TAG=$(echo $res_species | perl -pe 's/^([^_]{3})[^_]+(?:_([^_]{3}))?.*(_[^_]+)$/$1_$2$3/')

#   see https://www.ebi.ac.uk/seqdb/confluence/display/GTI/FTP+Core+Dumping+Pipeline#FTPCoreDumpingPipeline-GFF3 for alternative
    init_pipeline.pl Bio::EnsEMBL::EGPipeline::PipeConfig::FileDumpGFF_conf \
      $($CMD details script) \
      -hive_force_init 1 \
      -pipeline_tag "_${SPECIES_TAG}" \
      -registry $REG_FILE \
      -results_dir $OUT_DIR/gff3 \
      -species $res_species \
      -gff3_feature_type Gene \
      -gff3_feature_type Transcript \
      -gff3_remove_id_prefix 1 \
      -gff3_relabel_transcript 1 \
      ${OPTIONS} \
      2> $OUT_DIR/init.stderr \
      1> $OUT_DIR/init.stdout
    tail $OUT_DIR/init.stderr $OUT_DIR/init.stdout

    local SYNC_CMD=$(cat $OUT_DIR/init.stdout | grep -- -sync'$' | perl -pe 's/^\s*//')
    local LOOP_CMD=$(cat $OUT_DIR/init.stdout | grep -- -loop | perl -pe 's/^\s*//; s/\s*#.*$//')

    echo "$SYNC_CMD" > $OUT_DIR/_continue_pipeline
    echo "$LOOP_CMD" >> $OUT_DIR/_continue_pipeline
    echo "touch $DONE_TAGS_DIR/${DONE_TAG}" >> $OUT_DIR/_continue_pipeline

    echo Running pipeline...  > /dev/stderr
    echo See $OUT_DIR/_continue_pipeline if failed...  > /dev/stderr
    cat $OUT_DIR/_continue_pipeline > /dev/stderr

    $SYNC_CMD \
      2> $OUT_DIR/sync.stderr \
      1> $OUT_DIR/sync.stdout
    tail $OUT_DIR/sync.stderr $OUT_DIR/sync.stdout

    $LOOP_CMD \
      2> $OUT_DIR/loop.stderr \
      1> $OUT_DIR/loop.stdout
    tail $OUT_DIR/loop.stderr $OUT_DIR/loop.stdout

    find $OUT_DIR/gff3 -name '*.gff3' |
      xargs -n 1 -I XXX sh -c 'mv XXX XXX.pre; gt gff3 -tidy -sort -retainids XXX.pre > XXX'

    touch_done "$DONE_TAG"
  fi
}

function run_data_init() {
  local META_FILE="$1"
  local OUT_DIR="$2"
  local TAG="$3"

  local DONE_TAG='_data_init'"${TAG}"
  if ! check_done "$DONE_TAG"; then
    mkdir -p $OUT_DIR

    pushd $OUT_DIR
      local init_cmd=$(get_meta_conf $META_FILE DATA_INIT | perl -pe 's/$/;/ if $_ !~ m/^\s*$/')
      echo "running data init commands: '$init_cmd'" > /dev/stderr
      sh -c "$init_cmd"
    popd

    touch_done "$DONE_TAG"
  fi
}

function compara_proj_to_gff3 () {
  local CMD_FROM="$1"
  local DBNAME_FROM="$2"
  local CMD_TO="$3"
  local DBNAME_TO="$4"
  local SRC_GFF="$5"
  local OUT_DIR="$6"
  local ENS_DIR="$7"
  local TAG="$8"
  local CMP_OPTIONS="$9"

  local DONE_TAG='_compara_proj_to_gff3'${TAG}
  if ! check_done "$DONE_TAG"; then
    echo "compraing source ${CMD_FROM}:${DBNAME_FROM} and target ${CMD_TO}:${DBNAME_TO}" > /dev/stderr
    mkdir -p "$OUT_DIR"
    local CMP_SCRIPT=$ENS_DIR/ensembl-production-metazoa/scripts/compara_projection2gff3_pre.pl

    local CMP_CMD="perl $CMP_SCRIPT \
      $($CMD_FROM details script_from_) -from_dbname $DBNAME_FROM \
      $($CMD_TO details script_to_) -to_dbname $DBNAME_TO \
      $CMP_OPTIONS \
      -source_gff - \
      > ${OUT_DIR}/cmp.stdout 2> ${OUT_DIR}/cmp.stderr"

    #cpanm install Text::Levenshtein::Damerau::XS

    local BSUB_OPTS="-q production-rh74 -R 'rusage[mem=16000]' -M 16000"

    bsub $BSUB_OPTS \
      -o $OUT_DIR/bsub.out -e $OUT_DIR/bsub.err \
      -Is "less $SRC_GFF | $CMP_CMD; exit"
    tail $OUT_DIR/bsub.out $OUT_DIR/bsub.err

    local asm_to=$(get_db_asm $CMD_TO $DBNAME_TO)

    echo "splitting results ${OUT_DIR}/cmp.{stdout,stderr} for ${asm_to}" > /dev/stderr
    bash $ENS_DIR/ensembl-production-metazoa/scripts/projections_gff3_pre2gff3.sh \
      "${asm_to}.pre" ${OUT_DIR}/cmp.stdout ${OUT_DIR}/cmp.stderr ${OUT_DIR}/res \
      > ${OUT_DIR}/split.stdout 2> ${OUT_DIR}/split.stderr
    tail ${OUT_DIR}/split.stdout ${OUT_DIR}/split.stderr

    gzip -f ${OUT_DIR}/cmp.stdout ${OUT_DIR}/cmp.stderr

    touch_done "$DONE_TAG"
  fi
}


function run_rna_features_and_genes () {
  local CMD="$1"
  local DBNAME="$2"
  local SPECIES="$3"
  local ENS_DIR="$4"
  local OUT_DIR="$5"
  local TAG="$6"
  local OPTIONS="$7"

  local DONE_TAG='_rna_features'${TAG}
  if ! check_done "$DONE_TAG"; then
    echo "running RNAFeatures for ${CMD}:${DBNAME}" > /dev/stderr
    mkdir -p "$OUT_DIR"

    pushd $OUT_DIR

    # nonref_set_toplevel $CMD $DBNAME

    local REG_FILE=$OUT_DIR/prereqs/reg.conf
    gen_one_db_reg_conf $CMD $DBNAME $SPECIES $REG_FILE

    local SPECIES_TAG=$(echo $SPECIES | perl -pe 's/^([^_]{3})[^_]+(?:_([^_]{3}))?.*(_[^_]+)$/$1_$2$3/')

    # generic run init
    mkdir -p $OUT_DIR/rna_features
    init_pipeline.pl Bio::EnsEMBL::EGPipeline::PipeConfig::RNAFeatures_conf \
      $($CMD details script) \
      -registry $REG_FILE \
      -production_db "$($PROD_SERVER details url)""$PROD_DBNAME" \
      -hive_force_init 1\
      -pipeline_tag "_${SPECIES_TAG}" \
      -pipeline_dir $OUT_DIR/rna_features \
      -species $SPECIES \
      -eg_pipelines_dir $ENS_DIR/ensembl-production-imported \
      -no_summary_plots 1 \
      ${OPTIONS} \
      2> $OUT_DIR/init.stderr \
      1> $OUT_DIR/init.stdout
    tail $OUT_DIR/init.stderr $OUT_DIR/init.stdout

    local SYNC_CMD=$(cat $OUT_DIR/init.stdout | grep -- -sync'$' | perl -pe 's/^\s*//; s/"//g')
    local LOOP_CMD=$(cat $OUT_DIR/init.stdout | grep -- -loop | perl -pe 's/^\s*//; s/\s*#.*$//; s/"//g')

    echo "$SYNC_CMD" > $OUT_DIR/_continue_pipeline
    echo "$LOOP_CMD" >> $OUT_DIR/_continue_pipeline

    # LCA run init
    echo RNAFeatures with LCA...  > /dev/stderr
    mkdir -p $OUT_DIR/rna_features_lca
    init_pipeline.pl Bio::EnsEMBL::EGPipeline::PipeConfig::RNAFeatures_conf \
      $($CMD details script) \
      -registry $REG_FILE \
      -production_db "$($PROD_SERVER details url)""$PROD_DBNAME" \
      -hive_force_init 1 \
      -pipeline_tag "_lca_${SPECIES}" \
      -pipeline_dir $OUT_DIR/rna_features_lca \
      -species $SPECIES \
      -eg_pipelines_dir $ENS_DIR/ensembl-production-imported \
      -no_summary_plots 1 \
      -taxonomic_lca 1 \
      2> $OUT_DIR/init_lca.stderr \
      1> $OUT_DIR/init_lca.stdout
    tail $OUT_DIR/init_lca.stderr $OUT_DIR/init_lca.stdout

    local SYNC_CMD_LCA=$(cat $OUT_DIR/init_lca.stdout | grep -- -sync'$' | perl -pe 's/^\s*//; s/"//g')
    local LOOP_CMD_LCA=$(cat $OUT_DIR/init_lca.stdout | grep -- -loop | perl -pe 's/^\s*//; s/\s*#.*$//; s/"//g')

    echo "$SYNC_CMD_LCA" >> $OUT_DIR/_continue_pipeline
    echo "$LOOP_CMD_LCA" >> $OUT_DIR/_continue_pipeline

    local SPECIES_TAG=$(echo $SPECIES | perl -pe 's/^([^_]{3})[^_]+(?:_([^_]{3}))?.*(_[^_]+)$/$1_$2$3/')

    # Create genes from the RNA features
    local RNA_GENES_CONTEXT='vb'
    echo RNAFeatures to genes with $RNA_GENES_CONTEXT context...  > /dev/stderr
    mkdir -p $OUT_DIR/rna_genes
    init_pipeline.pl Bio::EnsEMBL::EGPipeline::PipeConfig::RNAGenes_conf \
      $($CMD details script) \
      -registry $REG_FILE \
      -production_db "$($PROD_SERVER details url)""$PROD_DBNAME" \
      -hive_force_init 1 \
      -pipeline_tag "_${SPECIES_TAG}" \
      -pipeline_dir $OUT_DIR/rna_genes \
      -species $SPECIES \
      -eg_pipelines_dir $ENS_DIR/ensembl-production-imported \
      -all_new_species 1 \
      -run_context $RNA_GENES_CONTEXT \
      -id_db_pass "" \
      2> $OUT_DIR/init_f2g.stderr \
      1> $OUT_DIR/init_f2g.stdout
    tail $OUT_DIR/init_f2g.stderr $OUT_DIR/init_f2g.stdout


    local SYNC_CMD_F2G=$(cat $OUT_DIR/init_f2g.stdout | grep -- -sync'$' | perl -pe 's/^\s*//; s/"//g')
    local LOOP_CMD_F2G=$(cat $OUT_DIR/init_f2g.stdout | grep -- -loop | perl -pe 's/^\s*//; s/\s*#.*$//; s/"//g')

    echo "$SYNC_CMD_F2G" >> $OUT_DIR/_continue_pipeline
    echo "$LOOP_CMD_F2G" >> $OUT_DIR/_continue_pipeline

    echo "# nonref_unset_toplevel $CMD $DBNAME" >> $OUT_DIR/_continue_pipeline
    echo "popd" >> $OUT_DIR/_continue_pipeline
    echo "fix_gene_ids_after_rna_pipeline $CMD $DBNAME $OUT_DIR/fix_genes" >> $OUT_DIR/_continue_pipeline
    echo "touch $DONE_TAGS_DIR/${DONE_TAG}" >> $OUT_DIR/_continue_pipeline

    # generic run
    echo Running pipeline...  > /dev/stderr
    echo See $OUT_DIR/_continue_pipeline if failed...  > /dev/stderr
    cat $OUT_DIR/_continue_pipeline > /dev/stderr

    $SYNC_CMD \
      2> $OUT_DIR/sync.stderr \
      1> $OUT_DIR/sync.stdout
    tail $OUT_DIR/sync.stderr $OUT_DIR/sync.stdout

    $LOOP_CMD \
      2> $OUT_DIR/loop.stderr \
      1> $OUT_DIR/loop.stdout
    tail $OUT_DIR/loop.stderr $OUT_DIR/loop.stdout

    # LCA Run
    echo Running pipeline...  > /dev/stderr
    echo See $OUT_DIR/_continue_pipeline if failed...  > /dev/stderr
    cat $OUT_DIR/_continue_pipeline > /dev/stderr

    $SYNC_CMD_LCA \
      2> $OUT_DIR/sync_lca.stderr \
      1> $OUT_DIR/sync_lca.stdout
    tail $OUT_DIR/sync_lca.stderr $OUT_DIR/sync_lca.stdout

    $LOOP_CMD_LCA \
      2> $OUT_DIR/loop_lca.stderr \
      1> $OUT_DIR/loop_lca.stdout
    tail $OUT_DIR/loop_lca.stderr $OUT_DIR/loop_lca.stdout

    # Create genes from the RNA features
    echo Running genes from RNA features pipeline...  > /dev/stderr
    echo See $OUT_DIR/_continue_pipeline if failed...  > /dev/stderr
    cat $OUT_DIR/_continue_pipeline > /dev/stderr

    $SYNC_CMD_F2G \
      2> $OUT_DIR/sync_f2g.stderr \
      1> $OUT_DIR/sync_f2g.stdout
    tail $OUT_DIR/sync_f2g.stderr $OUT_DIR/sync_f2g.stdout

    $LOOP_CMD_F2G \
      2> $OUT_DIR/loop_f2g.stderr \
      1> $OUT_DIR/loop_f2g.stdout
    tail $OUT_DIR/loop_f2g.stderr $OUT_DIR/loop_f2g.stdout


    # nonref_unset_toplevel $CMD $DBNAME
    fix_gene_ids_after_rna_pipeline $CMD $DBNAME $OUT_DIR/fix_genes
    popd

    touch_done "$DONE_TAG"
  fi
}


function run_rna_genes () {
  local CMD="$1"
  local DBNAME="$2"
  local SPECIES="$3"
  local ENS_DIR="$4"
  local OUT_DIR="$5"
  local TAG="$6"
  local OPTIONS="$7"

  local DONE_TAG='_rna_genes'${TAG}
  if ! check_done "$DONE_TAG"; then
    echo "running RNAGenes for ${CMD}:${DBNAME}" > /dev/stderr
    mkdir -p "$OUT_DIR"

    pushd $OUT_DIR

    # nonref_set_toplevel $CMD $DBNAME

    local REG_FILE=$OUT_DIR/prereqs/reg.conf
    gen_one_db_reg_conf $CMD $DBNAME $SPECIES $REG_FILE

    # generic run init
    local SPECIES_TAG=$(echo $SPECIES | perl -pe 's/^([^_]{3})[^_]+(?:_([^_]{3}))?.*(_[^_]+)$/$1_$2$3/')

    # Create genes from the RNA features
    echo RNAFeatures to genes...  > /dev/stderr
    mkdir -p $OUT_DIR/rna_genes
    init_pipeline.pl Bio::EnsEMBL::EGPipeline::PipeConfig::RNAGenes_conf \
      $($CMD details script) \
      -registry $REG_FILE \
      -production_db "$($PROD_SERVER details url)""$PROD_DBNAME" \
      -hive_force_init 1 \
      -pipeline_tag "_${SPECIES_TAG}" \
      -pipeline_dir $OUT_DIR/rna_genes \
      -species $SPECIES \
      -eg_pipelines_dir $ENS_DIR/ensembl-production-imported \
      -all_new_species 1 \
      -id_db_pass "" \
      -run_context vb \
      ${OPTIONS} \
      2> $OUT_DIR/init_f2g.stderr \
      1> $OUT_DIR/init_f2g.stdout
    tail $OUT_DIR/init_f2g.stderr $OUT_DIR/init_f2g.stdout


    local SYNC_CMD_F2G=$(cat $OUT_DIR/init_f2g.stdout | grep -- -sync'$' | perl -pe 's/^\s*//; s/"//g')
    local LOOP_CMD_F2G=$(cat $OUT_DIR/init_f2g.stdout | grep -- -loop | perl -pe 's/^\s*//; s/\s*#.*$//; s/"//g')

    echo "$SYNC_CMD_F2G" >> $OUT_DIR/_continue_pipeline
    echo "$LOOP_CMD_F2G" >> $OUT_DIR/_continue_pipeline

    echo "# nonref_unset_toplevel $CMD $DBNAME" >> $OUT_DIR/_continue_pipeline
    echo "popd" >> $OUT_DIR/_continue_pipeline
    echo "fix_gene_ids_after_rna_pipeline $CMD $DBNAME $OUT_DIR/fix_genes" >> $OUT_DIR/_continue_pipeline
    echo "touch $DONE_TAGS_DIR/${DONE_TAG}" >> $OUT_DIR/_continue_pipeline


    # Create genes from the RNA features
    echo Running genes from RNA features pipeline...  > /dev/stderr
    echo See $OUT_DIR/_continue_pipeline if failed...  > /dev/stderr
    cat $OUT_DIR/_continue_pipeline > /dev/stderr

    $SYNC_CMD_F2G \
      2> $OUT_DIR/sync_f2g.stderr \
      1> $OUT_DIR/sync_f2g.stdout
    tail $OUT_DIR/sync_f2g.stderr $OUT_DIR/sync_f2g.stdout

    $LOOP_CMD_F2G \
      2> $OUT_DIR/loop_f2g.stderr \
      1> $OUT_DIR/loop_f2g.stdout
    tail $OUT_DIR/loop_f2g.stderr $OUT_DIR/loop_f2g.stdout

    # nonref_unset_toplevel $CMD $DBNAME
    fix_gene_ids_after_rna_pipeline $CMD $DBNAME $OUT_DIR/fix_genes
    popd

    touch_done "$DONE_TAG"
  fi
}


function run_rna_features () {
  local CMD="$1"
  local DBNAME="$2"
  local SPECIES="$3"
  local ENS_DIR="$4"
  local OUT_DIR="$5"
  local TAG="$6"
  local OPTIONS="$7"

  local DONE_TAG='_rna_features'${TAG}
  if ! check_done "$DONE_TAG"; then
    echo "running RNAFeatures for ${CMD}:${DBNAME} with options: ${OPTIONS}" > /dev/stderr
    mkdir -p "$OUT_DIR"

    pushd $OUT_DIR

    local REG_FILE=$OUT_DIR/prereqs/reg.conf
    gen_one_db_reg_conf $CMD $DBNAME $SPECIES $REG_FILE

    local SPECIES_TAG=$(echo $SPECIES | perl -pe 's/^([^_]{3})[^_]+(?:_([^_]{3}))?.*(_[^_]+)$/$1_$2$3/')

    # generic run init
    mkdir -p $OUT_DIR/rna_features
    init_pipeline.pl Bio::EnsEMBL::EGPipeline::PipeConfig::RNAFeatures_conf \
      $($CMD details script) \
      -registry $REG_FILE \
      -production_db "$($PROD_SERVER details url)""$PROD_DBNAME" \
      -hive_force_init 1\
      -pipeline_tag "_${SPECIES_TAG}" \
      -pipeline_dir $OUT_DIR/rna_features \
      -species $SPECIES \
      -eg_pipelines_dir $ENS_DIR/ensembl-production-imported \
      -no_summary_plots 1 \
      ${OPTIONS} \
      2> $OUT_DIR/init.stderr \
      1> $OUT_DIR/init.stdout
    tail $OUT_DIR/init.stderr $OUT_DIR/init.stdout

    local SYNC_CMD=$(cat $OUT_DIR/init.stdout | grep -- -sync'$' | perl -pe 's/^\s*//; s/"//g')
    local LOOP_CMD=$(cat $OUT_DIR/init.stdout | grep -- -loop | perl -pe 's/^\s*//; s/\s*#.*$//; s/"//g')

    echo "$SYNC_CMD" > $OUT_DIR/_continue_pipeline
    echo "$LOOP_CMD" >> $OUT_DIR/_continue_pipeline

    echo "popd" >> $OUT_DIR/_continue_pipeline
    echo "touch $DONE_TAGS_DIR/${DONE_TAG}" >> $OUT_DIR/_continue_pipeline

    # generic run
    echo Running pipeline...  > /dev/stderr
    echo See $OUT_DIR/_continue_pipeline if failed...  > /dev/stderr
    cat $OUT_DIR/_continue_pipeline > /dev/stderr

    $SYNC_CMD \
      2> $OUT_DIR/sync.stderr \
      1> $OUT_DIR/sync.stdout
    tail $OUT_DIR/sync.stderr $OUT_DIR/sync.stdout

    $LOOP_CMD \
      2> $OUT_DIR/loop.stderr \
      1> $OUT_DIR/loop.stdout
    tail $OUT_DIR/loop.stderr $OUT_DIR/loop.stdout

    popd

    touch_done "$DONE_TAG"
  fi
}


function fix_gene_ids_after_rna_pipeline () {
  local CMD="$1"
  local DBNAME="$2"
  local OUT_DIR="$3"

  mkdir -p "$OUT_DIR"

  local MAX_GENE=$($CMD -D $DBNAME -e 'select stable_id from gene' -N | sort | tail -1 )
  local MAX_GENE_PFX=$(echo $MAX_GENE | perl -pe 's/\d+$//')
  local MAX_GENE_NUM_PRE=$(( $(echo $MAX_GENE | perl -pe 's/[^\d]+0*(\d+)$/$1/') + 1 ))
  local GENE_COUNT=$(( $($CMD -D $DBNAME -e 'select count(*) from gene' -N) + 1 ))
  local MAX_GENE_NUM=$(python -c "print max($MAX_GENE_NUM_PRE, $GENE_COUNT) + 100")
  # TODO: get max ids from old_core_db:

  echo "Updating gene ids produced by rna pipelines $MAX_GENE $MAX_GENE_PFX $MAX_GENE_NUM" > /dev/stderr

  $CMD -D $DBNAME -e 'select gene_id, stable_id from gene' -N |
    awk -F "\t" -v max_id=$MAX_GENE_NUM -v pfx=$MAX_GENE_PFX 'BEGIN {}
      (seen[$2]) {printf($0"\t%s%06d\tupdate gene set stable_id=\"%s%06d\" where gene_id=\"%d\" and stable_id = \"%s\";\n", pfx, max_id, pfx, max_id, $1, $2); max_id++; }
      {seen[$2]++}' > ${OUT_DIR}/gene_patches.pre

  cat ${OUT_DIR}/gene_patches.pre | cut -f 4 | $CMD -D $DBNAME

  # transcripts
  cat ${OUT_DIR}/gene_patches.pre | cut -f 1-3 | awk -F "\t" 'BEGIN {}
    {printf($0"\tupdate transcript set stable_id=replace(stable_id, \"%s\", \"%s\") where gene_id=\"%d\";\n", $2, $3, $1); }' > ${OUT_DIR}/transcript_patches.pre

  cat ${OUT_DIR}/transcript_patches.pre | cut -f 4 | $CMD -D $DBNAME

  #exons
  $CMD -D $DBNAME -e 'select tr.gene_id, et.exon_id from exon_transcript et, transcript tr where tr.transcript_id = et.transcript_id' -N | sort -k1,1 > ${OUT_DIR}/gene_exon.ids
  cat ${OUT_DIR}/transcript_patches.pre | cut -f 1-3 |
    sort -k1,1 | join -j 1 -t $'\t' ${OUT_DIR}/gene_exon.ids - |
    awk -F "\t" '{printf($0"\tupdate exon set stable_id=replace(stable_id, \"%s\", \"%s\") where exon_id=\"%d\";\n", $3, $4, $2); }' > ${OUT_DIR}/exon_patches.pre

  cat ${OUT_DIR}/exon_patches.pre | cut -f 5 | $CMD -D $DBNAME

  # #update source
  # $CMD -D $DBNAME -e 'update gene set source = "VectorBase" where source = "Ensembl_Metazoa"';
  # $CMD -D $DBNAME -e 'update transcript set source = "VectorBase" where source = "Ensembl_Metazoa"';
}

function preprocess_gff () {
  local GFF_FILE="$1"
  local PATCHER="$2"
  local OUT_FILE="$3"
  local TAG="$4"

  local DONE_TAG='_preprocess_gff'"$TAG"
  if ! check_done "$DONE_TAG"; then
    echo "patching raw gff $GFF_FILE using $PATCHER..." > /dev/stderr
    local OUT_DIR="$(dirname $OUT_FILE)"
    mkdir -p $OUT_DIR

    less $GFF_FILE | $PATCHER > $OUT_FILE

    touch_done "$DONE_TAG"
  fi
}

function gen_map_file () {
  local IN_FILE="$1"
  local PATCHER="$2"
  local OUT_FILE="$3"
  local TAG="$4"

  local DONE_TAG='_gen_map_file'"$TAG"
  if ! check_done "$DONE_TAG"; then
    echo "generating map file $OUT_FILE from $IN_FILE using $PATCHER..." > /dev/stderr
    local OUT_DIR="$(dirname $OUT_FILE)"
    mkdir -p $OUT_DIR

    less $IN_FILE | $PATCHER > $OUT_FILE

    touch_done "$DONE_TAG"
  fi
}

function mark_tr_trans_spliced () {
  local CMD="$1"
  local DBNAME="$2"
  local ID_LIST="$3"
  local TAG="$4"

  local DONE_TAG='_mark_tr_trans_spliced'"$TAG"
  local COUNT=$(echo $ID_LIST | perl -pe 's/,/\n/g' | wc -l)
  if ! check_done "$DONE_TAG"; then
    echo "setting trans_spliced attrib (503) for $COUNT transcripts in $CMD:$DBNAME..." > /dev/stderr
    echo $ID_LIST |
      perl -pe 's/[,\s+]/\n/g' |
      xargs -n 1 -I XXX echo 'insert into transcript_attrib select transcript_id, 503, 1 from transcript where stable_id in ("XXX");' |
      $CMD -D $DBNAME

    touch_done "$DONE_TAG"
  fi
}


function load_chromosome_bands_from_gff () {
  local CMD="$1"
  local DBNAME="$2"
  local GFF_FILE="$3"
  local SCRIPTS="$4"
  local OUT_DIR="$5"
  local TAG="$6"

  local DONE_TAG='_load_chr_bands'"$TAG"
  if ! check_done "$DONE_TAG"; then
    echo "loading chromosome bands for  $CMD:$DBNAME from $GFF_FILE..." > /dev/stderr
    mkdir -p $OUT_DIR
    less $GFF_FILE | grep -P '\tchromosome_band\t' > $OUT_DIR/bands.gff

    perl $SCRIPTS/archive/flybase/load_karyotype.pl \
      $($CMD details script) -dbname $DBNAME \
      -type chromosome_band -regex_for_id 'band-(\d+[A-Z]+\d+)_chromosome_band' \
      $OUT_DIR/bands.gff

    touch_done "$DONE_TAG"
  fi
}


function flybase_gff2xref () {
  local CMD="$1"
  local DBNAME="$2"
  local GFF_FILE="$3"
  local ENS_DIR="$4"
  local OUT_DIR="$5"
  local TAG="$6"

  local DONE_TAG='_gff2xref_flybase'"$TAG"
  if ! check_done "$DONE_TAG"; then
    echo "loading Xrefs from $GFF_FILE to $CMD:$DBNAME..." > /dev/stderr
    mkdir -p $OUT_DIR

    local pat=;
    for pat in gene:Gene mRna:Transcript protein:Translation; do
      local pat_from=$(echo $pat | cut -f 1 -d ':')
      local pat_to=$(echo $pat | cut -f 2 -d ':')
      local pat_to_lc=$(echo $pat_to | perl -ne 'print lc($_)')

      echo "Getting $pat_from xrefs from gff..."  > /dev/stderr
      less  $GFF_FILE |
        grep -P '\t'"$pat_from"'\t' |
        perl -pe 's/.*ID=([^;]+);.*Name=([^;]+);.*/$1\t$2/' |
        perl -pe 's/\\/\\\\/' |
        awk -F "\t" '{OFS="\t"; print $1, $1, $2}' |
        sort | uniq > ${OUT_DIR}/"$pat_from.from_gff.txt"

      ( echo "Inserting something like this as $pat_to:FlyBaseName_${pat_to_lc}: ";
        head -n 2 ${OUT_DIR}/"$pat_from.from_gff.txt" > /dev/stderr;
        echo ) > /dev/stderr

      cat ${OUT_DIR}/"$pat_from.from_gff.txt" |
        perl $ENS_DIR/ensembl-production-imported/scripts/misc_scripts/load_xref.pl \
        $($CMD details script) -dbname $DBNAME \
        -update_display_xref \
        -display_ne_primary_id \
        -object "$pat_to" -xref_name "FlyBaseName_${pat_to_lc}" \
        -info_type 'DIRECT' -info_text ''

      echo "Getting $pat_to_lc stable ids as xrefs..."  > /dev/stderr
      $CMD -D $DBNAME \
        -e 'select stable_id, stable_id from '"$pat_to_lc"' where stable_id is not NULL;' -N |
        sort | uniq > ${OUT_DIR}/"$pat_to_lc.from_stable.txt"

      ( echo "Inserting something like this as $pat_to:flybase_${pat_to_lc}_id ";
        head -n 2 ${OUT_DIR}/"$pat_to_lc.from_stable.txt" > /dev/stderr;
        echo ) > /dev/stderr

      cat ${OUT_DIR}/"$pat_to_lc.from_stable.txt" |
        perl $ENS_DIR/ensembl-production-imported/scripts/misc_scripts/load_xref.pl \
        $($CMD details script) -dbname $DBNAME \
        -object "$pat_to" -xref_name "flybase_${pat_to_lc}_id" \
        -info_type 'DIRECT' -info_text ''
    done

    for pat in Rfam:RFAM MIR:miRBase; do
      local pat_from=$(echo $pat | cut -f 1 -d ':')
      local pat_to=$(echo $pat | cut -f 2 -d ':')

      echo "Getting $pat_from xrefs from gff..."  > /dev/stderr
      less  $GFF_FILE |
        grep -P '\tgene\t.*Dbxref=[^;]*'"$pat_from" |
        perl -pe 's/.*ID=([^;]+);.*Dbxref=[^;]*'"${pat_from}"'\:([^;,]+).*/$1\t$2/' |
        awk -F "\t" '{OFS="\t"; print $1, $2, $2}' |
        sort | uniq > ${OUT_DIR}/"$pat_from.from_gff.txt"

      ( echo "Inserting something like this as Gene:$pat_to:";
        head -n 2 ${OUT_DIR}/"$pat_from.from_gff.txt" > /dev/stderr;
        echo ) > /dev/stderr

      cat ${OUT_DIR}/"$pat_from.from_gff.txt" |
        perl $ENS_DIR/ensembl-production-imported/scripts/misc_scripts/load_xref.pl \
        $($CMD details script) -dbname $DBNAME \
        -display_ne_primary_id \
        -object "Gene" -xref_name "$pat_to" \
        -info_type 'DIRECT' -info_text ''
    done

    touch_done "$DONE_TAG"
  fi
}

function update_prod_tables () {
  local CMD="$1"
  local DBNAME="$2"
  local SCRIPTS="$3"
  local OUT_DIR="$4"
  local TAG="$5"

  local DONE_TAG='_update_prod_tables'"$TAG"
  if ! check_done "$DONE_TAG"; then
    echo "updatin prod tables for $CMD:$DBNAME from $PROD_SERVER:$PROD_DBNAME..." > /dev/stderr
    mkdir -p $OUT_DIR

    perl $SCRIPTS/ensembl-production/scripts/production_database/populate_production_db_tables.pl\
      $($CMD details script) --database $DBNAME \
      $($PROD_SERVER details prefix_m) --mdatabase $PROD_DBNAME \
      --dumppath $OUT_DIR --dropbaks

    touch_done "$DONE_TAG"
  fi
}

function fopt_from_meta () {
  local META="$1"
  local TAG="$2"
  local DIR="$3"
  local OPT_NAME="$4"
  local ERR_ACTION="$5"

  local FNAME=$(get_meta_conf $META "$TAG")
  [ -n "$(echo $FNAME | grep  '^/')" ] && DIR= #use abs path
  if [ -n "$FNAME" -a -f "$DIR/$FNAME" ]; then
    echo $OPT_NAME "$DIR/$FNAME"
  else
    echo "No $TAG specified or '$DIR/$FNAME' doesn't exist" > /dev/stderr
    [ -n "$FNAME" ] && [ -n "$ERR_ACTION" ]  && $ERR_ACTION
  fi
}

function prepare_metada () {
  local META_RAW="$1"
  local ASM_DIR="$2"
  local SCRIPTS="$3"
  local OUT_DIR="$4"
  local TAG="$5"

  local DONE_TAG='_prepare_metadata'"$TAG"
  if ! check_done "$DONE_TAG"; then
    echo "generating metadata from raw $META_RAW..." > /dev/stderr
    mkdir -p $OUT_DIR

    local BRC4_LOAD=$BRC4_LOAD
    if [ -z "$BRC4_LOAD" ]; then
      BRC4_LOAD=$(get_meta_conf $META_RAW 'BRC4_LOAD')
      [ "$BRC4_LOAD" = "NO" ] && BRC4_LOAD=
      [ -n "$BRC4_LOAD" ] && export BRC4_LOAD
    fi

    local ASM_VERSION=$(get_meta_conf $META_RAW ASM_VERSION)
    local FNA_FILE=$(get_meta_conf $META_RAW FNA_FILE)

    local MCFG_GBFF_OPTS=$(fopt_from_meta $META_RAW GBFF_FILE $ASM_DIR '--gbff_file' false)
    local MCFG_ASM_REP_OPTS=$(fopt_from_meta $META_RAW ASM_REP_FILE $ASM_DIR  '--asm_rep_file' false)

    local GFF_PARSER_CONF_DIR="$SCRIPTS/new_genome_loader/scripts/gff_metaparser/conf"

    local MCFG_GFF_CAUSED_OPTS=''
    local GFF_PATH=$(fopt_from_meta $META_RAW GFF_FILE $ASM_DIR '' false)
    if [ -n "$GFF_PATH" ]; then
      local GFF_STATS_CONF=$(fopt_from_meta $META_RAW GFF_STATS_CONF $GFF_PARSER_CONF_DIR '' true)
      local GFF_STATS_OPTIONS=$(get_meta_conf $META_RAW GFF_STATS_OPTIONS)
      local GFF_STATS_BRC4_OPTIONS=

      local GFF_PARSER_CONF=$(fopt_from_meta $META_RAW GFF_PARSER_CONF $GFF_PARSER_CONF_DIR '' true)
      local GFF_PARSER_CONF_PATCH=$(fopt_from_meta $META_RAW GFF_PARSER_CONF_PATCH $GFF_PARSER_CONF_DIR '' true)
      local GFF_PARSER_OPTIONS=$(get_meta_conf $META_RAW GFF_PARSER_OPTIONS)
      local GFF_PARSER_BRC4_OPTIONS=

      if [ -n "$BRC4_LOAD" ]; then
        GFF_STATS_BRC4_OPTIONS="${GFF_STATS_OPTIONS} --rule_options load_pseudogene_with_CDS"

        GFF_PARSER_BRC4_OPTIONS="${GFF_PARSER_BRC4_OPTIONS}"
        if [ -z "$GFF_PARSER_CONF_PATCH" ]; then
          GFF_PARSER_CONF_PATCH="$GFF_PARSER_CONF_DIR/gff_metaparser/brc4.patch"
        fi
      fi

      # conf
      if [ -z "$GFF_STATS_CONF" ]; then
        GFF_STATS_CONF=$GFF_PARSER_CONF_DIR/valid_structures.conf
      fi
      if [ -z "$GFF_PARSER_CONF" ]; then
        GFF_PARSER_CONF=$GFF_PARSER_CONF_DIR/gff_metaparser.conf
      fi
      # pactch conf
      if [ -z "$GFF_PARSER_CONF_PATCH" ]; then
        GFF_PARSER_CONF_PATCH=NO
      fi

      # if NO remove option
      if [ "$GFF_PARSER_CONF_PATCH" == "NO" ]; then
        GFF_PARSER_CONF_PATCH=
      else
        GFF_PARSER_CONF_PATCH="--conf_patch $GFF_PARSER_CONF_PATCH"
      fi

      local GFF_PARSER_PFX_TRIM=$(get_meta_conf $META_RAW GFF_PARSER_PFX_TRIM)
      if [ -z "$GFF_PARSER_PFX_TRIM" ]; then
        GFF_PARSER_PFX_TRIM='ANY!:.+\|,ANY:id-,ANY:gene-,ANY:rna-,ANY:mrna-,cds:cds-,exon:exon-'
      fi
      if [ "$GFF_PARSER_PFX_TRIM" == "NO" ]; then
        GFF_PARSER_PFX_TRIM=
      else
        GFF_PARSER_PFX_TRIM="--pfx_trims $GFF_PARSER_PFX_TRIM"
      fi

      # remove #FASTA part
      less $GFF_PATH |
        sed -n '/^##FASTA/q; /^>/q; p' > $OUT_DIR/no_fasta.gff3 || true

      # initial validation
      local IGNORE_UNVALID_SOURCE_GFF=$(get_meta_conf $META_RAW IGNORE_UNVALID_SOURCE_GFF)
      gt gff3validator $OUT_DIR/no_fasta.gff3 \
          > $OUT_DIR/no_fasta_gff3validator.stdout \
          2> $OUT_DIR/no_fasta_gff3validator.stderr \
      || [ -n "$IGNORE_UNVALID_SOURCE_GFF" -a "x$IGNORE_UNVALID_SOURCE_GFF" != "xNO" ]  && true \
      || echo "unvalid source gff: $GFF_PATH. no IGNORE_UNVALID_SOURCE_GFF ($IGNORE_UNVALID_SOURCE_GFF) set. failing..." \
          > /dev/stderr || return false || exit 0

      # gen stats
      cat $OUT_DIR/no_fasta.gff3 |
        python $SCRIPTS/new_genome_loader/scripts/gff_metaparser/gff_stats.py \
          --dump_used_options \
          --fail_unknown \
          --conf $GFF_STATS_CONF \
          --stats_out $OUT_DIR/gff_stats.stats.out \
          --gff_out $OUT_DIR/pre_validated.gff3 \
          --detailed_report $OUT_DIR/gff_stats.detailed.log \
          $GFF_STATS_BRC4_OPTIONS \
          $GFF_STATS_OPTIONS \
          - \
          > $OUT_DIR/gff_stats.stdout 2> $OUT_DIR/gff_stats.stderr

      [ -f $OUT_DIR/gff_stats.detailed.log ] && gzip -f $OUT_DIR/gff_stats.detailed.log

      # tidy and validate gff3
      gt gff3 -tidy -sort -retainids $OUT_DIR/pre_validated.gff3 \
        > $OUT_DIR/validated.gff3  2> $OUT_DIR/gt_gff3_tidy.stderr
      gt gff3validator $OUT_DIR/validated.gff3 > $OUT_DIR/gt_gff3validator.stdout 2> $OUT_DIR/gt_gff3validator.stderr

      # ID prefices
      cat $OUT_DIR/gff_stats.stats.out |
        awk -F "\t" '$2 == "ID" {print $5}' |
        cut -f 1 -d '-' |
        sort | uniq > $OUT_DIR/gff_stats.id_pfx.u

      #exit if flag
      local STOP_AFTER_GFF_STATS=${STOP_AFTER_GFF_STATS}
      if [ -z "${STOP_AFTER_GFF_STATS}" ]; then
        STOP_AFTER_GFF_STATS=$(get_meta_conf $META_RAW 'STOP_AFTER_GFF_STATS')
      fi
      if [ -n "${STOP_AFTER_GFF_STATS}" -a "x${STOP_AFTER_GFF_STATS}" != "xNO" ]; then
        echo stoppping beacuse of the STOP_AFTER_GFF_STATS: "$STOP_AFTER_GFF_STATS" > /dev/stderr
        exit 0
        return false
      fi

      # prepare gff and json
      less $OUT_DIR/validated.gff3 |
        python $SCRIPTS/new_genome_loader/scripts/gff_metaparser/gff3_meta_parse.py \
          --dump_used_options \
          --conf $GFF_PARSER_CONF \
          $GFF_PARSER_CONF_PATCH \
          $GFF_PARSER_PFX_TRIM \
          $GFF_PARSER_OPTIONS \
          $GFF_PARSER_BRC4_OPTIONS \
          --gff_out $OUT_DIR/pre_models.gff3 \
          --fann_out $OUT_DIR/functional_annotation.json \
          --seq_region_out $OUT_DIR/seq_region_raw.json \
          - \
          > $OUT_DIR/gff3_meta_parse.stdout 2> $OUT_DIR/gff3_meta_parse.stderr

      # remove CDS ID duplicates not from the first scaffold met
      cat $OUT_DIR/pre_models.gff3 |
        python3 $SCRIPTS/ensembl-production-metazoa/scripts/cds_sr_filter.py \
        > $OUT_DIR/pre_models.cds_sr_filtered.gff3

      # tidy and validate models gff3
      gt gff3 -tidy -sort -retainids $OUT_DIR/pre_models.cds_sr_filtered.gff3 \
        > $OUT_DIR/models.gff3  2> $OUT_DIR/models_gff3_tidy.stderr
      gt gff3validator $OUT_DIR/models.gff3 > $OUT_DIR/models_gff3validator.stdout 2> $OUT_DIR/models_gff3validator.stderr

      MCFG_GFF_CAUSED_OPTS="--gff_file $OUT_DIR/models.gff3  --fann_file $OUT_DIR/functional_annotation.json --seq_region_raw $OUT_DIR/seq_region_raw.json"


      local PEP_FILE=$(fopt_from_meta $META_RAW PEP_FILE $ASM_DIR '' false)
      ###
      if [ -n "$PEP_FILE" ]; then
        less $PEP_FILE |
          perl -pe 's/\./\*/g if !m/^>/' \
            > $OUT_DIR/pep_fasta.corrected_stops.faa
        local MCFG_PEP_OPTS="--fasta_pep  $OUT_DIR/pep_fasta.corrected_stops.faa"

        local PEP_MODIFY_ID=$(get_meta_conf $META_RAW PEP_MODIFY_ID)
        if [ -n "$PEP_MODIFY_ID" -a "x$PEP_MODIFY_ID" != "xNO" ]; then
          local PEP_FILE=$(fopt_from_meta $META_RAW PEP_FILE $ASM_DIR '' false)
          less $PEP_FILE |
            perl -pe 's/\./\*/g if !m/^>/' |
            perl -pe "${PEP_MODIFY_ID} if m/^>/" \
              > $OUT_DIR/pep_fasta.changed_ids.faa
          MCFG_PEP_OPTS="--fasta_pep  $OUT_DIR/pep_fasta.changed_ids.faa"
        fi
      fi
      ###

      MCFG_GFF_CAUSED_OPTS="$MCFG_GFF_CAUSED_OPTS $MCFG_PEP_OPTS"
    fi

    # ad hoc seq regions gff
    local SR_GFF_FILE=$(fopt_from_meta $META_RAW SR_GFF_FILE $ASM_DIR '' true)
    if [ -n "$SR_GFF_FILE" -a -f "$SR_GFF_FILE" ]; then
      echo getting annditional region data from gff $SR_GFF_FILE > /dev/stderr
      less $SR_GFF_FILE |
        awk -F "\t" \
          '($3 == "region") {print}
           ($3 == "CDS" && $9 ~ /transl_table=/ && !seen[$1]) {print; seen[$1] = 1}' \
        > $OUT_DIR/sr_gff.gff3

      local SR_GFF_PARSER_CONF=$(fopt_from_meta $META_RAW SR_GFF_PARSER_CONF $GFF_PARSER_CONF_DIR '' true)
      local SR_GFF_PARSER_OPTIONS=$(get_meta_conf $META_RAW SR_GFF_PARSER_OPTIONS)

      if [ -z "$SR_GFF_PARSER_CONF" ]; then
        SR_GFF_PARSER_CONF=$GFF_PARSER_CONF_DIR/gff_metaparser.conf
      fi

      local SR_GFF_PARSER_CONF_PATCH=$(fopt_from_meta $META_RAW 'SR_GFF_PARSER_CONF_PATCH' $GFF_PARSER_CONF_DIR '--conf_patch' true)

      cat $OUT_DIR/sr_gff.gff3 |
        python $SCRIPTS/new_genome_loader/scripts/gff_metaparser/gff3_meta_parse.py \
          --dump_used_options \
          --conf $SR_GFF_PARSER_CONF \
          $SR_GFF_PARSER_CONF_PATCH \
          $SR_GFF_PARSER_OPTIONS \
          --gff_out /dev/null \
          --fann_out /dev/null \
          --seq_region_out $OUT_DIR/seq_region_raw.ad_hoc.json \
          - \
          > $OUT_DIR/sr_gff3_parser.stdout 2> $OUT_DIR/sr_gff3_parser.stderr

      MCFG_GFF_CAUSED_OPTS="$MCFG_GFF_CAUSED_OPTS --seq_region_genbank $OUT_DIR/seq_region_raw.ad_hoc.json"
    fi # ad hoc seq regions gff

    local SEQ_REGION_SOURCE_DEFAULT=$(get_meta_conf $META_RAW SEQ_REGION_SOURCE_DEFAULT)
    if [ -z "$SEQ_REGION_SOURCE_DEFAULT" ]; then
      SEQ_REGION_SOURCE_DEFAULT="GenBank"
    fi

    python $SCRIPTS/new_genome_loader/scripts/gff_metaparser/gen_meta_conf.py \
      --assembly_version $ASM_VERSION \
      --data_out_dir $OUT_DIR \
      --raw_meta_conf $META_RAW \
      --fasta_dna $ASM_DIR/$FNA_FILE \
      $MCFG_GBFF_OPTS \
      $MCFG_ASM_REP_OPTS \
      $MCFG_GFF_CAUSED_OPTS \
      --syns_src $SEQ_REGION_SOURCE_DEFAULT \
      --genome_conf  $OUT_DIR/genome.json \
      --seq_region_conf $OUT_DIR/seq_region.json \
      --manifest_out $OUT_DIR/manifest.json \
      --meta_out $OUT_DIR/meta

    touch_done "$DONE_TAG"
  fi
}

function run_new_loader () {
  local CMD_W="$1"
  local RELEASE_V="$2"
  local META_DIR="$3"
  local ENS_PROD="$4"
  local OUT_DIR="$5"
  local TAG="$6"

  local DONE_TAG='_load_new'"$TAG"
  if ! check_done "$DONE_TAG"; then
    echo "loading new species based on metadata fromr$META_DIR..." > /dev/stderr
    [ -d "$OUT_DIR" ] && mkdir -p "$OUT_DIR"/old && mv -f "$OUT_DIR"/* "$OUT_DIR"/old || true
    mkdir -p $OUT_DIR

    local META_FILE=$META_DIR/meta
    local META_FILE_RAW=$(get_meta_conf $META_FILE 'META_FILE_RAW')
    if [ -z "$META_FILE_RAW" ]; then
      META_FILE_RAW=$META_FILE
    fi

    local DB_PFX=$(get_meta_conf $META_FILE_RAW DB_PFX)
    local DB_PFX_RAW="${DB_PFX}"

    if [ -n "$DB_PFX" ]; then
      DB_PFX="--db_prefix $DB_PFX"
    else
      [ -n "$TAG" ] && DB_PFX="--db_prefix $TAG"
      DB_PFX_RAW="${TAG}"
    fi

    local SPECIES=$(get_meta_str $META_FILE 'species.production_name')
    local SPECIES_TAG=$(echo $SPECIES | perl -pe 's/^([^_]{3})[^_]+(?:_([^_]{3}))?.*(_[^_]+)$/$1_$2$3/')
    local ORDERED_CS_TAG=$(get_meta_conf $META_FILE 'ORDERED_CS_TAG')
    if [ -z "$ORDERED_CS_TAG" ]; then
      ORDERED_CS_TAG="chromosome"
    fi

    local BRC4_LOAD=$BRC4_LOAD
    if [ -z "$BRC4_LOAD" ]; then
      BRC4_LOAD=$(get_meta_conf $META_FILE_RAW 'BRC4_LOAD')
      [ "$BRC4_LOAD" = "NO" ] && BRC4_LOAD=
      [ -n "$BRC4_LOAD" ] && export BRC4_LOAD
    fi

    local GFF3_LOAD_LOGIC_NAME=$(get_meta_conf $META_FILE_RAW 'GFF3_LOAD_LOGIC_NAME')
    if [ -z "$GFF3_LOAD_LOGIC_NAME" ]; then
      if [ -z "$BRC4_LOAD" ]; then
         GFF3_LOAD_LOGIC_NAME='refseq_import_visible'
      else
         GFF3_LOAD_LOGIC_NAME='gff3_genes'
      fi
    fi

    local GFF3_LOAD_SOURCE_NAME=$(get_meta_conf $META_FILE_RAW 'GFF3_LOAD_SOURCE_NAME')
    if [ -z "$GFF3_LOAD_SOURCE_NAME" ]; then
      if [ -z "$BRC4_LOAD" ]; then
         GFF3_LOAD_SOURCE_NAME='Ensembl_Metazoa'
      else
         GFF3_LOAD_SOURCE_NAME='Ensembl_Metazoa'
      fi
    fi

    local GCF_TO_GCA=$(get_meta_conf $META_FILE_RAW 'GCF_TO_GCA')
    if [ -n "$GCF_TO_GCA" ]; then
      GCF_TO_GCA="--swap_gcf_gca 1"
    fi

    local ADHOC_OPTIONS="--load_pseudogene_with_CDS 0 --no_brc4_stuff 1 --ignore_final_stops 1 --xref_display_db_default Ensembl_Metazoa --xref_load_logic_name $GFF3_LOAD_LOGIC_NAME"
    ADHOC_OPTIONS="$ADHOC_OPTIONS --gff3_load_logic_name $GFF3_LOAD_LOGIC_NAME --gff3_load_gene_source $GFF3_LOAD_SOURCE_NAME"
    # feature versions are allowed only for brc4 and for 'build' not 'import'ed gene sets
    ADHOC_OPTIONS="$ADHOC_OPTIONS --no_feature_version_defaults 1"
    # do not clean anything from xrefs silently
    ADHOC_OPTIONS="$ADHOC_OPTIONS --skip_ensembl_xrefs 0"
    if [ -n "$BRC4_LOAD" ]; then
      ADHOC_OPTIONS=""
    fi

    local GFF_LOADER_OPTIONS=$(get_meta_conf $META_FILE_RAW 'GFF_LOADER_OPTIONS')

    # gen registry
    local REG_FILE=$OUT_DIR/prereqs/reg.conf
    gen_pfx_reg_conf $CMD_W $DB_PFX_RAW $REG_FILE

    # try to set max_allowed_packet size
    $CMD_W -e 'SET GLOBAL max_allowed_packet=2147483648;' || true

    init_pipeline.pl Bio::EnsEMBL::Pipeline::PipeConfig::BRC4_genome_loader_conf \
      $($CMD_W details hive) \
      --hive_force_init 1 \
      --registry $REG_FILE \
      --pipeline_tag "_${SPECIES_TAG}" \
      --ensembl_root_dir $ENS_PROD \
      --dbsrv_url $($CMD_W details url) \
      --proddb_url $($PROD_SERVER details url)"$PROD_DBNAME" \
      --taxonomy_url $($PROD_SERVER details url)"$TAXONOMY_DBNAME" \
      --data_dir $META_DIR \
      --pipeline_dir $OUT_DIR \
      --release $RELEASE_V \
      --check_manifest 1 \
      --prune_agp 0 \
      --unversion_scaffolds 1 \
      --cs_tag_for_ordered "$ORDERED_CS_TAG" \
      $DB_PFX \
      $ADHOC_OPTIONS \
      $GFF_LOADER_OPTIONS \
      $GCF_TO_GCA \
      2> $OUT_DIR/init.stderr \
      1> $OUT_DIR/init.stdout
    tail $OUT_DIR/init.stderr $OUT_DIR/init.stdout

    local SYNC_CMD=$(cat $OUT_DIR/init.stdout | grep -- -sync'$' | perl -pe 's/^\s*//; s/"//g')
    local LOOP_CMD=$(cat $OUT_DIR/init.stdout | grep -- -loop | perl -pe 's/^\s*//; s/\s*#.*$//; s/"//g')

    echo "$SYNC_CMD" > $OUT_DIR/_continue_pipeline
    echo "$LOOP_CMD" >> $OUT_DIR/_continue_pipeline

    echo "touch $DONE_TAGS_DIR/$DONE_TAG" >> $OUT_DIR/_continue_pipeline

    echo Running pipeline...  > /dev/stderr
    echo See $OUT_DIR/_continue_pipeline if failed...  > /dev/stderr
    cat $OUT_DIR/_continue_pipeline > /dev/stderr

    $SYNC_CMD \
      2> $OUT_DIR/sync.stderr \
      1> $OUT_DIR/sync.stdout
    tail $OUT_DIR/sync.stderr $OUT_DIR/sync.stdout

    $LOOP_CMD \
      2> $OUT_DIR/loop.stderr \
      1> $OUT_DIR/loop.stdout
    tail $OUT_DIR/loop.stderr $OUT_DIR/loop.stdout

    local failed_jobs=$($SYNC_CMD --failed_jobs 2>/dev/null | grep -cF 'status=FAILED')
    if [ "$failed_jobs" -gt "0" ]; then
      echo $failed_jobs failed jobs in loader...> /dev/stderr
      false
    fi

    touch_done "$DONE_TAG"
  fi
}

function get_repbase_lib () {
  local SPECIES="$1"
  local CMD="$2"
  local DBNAME="$3"
  local OUT_DIR="$4"
  local TAG="$5"

  local REPUTIL="$REPUTIL_PATH"/queryRepeatDatabase.pl

  local DONE_TAG='_get_repbase'"$TAG"
  if ! check_done "$DONE_TAG"; then
    echo "getting data from repeatmasker libs for species ${SPECIES}..." > /dev/stderr
    mkdir -p $OUT_DIR

    echo $SPECIES |  perl -pe 's/[ _]+/_/g' > $OUT_DIR/name_set.pre
    $CMD -D $DBNAME \
      -Ne 'select meta_value from meta where meta_key = "species.classification" order by meta_id' |
      perl -pe 's/[ _]+/_/g' >> $OUT_DIR/name_set.pre

    local name=
    for name in $(cat $OUT_DIR/name_set.pre); do
      local repname="$(echo $name | perl -pe 's/_/ /g' )"
      echo getting RepBase data for "'$repname'" > /dev/stderr
      $REPUTIL -species "$repname" > $OUT_DIR/repbase.lib 2> $OUT_DIR/err.log
      local repcnt=$(grep -c '>' $OUT_DIR/repbase.lib)
      if [ "$repcnt" -gt 0 ]; then
        break
      fi
      echo failed to get RepBase data for "'$repname'" > /dev/stderr
      name=
      rm -f $OUT_DIR/repbase.lib
    done
    if [ -n "$name" ]; then
      echo "$name" > $OUT_DIR/_repbase_species_name
    else
      echo $SPECIES | perl -pe 's/[ _]+/_/g' > $OUT_DIR/_repbase_species_name
    fi

    touch_done "$DONE_TAG"
  fi
}

function update_prod_tables_new () {
  local CMD="$1"
  local DBNAME="$2"
  local SPECIES="$3"
  local OUT_DIR="$4"
  local TAG="$5"

  local DONE_TAG='_update_prod_tables_new'"$TAG"
  if ! check_done "$DONE_TAG"; then
    echo "running production dbsync pipeline for ${CMD}:${DBNAME}" > /dev/stderr
    mkdir -p "$OUT_DIR"

    pushd $OUT_DIR

    local REG_FILE=$OUT_DIR/prereqs/reg.conf
    gen_one_db_reg_conf $CMD $DBNAME $SPECIES $REG_FILE

    local SPECIES_TAG=$(echo $SPECIES | perl -pe 's/^([^_]{3})[^_]+(?:_([^_]{3}))?.*(_[^_]+)$/$1_$2$3/')

    init_pipeline.pl Bio::EnsEMBL::Production::Pipeline::PipeConfig::ProductionDBSync_conf \
      $($CMD details hive) \
      -pipeline_name "prod_db_sync_${SPECIES_TAG}" \
      -hive_force_init 1\
      -registry $REG_FILE \
      -division "metazoa" \
      -group core \
      -backup_dir $OUT_DIR \
      2> $OUT_DIR/init.stderr \
      1> $OUT_DIR/init.stdout
    tail $OUT_DIR/init.stderr $OUT_DIR/init.stdout

    local SYNC_CMD=$(cat $OUT_DIR/init.stdout | grep -- -sync'$' | perl -pe 's/^\s*//; s/"//g')
    local LOOP_CMD=$(cat $OUT_DIR/init.stdout | grep -- -loop | perl -pe 's/^\s*//; s/\s*#.*$//; s/"//g')

    echo "$SYNC_CMD" > $OUT_DIR/_continue_pipeline
    echo "$LOOP_CMD" >> $OUT_DIR/_continue_pipeline

    echo "popd" >> $OUT_DIR/_continue_pipeline
    echo "touch $DONE_TAGS_DIR/${DONE_TAG}" >> $OUT_DIR/_continue_pipeline

    # generic run
    echo Running pipeline...  > /dev/stderr
    echo See $OUT_DIR/_continue_pipeline if failed...  > /dev/stderr
    cat $OUT_DIR/_continue_pipeline > /dev/stderr

    $SYNC_CMD \
      2> $OUT_DIR/sync.stderr \
      1> $OUT_DIR/sync.stdout
    tail $OUT_DIR/sync.stderr $OUT_DIR/sync.stdout

    $LOOP_CMD \
      2> $OUT_DIR/loop.stderr \
      1> $OUT_DIR/loop.stdout
    tail $OUT_DIR/loop.stderr $OUT_DIR/loop.stdout

    popd

    touch_done "$DONE_TAG"
  fi
}

function patch_db_schema () {
  local CMD="$1"
  local DBNAME="$2"
  local SCRIPTS="$3"
  local OUT_DIR="$4"
  local TAG="$5"

  local DONE_TAG='_patch_schema'"$TAG"
  if ! check_done "$DONE_TAG"; then
    local CVER=$($CMD -D $DBNAME -Ne 'select  meta_value from meta where meta_key = "schema_version"')
    local NVER=$(($CVER + 1))

    echo "patching schema from $CVER to $NVER for for ${CMD}:${DBNAME}" > /dev/stderr
    mkdir -p "$OUT_DIR"
    ls -1 $SCRIPTS/ensembl.${NVER}/sql/patch_${CVER}_${NVER}*.sql > $OUT_DIR/patches.lst

    local PLOG=$OUT_DIR/patch.log
    echo -n > $PLOG
    cat $OUT_DIR/patches.lst |
      sort |
      xargs -n 1 -I XXX \
        sh -c "echo patching with XXX >> $PLOG; cat XXX | $CMD -D $DBNAME 2>> $PLOG"

    touch_done "$DONE_TAG"
  fi
}

function run_dc () {
  local CMD="$1"
  local DBNAME="$2"
  local SCRIPTS="$3"
  local OUT_DIR="$4"
  local TAG="$5"

  local DONE_TAG='_run_dc'"$TAG"
  if ! check_done "$DONE_TAG"; then
    echo "running datachecks for ${CMD}:${DBNAME}" > /dev/stderr
    mkdir -p "$OUT_DIR"

    pushd $OUT_DIR

    local CVER=$($CMD -D $DBNAME -Ne 'select  meta_value from meta where meta_key = "schema_version"')

    local OLD_PERL5LIB=$PERL5LIB
    echo $OLD_PERL5LIB > $OUT_DIR/_OLD_PERL5LIB

    CVER=".${CVER}"
    if [ -d $SCRIPTS/ensembl${CVER} -a -d $SCRIPTS/ensembl-datacheck${CVER} ]; then
      echo using $CVER versiond of ensembl and ensembl-datacheck > /dev/stderr
      PERL5LIB=$SCRIPTS/ensembl${CVER}/modules:$(echo $PERL5LIB | perl -pe 'chomp; $_=join(":", grep {$_ !~ m,/ensembl/modules/,} split(":", $_))')
      PERL5LIB=$SCRIPTS/ensembl-datacheck${CVER}/lib:$(echo $PERL5LIB | perl -pe 'chomp; $_=join(":", grep {$_ !~ m,/ensembl-datacheck/lib/,} split(":", $_))')
      export PERL5LIB
    else
      CVER=""
    fi

    # removing history file
    touch $OUT_DIR/dc.json
    rm $OUT_DIR/dc.json

    local SPECIES=$(get_db_prod_name $CMD $DBNAME)

    local REG_FILE=$OUT_DIR/prereqs/reg.conf
    gen_one_db_reg_conf $CMD $DBNAME $SPECIES $REG_FILE

    local SPECIES_TAG=$(echo $SPECIES | perl -pe 's/^([^_]{3})[^_]+(?:_([^_]{3}))?.*(_[^_]+)$/$1_$2$3/')

    local PIPELINE_DBNAME=dc_${SPECIES_TAG}

    # can be useful:  -parallelize_datachecks 1 \

    perl $SCRIPTS/ensembl-datacheck${CVER}/scripts/run_pipeline.pl \
      $($CMD details script_p) \
      -drop_pipeline_db \
      -pipeline_dbname ${PIPELINE_DBNAME} \
      -registry_file $REG_FILE \
      -dbtype core \
      -division metazoa \
      -group core \
      -datacheck_type critical \
      -history_file $OUT_DIR/dc.json \
      -output_dir $OUT_DIR/dc_output \
      -tag "Critical core datachecks for $SPECIES" \
      -email ${USER}@ebi.ac.uk \
      -old_server_uri $($CMD details url) \
      2> $OUT_DIR/init.stderr \
      1> $OUT_DIR/init.stdout
    tail $OUT_DIR/init.stderr $OUT_DIR/init.stdout

    local PIPELINE_URL="$($CMD details url $PIPELINE_DBNAME)"
    local SYNC_CMD="beekeeper.pl -url $PIPELINE_URL -reg_file $REG_FILE -sync"
    local LOOP_CMD="beekeeper.pl -url $PIPELINE_URL -reg_file $REG_FILE -loop"

    echo "$SYNC_CMD" > $OUT_DIR/_continue_pipeline
    echo "$LOOP_CMD" >> $OUT_DIR/_continue_pipeline

    echo "popd" >> $OUT_DIR/_continue_pipeline
    echo "export PERL5LIB=$OLD_PERL5LIB" >> $OUT_DIR/_continue_pipeline
    echo "touch $DONE_TAGS_DIR/${DONE_TAG}" >> $OUT_DIR/_continue_pipeline

    # generic run
    echo Running pipeline...  > /dev/stderr
    echo See $OUT_DIR/_continue_pipeline if failed...  > /dev/stderr
    cat $OUT_DIR/_continue_pipeline > /dev/stderr

    $SYNC_CMD \
      2> $OUT_DIR/sync.stderr \
      1> $OUT_DIR/sync.stdout
    tail $OUT_DIR/sync.stderr $OUT_DIR/sync.stdout

    $LOOP_CMD \
      2> $OUT_DIR/loop.stderr \
      1> $OUT_DIR/loop.stdout
    tail $OUT_DIR/loop.stderr $OUT_DIR/loop.stdout

    local DC_OUT=$(ls -1td $OUT_DIR/dc_output/* | head -n 1)
    cat ${DC_OUT}/${DBNAME}.txt |
      grep '^not ok' |
      cut -f 2 -d '-' |
      sort |
      uniq -c |
      sort -nr > $OUT_DIR/failed.lst

    if [ "$(cat $OUT_DIR/failed.lst | wc -l)" -gt 0 ]; then
      echo "non empty failed list: $OUT_DIR/failed.lst" > /dev/stderr
      false
    fi

    export PERL5LIB=$OLD_PERL5LIB
    popd

    touch_done "$DONE_TAG"
  fi
}

function run_core_stats_new () {
  local CMD="$1"
  local DBNAME="$2"
  local SPECIES="$3"
  local OUT_DIR="$4"
  local TAG="$5"

  local DONE_TAG='_run_core_stats_new'"$TAG"
  if ! check_done "$DONE_TAG"; then
    echo "running production core stats pipeline for ${CMD}:${DBNAME}" > /dev/stderr
    mkdir -p "$OUT_DIR"

    pushd $OUT_DIR

    local REG_FILE=$OUT_DIR/prereqs/reg.conf
    gen_one_db_reg_conf $CMD $DBNAME $SPECIES $REG_FILE

    local SPECIES_TAG=$(echo $SPECIES | perl -pe 's/^([^_]{3})[^_]+(?:_([^_]{3}))?.*(_[^_]+)$/$1_$2$3/')

    init_pipeline.pl Bio::EnsEMBL::Production::Pipeline::PipeConfig::CoreStatistics_conf \
      $($CMD details hive) \
      -pipeline_name "prod_core_stats_${SPECIES_TAG}" \
      -hive_force_init 1\
      -registry $REG_FILE \
      -division "metazoa" \
      -history_file $OUT_DIR/hist.json \
      -skip_metadata_check 1 \
      2> $OUT_DIR/init.stderr \
      1> $OUT_DIR/init.stdout
    tail $OUT_DIR/init.stderr $OUT_DIR/init.stdout

    local SYNC_CMD=$(cat $OUT_DIR/init.stdout | grep -- -sync'$' | perl -pe 's/^\s*//; s/"//g')
    local LOOP_CMD=$(cat $OUT_DIR/init.stdout | grep -- -loop | perl -pe 's/^\s*//; s/\s*#.*$//; s/"//g')

    echo "$SYNC_CMD" > $OUT_DIR/_continue_pipeline
    echo "$LOOP_CMD" >> $OUT_DIR/_continue_pipeline

    echo "popd" >> $OUT_DIR/_continue_pipeline
    echo "touch $DONE_TAGS_DIR/${DONE_TAG}" >> $OUT_DIR/_continue_pipeline

    # generic run
    echo Running pipeline...  > /dev/stderr
    echo See $OUT_DIR/_continue_pipeline if failed...  > /dev/stderr
    cat $OUT_DIR/_continue_pipeline > /dev/stderr

    $SYNC_CMD \
      2> $OUT_DIR/sync.stderr \
      1> $OUT_DIR/sync.stdout
    tail $OUT_DIR/sync.stderr $OUT_DIR/sync.stdout

    $LOOP_CMD \
      2> $OUT_DIR/loop.stderr \
      1> $OUT_DIR/loop.stdout
    tail $OUT_DIR/loop.stderr $OUT_DIR/loop.stdout

    local failed_jobs=$($SYNC_CMD --failed_jobs 2>/dev/null | grep -cF 'status=FAILED')
    if [ "$failed_jobs" -gt "0" ]; then
      echo $failed_jobs failed jobs in loader...> /dev/stderr
      false
    fi

    popd

    touch_done "$DONE_TAG"
  fi
}

function update_stable_ids () {
  local CMD="$1"
  local DBNAME="$2"
  local PREV_XREF_FILE="$3"
  local ADDITIONAL_OPTIONS="$4"
  local SCRIPTS="$5"
  local OUT_DIR="$6"
  local TAG="$7"

  local DONE_TAG='_update_stable_ids'"$TAG"
  if ! check_done "$DONE_TAG"; then
    echo "update stable_ids for for ${CMD}:${DBNAME}" > /dev/stderr
    mkdir -p "$OUT_DIR"

    pushd $OUT_DIR

    if [ -f "$PREV_XREF_FILE"  ] ; then
      local OPTIONS=" -type GeneID -dry_run 0 ${ADDITIONAL_OPTIONS}"
      less "$PREV_XREF_FILE" |
        perl $SCRIPTS/ensembl-production-metazoa/scripts/update_stable_ids_from_xref.pl \
          $($CMD details script) \
          -dbname $DBNAME \
          $OPTIONS \
          > $OUT_DIR/updated_list.txt \
          2> $OUT_DIR/updated.stderr
      echo "updated:" > /dev/stderr
      cat $OUT_DIR/updated_list.txt | cut -f 1 | sort | uniq -c > /dev/stderr
      tail $OUT_DIR/updated.stderr
    else
      echo "not prev xrefs file ($PREV_XREF_FILE) found" > /dev/stderr
      false
    fi

    popd

    touch_done "$DONE_TAG"
  fi
}

