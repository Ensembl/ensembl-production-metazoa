#!/usr/bin/bash

## set and ENS_VERSION and MZ_RELEASE number
ENS_VERSION= # e.g 111
MZ_RELEASE= # e.g 58
MAIN_BASE_DIR= #Work dir, location of base working space for loading
SLURM_BATCH_TEMPLATE= #Template containing sbatch params used to construct `sptags_batch_#' Slurm submission batch file

if [[ -z $ENS_VERSION ]] | [[ -z $MZ_RELEASE ]] | [[ -z $MAIN_BASE_DIR ]] | [[ -z $SLURM_BATCH_TEMPLATE ]]; then

    echo "Ensure following vars are defined: ENS_VERSION, MZ_RELEASE, MAIN_BASE_DIR, SLURM_BATCH_TEMPLATE"
    exit
fi

## default server aliases
CMD=me1 #Mysql host in which loaded cores are stored
PROD_SERVER=meta1
QUEUE=production

## LSF Legacy stuff:
# export PROD_SERVER
# export CMD
# export ENS_VERSION
# export MZ_RELEASE
# LSF_QUEUE=production # LSF queue which runs loading/production pipelines

## TMUX session connections
# TMUX CREATE:
# tmux -S /tmp/${USER}_e${ENS_VERSION}_load new -s ${USER}_e${ENS_VERSION}_load
# TMUX ATTACH:
# tmux -S /tmp/${USER}_e${ENS_VERSION}_load att -t ${USER}_e${ENS_VERSION}_load

## How to set up the main production environment.
# ${ENS_MAIN_METAZOA_PROD}/scripts/mz_generic.sh env_setup_only

## Set up of ensembl-production-metazoa production repo
cd $MAIN_BASE_DIR; mkdir -p workdir tmp logs data locks

# Requires https://github.com/Ensembl/ensembl-production-metazoa
# git clone --depth 1 -b main git@github.com:Ensembl/ensembl-production-metazoa.git
ENS_MAIN_METAZOA_PROD=${MAIN_BASE_DIR}/ensembl-production-metazoa
METACONF_DIR=$ENS_MAIN_METAZOA_PROD/meta/2024-01.release_XXX  #Space in which meta files are stored for a given release.
mkdir -p $METACONF_DIR

# echo tmp workdir | xargs -n 1 | xargs -n 1 -I XXX sh -c 'mv XXX XXX.old; mkdir -p XXX; rm -rf XXX.old;'
# SPECIES_TO_LOAD_META=_refseq_e${ENS_VERSION}.list # This list is prepared by hand using input from curated spreadsheet (e.g. https://github.com/Ensembl/ensembl-production-metazoa/blob/main/meta/107_for_109/_refseq_109.lst)
# python3 ${ENS_MAIN_METAZOA_PROD}/scripts/tmpl2meta.py --template ${ENS_MAIN_METAZOA_PROD}/meta/refseq.tmpl --param_table $METACONF_DIR/_refseq_e${ENS_VERSION}.list --output_dir $METACONF_DIR --out_file_pfx rs8t_

### Processing meta_conf to generate batches of species to load (Batch file prefix: sptags_batch_#)
# BATCH_SIZE=4 # Number of species to load in one batch submission
# ls -1 $METACONF_DIR/rs8t_* | \
# perl -pe 's,.*/,,' | \
# xargs -n 1 echo | split --numeric-suffixes=1 -l $BATCH_SIZE - sptags_batch_

### Genome Loading and Processing starts from here:

## Uncomment lines as needed
BATCH_NO="BATCH_1_ROUND1"
# BATCH_NO="BATCH_2_ROUND1"
# BATCH_NO="BATCH_3_ROUND1"
# BATCH_NO="BATCH_4_ROUND1"
# BATCH_NO="BATCH_5_ROUND1"
# BATCH_NO="CUSTOM"

## Species batch number 1:
if [ "$BATCH_NO" == "BATCH_1_ROUND1" ]; then

BATCH_FILE=sptags_batch_01
MODE="stop_after_load" # SEE (https://github.com/Ensembl/ensembl-production-metazoa/blob/main/docs/mz_generic_params.md)
SLEEP=7200 #Time to wait between genome load, useful to not throttle cluster when loading large genomes with very long chromosomes.

while read TAG
do
  echo "Preparing ${TAG}_slurm_batch.sh ..."
  cat $SLURM_BATCH_TEMPLATE > ${TAG}_slurm_batch.sh
  echo -e -n "ENS_VERSION=$ENS_VERSION\nPROD_SERVER=$PROD_SERVER\nCMD=$CMD\nMZ_RELEASE=$MZ_RELEASE\n" >> ${TAG}_slurm_batch.sh
  echo -e -n "\nexport ENS_VERSION\nexport PROD_SERVER\nexport CMD\nexport MZ_RELEASE\n\n" >> ${TAG}_slurm_batch.sh
  echo -e -n "flock -n locks/$TAG ${ENS_MAIN_METAZOA_PROD}/scripts/mz_generic.sh ${METACONF_DIR}/$TAG $MODE;\n" >> ${TAG}_slurm_batch.sh
  sed -i s/XXX/${TAG}/g ${TAG}_slurm_batch.sh
  sbatch ${TAG}_slurm_batch.sh | tee logs/${TAG}.sbatch_ID
  echo "Submitted $TAG. Now sleeping for [${SLEEP}] seconds ..."
  sleep $SLEEP
done < ${MAIN_BASE_DIR}/${BATCH_FILE}

fi

## Species batch number 2:
if [ "$BATCH_NO" == "BATCH_2_ROUND1" ]; then

cat sptags_batch_02 |

BATCH_FILE=sptags_batch_02
MODE="stop_after_load"
SLEEP=7200

while read TAG
do
  echo "Preparing ${TAG}_slurm_batch.sh ..."
  cat $SLURM_BATCH_TEMPLATE > ${TAG}_slurm_batch.sh
  echo -e -n "ENS_VERSION=$ENS_VERSION\nPROD_SERVER=$PROD_SERVER\nCMD=$CMD\nMZ_RELEASE=$MZ_RELEASE\n" >> ${TAG}_slurm_batch.sh
  echo -e -n "\nexport ENS_VERSION\nexport PROD_SERVER\nexport CMD\nexport MZ_RELEASE\n\n" >> ${TAG}_slurm_batch.sh
  echo -e -n "flock -n locks/$TAG ${ENS_MAIN_METAZOA_PROD}/scripts/mz_generic.sh ${METACONF_DIR}/$TAG $MODE;\n" >> ${TAG}_slurm_batch.sh
  sed -i s/XXX/${TAG}/g ${TAG}_slurm_batch.sh
  sbatch ${TAG}_slurm_batch.sh | tee logs/${TAG}.sbatch_ID
  echo "Submitted $TAG. Now sleeping for [${SLEEP}] seconds ..."
  sleep $SLEEP
done < ${MAIN_BASE_DIR}/${BATCH_FILE}

fi

## Species batch number 3:
if [ "$BATCH_NO" == "BATCH_3_ROUND1" ]; then

BATCH_FILE=sptags_batch_03
MODE="stop_after_load"
SLEEP=7200

while read TAG
do
  echo "Preparing ${TAG}_slurm_batch.sh ..."
  cat $SLURM_BATCH_TEMPLATE > ${TAG}_slurm_batch.sh
  echo -e -n "ENS_VERSION=$ENS_VERSION\nPROD_SERVER=$PROD_SERVER\nCMD=$CMD\nMZ_RELEASE=$MZ_RELEASE\n" >> ${TAG}_slurm_batch.sh
  echo -e -n "\nexport ENS_VERSION\nexport PROD_SERVER\nexport CMD\nexport MZ_RELEASE\n\n" >> ${TAG}_slurm_batch.sh
  echo -e -n "flock -n locks/$TAG ${ENS_MAIN_METAZOA_PROD}/scripts/mz_generic.sh ${METACONF_DIR}/$TAG $MODE;\n" >> ${TAG}_slurm_batch.sh
  sed -i s/XXX/${TAG}/g ${TAG}_slurm_batch.sh
  sbatch ${TAG}_slurm_batch.sh | tee logs/${TAG}.sbatch_ID
  echo "Submitted $TAG. Now sleeping for [${SLEEP}] seconds ..."
  sleep $SLEEP
done < ${MAIN_BASE_DIR}/${BATCH_FILE}

fi

## Species batch number 4:
if [ "$BATCH_NO" == "BATCH_4_ROUND1" ]; then

BATCH_FILE=sptags_batch_04
MODE="stop_after_load"
SLEEP=7200

while read TAG
do
  echo "Preparing ${TAG}_slurm_batch.sh ..."
  cat $SLURM_BATCH_TEMPLATE > ${TAG}_slurm_batch.sh
  echo -e -n "ENS_VERSION=$ENS_VERSION\nPROD_SERVER=$PROD_SERVER\nCMD=$CMD\nMZ_RELEASE=$MZ_RELEASE\n" >> ${TAG}_slurm_batch.sh
  echo -e -n "\nexport ENS_VERSION\nexport PROD_SERVER\nexport CMD\nexport MZ_RELEASE\n\n" >> ${TAG}_slurm_batch.sh
  echo -e -n "flock -n locks/$TAG ${ENS_MAIN_METAZOA_PROD}/scripts/mz_generic.sh ${METACONF_DIR}/$TAG $MODE;\n" >> ${TAG}_slurm_batch.sh
  sed -i s/XXX/${TAG}/g ${TAG}_slurm_batch.sh
  sbatch ${TAG}_slurm_batch.sh | tee logs/${TAG}.sbatch_ID
  echo "Submitted $TAG. Now sleeping for [${SLEEP}] seconds ..."
  sleep $SLEEP
done < ${MAIN_BASE_DIR}/${BATCH_FILE}

fi

## Species batch number 5:
if [ "$BATCH_NO" == "BATCH_5_ROUND1" ]; then

BATCH_FILE=sptags_batch_05
MODE="stop_after_load"
SLEEP=7200

while read TAG
do
  echo "Preparing ${TAG}_slurm_batch.sh ..."
  cat $SLURM_BATCH_TEMPLATE > ${TAG}_slurm_batch.sh
  echo -e -n "ENS_VERSION=$ENS_VERSION\nPROD_SERVER=$PROD_SERVER\nCMD=$CMD\nMZ_RELEASE=$MZ_RELEASE\n" >> ${TAG}_slurm_batch.sh
  echo -e -n "\nexport ENS_VERSION\nexport PROD_SERVER\nexport CMD\nexport MZ_RELEASE\n\n" >> ${TAG}_slurm_batch.sh
  echo -e -n "flock -n locks/$TAG ${ENS_MAIN_METAZOA_PROD}/scripts/mz_generic.sh ${METACONF_DIR}/$TAG $MODE;\n" >> ${TAG}_slurm_batch.sh
  sed -i s/XXX/${TAG}/g ${TAG}_slurm_batch.sh
  sbatch ${TAG}_slurm_batch.sh | tee logs/${TAG}.sbatch_ID
  echo "Submitted $TAG. Now sleeping for [${SLEEP}] seconds ..."
  sleep $SLEEP
done < ${MAIN_BASE_DIR}/${BATCH_FILE}

fi

## Custom loading section for ad-hoc or odd loading jobs
if [ "$BATCH_NO" == "CUSTOM" ]; then

BATCH_FILE=sptags_batch_custom
MODE="stop_after_load"
SLEEP=7200

while read TAG
do
  echo "Preparing ${TAG}_slurm_batch.sh ..."
  cat $SLURM_BATCH_TEMPLATE > ${TAG}_slurm_batch.sh
  echo -e -n "ENS_VERSION=$ENS_VERSION\nPROD_SERVER=$PROD_SERVER\nCMD=$CMD\nMZ_RELEASE=$MZ_RELEASE\n" >> ${TAG}_slurm_batch.sh
  echo -e -n "\nexport ENS_VERSION\nexport PROD_SERVER\nexport CMD\nexport MZ_RELEASE\n\n" >> ${TAG}_slurm_batch.sh
  echo -e -n "flock -n locks/$TAG ${ENS_MAIN_METAZOA_PROD}/scripts/mz_generic.sh ${METACONF_DIR}/$TAG $MODE;\n" >> ${TAG}_slurm_batch.sh
  sed -i s/XXX/${TAG}/g ${TAG}_slurm_batch.sh
  sbatch ${TAG}_slurm_batch.sh | tee logs/${TAG}.sbatch_ID
  echo "Submitted $TAG. Now sleeping for [${SLEEP}] seconds ..."
  sleep $SLEEP
done < ${MAIN_BASE_DIR}/${BATCH_FILE}

fi
