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


set -o errexit
set -o xtrace

SPEC_PATH="$1"
SPECIAL_ACTION="$2"


# load _mz.conf
if [ -f "$MZ_CONFIG" ]; then
  source $MZ_CONFIG
elif [ -f "$(pwd)/_mz.conf" ]; then
  MZ_CONFIG=$(pwd)/_mz.conf
  source $MZ_CONFIG
elif [ -f "$(pwd)/ensembl-production-metazoa-private/conf/_mz.conf" ]; then
  MZ_CONFIG="$(pwd)/ensembl-production-metazoa-private/conf/_mz.conf"
  source $MZ_CONFIG
fi

# ENS_VERSION and MZ_RELEASE number
if [ -z "$MZ_RELEASE" ]; then
  MZ_RELEASE=51
fi 
if [ -z "$ENS_VERSION" ]; then
  ENS_VERSION=104
fi

# TODO: create a param or a config to load user scpecific options from
if [ -z "$SCRIPTS" ]; then
  SCRIPTS="$(pwd)"
fi
if [ -z "$WD" ]; then
  WD="$(pwd)"/data
fi
mkdir -p "$WD"

# db server alias
if [ -z "$CMD" ]; then 
  echo 'no db server alias "$CMD" is provided' > /dev/stderr
  exit 1
fi
if [ -z "$CMD_W" ]; then 
  CMD_W="${CMD}-w"
fi

# should we create a local copy of _mz.conf and fill / update it?



MZ_SCRIPTS=${SCRIPTS}/ensembl-production-metazoa/scripts

source ${MZ_SCRIPTS}/lib.sh

# picking META_FILE_RAW
SPEC_SHORT="$(basename ${SPEC_PATH})"

spec_dir="$(dirname ${SPEC_PATH})"
abs_dir="$(dirname $(realpath ${SPEC_PATH}))"

if [ "$spec_dir" = "$abs_dir" ]; then
  META_FILE_RAW=${SPEC_PATH}  
else # relative paths
  if [ "$spec_dir" = "." ]; then
    META_FILE_RAW=$MZ_SCRIPTS/../meta/$ENS_VERSION/$SPEC_SHORT
  else # use current dir as base
    META_FILE_RAW=$(pwd)/$SPEC_PATH
  fi
fi


# prepare / source ensembl.prod.${ENS_VERSION}
#   ${SCRIPTS}/ensembl.prod.${ENS_VERSION}

flock ${SCRIPTS}/ensembl.prod.${ENS_VERSION}.lock -c " 
  source ${MZ_SCRIPTS}/lib.sh;
  get_ensembl_prod ${SCRIPTS}/ensembl.prod.${ENS_VERSION} $ENS_VERSION \
    $MZ_SCRIPTS/checkout_ensembl.20210208.sh $MZ_SCRIPTS/legacy/create_setup_script.sh
  "
# or copy


source ${SCRIPTS}/ensembl.prod.${ENS_VERSION}/setup.sh
export PROD_DB_SCRIPTS=${ENSEMBL_ROOT_DIR}/ensembl.prod.${ENS_VERSION}uction/scripts/production_database
echo 'ENSEMBL_ROOT_DIR='"${ENSEMBL_ROOT_DIR}" > /dev/stderr


# prepared data dir
export DATA_DIR=$WD/$SPEC_SHORT
populate_dirs $DATA_DIR

export DONE_TAGS_DIR=$DATA_DIR/done
export PIPELINE_OUT_DIR=$DATA_DIR/data/pipeline_out

echo DATA_DIR="'${DATA_DIR}'" > /dev/stderr


# get data
ASM_URL=$(get_meta_conf $META_FILE_RAW ASM_URL)
get_asm_ftp "$ASM_URL"  "$DATA_DIR/data/raw"
export ASM_DIR=$DATA_DIR/data/raw/asm

# get adhoc data
get_individual_files_to_asm $ASM_DIR $META_FILE_RAW

# run data preprocessing commands (DATA_INIT meta tag)
run_data_init $META_FILE_RAW $ASM_DIR

# get metadata from gbff
prepare_metada $META_FILE_RAW $ASM_DIR $ENSEMBL_ROOT_DIR $DATA_DIR/metadata
export META_FILE=$DATA_DIR/metadata/meta


STOP_AFTER_CONF=${STOP_AFTER_CONF}
if [ -z "${STOP_AFTER_CONF}" ]; then
  STOP_AFTER_CONF=$(get_meta_conf $META_FILE_RAW 'STOP_AFTER_CONF')
fi
if [ -n "${STOP_AFTER_CONF}" -a "x${STOP_AFTER_CONF}" != "xNO" ]; then
  echo 'stopping after config generation (STOP_AFTER_CONF). see stats...' > /dev/stderr
  exit 0
  false
fi


# load using new-genome-loader
run_new_loader $CMD_W $MZ_RELEASE $DATA_DIR/metadata $ENSEMBL_ROOT_DIR \
  $DATA_DIR/data/pipeline_out/new_load nopfx2

DBNAME=$(find $DATA_DIR/data/pipeline_out/new_load/*_core_* -maxdepth 0 -type d | grep -F _core_ | head -n 1 | perl -pe 's,^.*/,,')

SPECIES=$(get_meta_str $META_FILE "species.production_name")
SPECIES_SCI=$(get_meta_str $META_FILE "species.scientific_name")
SPECIES_SCI_=$(echo $SPECIES_SCI | perl -pe 's/[ _]+/_/g')

echo "using DBNAME $DBNAME" > /dev/stderr
echo "using SPECIES $SPECIES" > /dev/stderr
echo "using SPECIES_SCI_ $SPECIES_SCI_" > /dev/stderr

backup_relink $DBNAME $CMD new_loader $DATA_DIR/bup

if [ z"${SPECIAL_ACTION}" = z"restore" ]; then
  # RESTORE / UNCOMMENT TO USE
  echo "!!! RESTORING DB !!!" > /dev/stderr; restore $DBNAME $CMD_W $DATA_DIR/bup; echo ok > /dev/stderr; false; fail
fi


# initial test, uncomment for the first run, if not sure
# TODO: add an option to run, similar tot the STOP_AFTER_CONF
# run_core_stats_new $CMD_W $DBNAME $SPECIES $DATA_DIR/data/pipeline_out/core_stats _initial
# run_dc $CMD_W $DBNAME $ENSEMBL_ROOT_DIR $DATA_DIR/data/pipeline_out/dc _initial
# exit 0


# fill meta
fill_meta $CMD_W $DBNAME $META_FILE $DATA_DIR/data/pipeline_out/fill_meta
backup_relink $DBNAME $CMD with_meta $DATA_DIR/bup


# mark trans_spliced transcripts
TR_TRANS_SPLICED="$(get_meta_conf $META_FILE 'TR_TRANS_SPLICED')"
if [ -n "$TR_TRANS_SPLICED" ]; then
  mark_tr_trans_spliced $CMD_W $DBNAME "$TR_TRANS_SPLICED"
  backup_relink $DBNAME $CMD tr_spliced_marks $DATA_DIR/bup
fi


GFF_FILE=$(get_meta_conf $META_FILE 'GFF_FILE')


# getting data from repbase to upcast species name
REPBASE_SPECIES_NAME="$(get_meta_conf $META_FILE REPBASE_SPECIES_NAME_RAW)"
if [ -z "$REPBASE_SPECIES_NAME" ]; then
  REPBASE_SPECIES_NAME=$(echo "$SPECIES_SCI" | perl -pe 's/[ _]+/_/g')
fi

REPBASE_OUT_DIR=$DATA_DIR/data/pipeline_out/repeat_lib/repbase
get_repbase_lib "$SPECIES_SCI" $CMD $DBNAME $REPBASE_OUT_DIR
REPBASE_FILE_NEW=$REPBASE_OUT_DIR/repbase.lib

DISABLE_REPBASE_NAME_UPCAST=$(get_meta_conf $META_FILE_RAW DISABLE_REPBASE_NAME_UPCAST)
if [ -z "${DISABLE_REPBASE_NAME_UPCAST}" \
     -o "x${DISABLE_REPBASE_NAME_UPCAST}" != "xYES" \
     -o "x${DISABLE_REPBASE_NAME_UPCAST}" != "x1"
   ]; then
  REPBASE_SPECIES_NAME=$(cat $REPBASE_OUT_DIR/_repbase_species_name)
else
  REPBASE_SPECIES_NAME_NEW=$(cat $REPBASE_OUT_DIR/_repbase_species_name)
  if [ "$REPBASE_SPECIES_NAME" != "$REPBASE_SPECIES_NAME_NEW" ]; then
    REPBASE_FILE_NEW=
  fi
fi

# building repeat libraries
REP_LIB="$(get_meta_conf $META_FILE_RAW REP_LIB)"

if [ -z "$REP_LIB" ]; then
  # try to get raw lib
  REP_LIB="$(get_meta_conf $META_FILE_RAW REP_LIB_RAW)"
  if [ -z "$REP_LIB" ]; then
    # repeats harvesting
    construct_repeat_libraries $CMD_W $DBNAME $SPECIES \
      $DATA_DIR/data/pipeline_out/repeat_lib \
      "$(get_meta_conf $META_FILE_RAW REPEAT_MODELER_OPTIONS)"

    REP_LIB="$DATA_DIR/data/pipeline_out/repeat_lib/${SPECIES}.rm.lib"
    # nonref_unset_toplevel $CMD_W $DBNAME
  fi

  # repeats filtering stage
  REPBASE_FILTER="$(get_meta_conf $META_FILE_RAW REPBASE_FILTER)"
  REPBASE_FILE="$(get_meta_conf $META_FILE_RAW REPBASE_FILE)"

  if [ -z "$GFF_FILE" ]; then
    REPBASE_FILTER='NO'
  fi

  # get RepBase from repeat masker if nothing specified
  if [ -z "$REPBASE_FILTER" -o "x$REPBASE_FILTER" != "xNO" ]; then
    if [ -z "$REPBASE_FILE" ]; then
      REPBASE_FILE="$REPBASE_FILE_NEW"
    fi

    if [ -n "$REPBASE_FILE" -a -f "$REPBASE_FILE" ]; then
      # dump transctipts and translations
      DUMP_TR_DIR=$DATA_DIR/data/pipeline_out/repeat_lib/tr_tr
      dump_translations $CMD $DBNAME $DUMP_TR_DIR \
        ${SCRIPTS}/ensembl.prod.${ENS_VERSION}

      RM_CLEAN_RNA_FILE=${DUMP_TR_DIR}/tr.fna
      RM_CLEAN_PEP_FILE=${DUMP_TR_DIR}/pep.faa

      rm_clean_peps=$(grep -c '>' $RM_CLEAN_PEP_FILE)
      if [ "$rm_clean_peps" -gt "0" ]; then
        filter_repeat_library $REP_LIB \
          $REPBASE_FILE \
          $RM_CLEAN_PEP_FILE \
          $RM_CLEAN_RNA_FILE \
          "${SPECIES}.rm.filtered" \
          $DATA_DIR/data/pipeline_out/repeat_lib/filter

        REP_LIB="$DATA_DIR/data/pipeline_out/repeat_lib/filter/${SPECIES}.rm.filtered"
      fi # rm_clean_peps
    fi # -n REPBASE_FILE

  fi # REPBASE_FILTER != NO
fi # -z REPLIB

# checkin rep lib size
if [ -n "$REP_LIB" -a "x$REP_LIB" != "xNO" ]; then
  rep_lib_size=$(grep -c '>' $REP_LIB)

  if [ "$rep_lib_size" -lt "1" ]; then
    echo "empty repeat library ${REP_LIB}" > /dev/stderr
    IGNORE_EMPTY_REP_LIB=$(get_meta_conf $META_FILE_RAW IGNORE_EMPTY_REP_LIB)
    if [ -n "$IGNORE_EMPTY_REP_LIB" ]; then
      REP_LIB="NO"
      echo "  ignoring. (IGNORE_EMPTY_REP_LIB=${IGNORE_EMPTY_REP_LIB})" > /dev/stderr
    else
      echo "  failing. set IGNORE_EMPTY_REP_LIB=1 to ignore" > /dev/stderr
      fail
    fi
  fi
fi

# repeat masking
run_repeat_masking $CMD_W $DBNAME $SPECIES "$REP_LIB" $DATA_DIR/data/pipeline_out/dna_features "$REPBASE_SPECIES_NAME"
# nonref_unset_toplevel $CMD_W $DBNAME
backup_relink $DBNAME $CMD repeat_masking $DATA_DIR/bup


if [ -n "$GFF_FILE" ]; then

  # RNA features
  run_rna_features $CMD_W $DBNAME $SPECIES $ENSEMBL_ROOT_DIR \
    $DATA_DIR/data/pipeline_out/rna_features '_opt' "$(get_meta_conf $META_FILE_RAW RNA_FEAT_PARAMS)"
  backup_relink $DBNAME $CMD rna_features $DATA_DIR/bup

  # RNA genes
  RUN_RNA_GENES=$(get_meta_conf $META_FILE_RAW RUN_RNA_GENES)
  if [ -z "$RUN_RNA_GENES" -o "x$RUN_RNA_GENES" != "xNO" ]; then
    run_rna_genes $CMD_W $DBNAME $SPECIES $ENSEMBL_ROOT_DIR \
      $DATA_DIR/data/pipeline_out/rna_features '_opt' "$(get_meta_conf $META_FILE_RAW RNA_GENE_PARAMS)"
    backup_relink $DBNAME $CMD rna_genes $DATA_DIR/bup
  fi


  # run xref pipelines
  run_xref $CMD_W $DBNAME $SPECIES $ENSEMBL_ROOT_DIR $DATA_DIR/data/pipeline_out/xrefs/all "$(get_meta_conf $META_FILE_RAW XREF_PARAMS)"
  backup_relink $DBNAME $CMD run_xref $DATA_DIR/bup


  # fix gene and transcript stable ids, update xrefs name
  UPDATE_STABLE_IDS="$(get_meta_conf $META_FILE_RAW 'UPDATE_STABLE_IDS')"
  UPDATE_STABLE_IDS_OPTIONS="$(get_meta_conf $META_FILE_RAW 'UPDATE_STABLE_IDS_OPTIONS')"
  if [ -n "$UPDATE_STABLE_IDS" -a "x$UPDATE_STABLE_IDS" != "xNO" ]; then
    PREV_XREF_FILE="$DATA_DIR/data/pipeline_out/xrefs/all/prev_xrefs/${DBNAME}.ids_xref.txt"
    update_stable_ids $CMD_W $DBNAME $PREV_XREF_FILE "${UPDATE_STABLE_IDS_OPTIONS}" $ENSEMBL_ROOT_DIR $DATA_DIR/data/pipeline_out/update_stable_ids
    backup_relink $DBNAME $CMD update_stable_ids $DATA_DIR/bup
  fi


  # description projection
  # we can project descriptions only if we have compara data -- thus skipping


  if [ -z "$(get_meta_str $META_FILE 'sample.location_param')" ]; then
    SAMPLE_GENE="$(get_meta_conf $META_FILE 'SAMPLE_GENE')"
    set_core_random_samples $CMD_W $DBNAME "$SAMPLE_GENE" $ENSEMBL_ROOT_DIR
    backup_relink $DBNAME $CMD random_samples $DATA_DIR/bup
  fi

fi # "GFF_FILE"


# core stats
run_core_stats_new $CMD_W $DBNAME $SPECIES $DATA_DIR/data/pipeline_out/core_stats
backup_relink $DBNAME $CMD core_stats $DATA_DIR/bup

# run_dc $CMD_W $DBNAME $ENSEMBL_ROOT_DIR $DATA_DIR/data/pipeline_out/dc _pre_prod_sync

update_prod_tables_new $CMD_W $DBNAME $SPECIES $DATA_DIR/data/pipeline_out/update_prod_tables

backup_relink $DBNAME $CMD prodsync_new $DATA_DIR/bup

if [ z"${SPECIAL_ACTION}" = z"pre_final_dc" ]; then
  run_dc $CMD_W $DBNAME $ENSEMBL_ROOT_DIR $DATA_DIR/data/pipeline_out/dc _pre_final
fi

if [ z"${SPECIAL_ACTION}" = z"finalise" ]; then
  backup_relink $DBNAME $CMD final $DATA_DIR/bup
  echo done > /dev/stderr
fi

if [ z"${SPECIAL_ACTION}" = z"patch_schema" ]; then
  echo running additional steps. not backing them  up > /dev/stderr
  patch_db_schema $CMD_W $DBNAME \
    $ENSEMBL_ROOT_DIR $DATA_DIR/data/pipeline_out/patch_schema

  backup_relink $DBNAME $CMD patched_shema $DATA_DIR/bup
  echo schema patched > /dev/stderr
fi

# additioanal staff
exit 0

# use conf instead???
# exit 0

# add metakey
DBNAME_FIN=$DBNAME

update_prod_tables_new $CMD_W $DBNAME_FIN $SPECIES \
  $DATA_DIR/data/pipeline_out/update_prod_tables_fin _fin

run_dc $CMD_W $DBNAME_FIN \
  $ENSEMBL_ROOT_DIR $DATA_DIR/data/pipeline_out/dc _fin

echo done additional > /dev/stderr

