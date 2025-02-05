#!/usr/bin/bash
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

####################
### Create ensembl-mod-env for genome load production processing:
# Step1: get latest updates to ensembl-mod-env repo ! This is critical to ensure proper functionality. 
# Step2: Select appropriate python version, this e.g. use relatively latest python version v3.11.7
  # - module load python/3.11.7
# Step3: Create production environment, using load_genome.conf (https://github.com/Ensembl/ensembl-mod-env/blob/main/confs/ensembl/load_genome.yml)
# whilst selecting the base branch to be the same as the ensembl schema version for the core creation [ENS_VERSION]
  # - E.g. modenv_create -b 114 ensembl/load_genome e114_genomeload
## Load module env, you will need to do this manually outside of this wrapper
  # -E.g.  module load ensembl/e114_genomeload
## Load module env for hive, you will need to do this manually outside of this wrapper
  # -E.g.  module load hive/2.7.0
####################

## set ENS_VERSION
if [[ $ENSEMBL_VERSION ]]; then
  ENS_VERSION=$ENSEMBL_VERSION
  echo "ENSEMBL VERSION detected: '$ENS_VERSION'"
else
  # e.g 111 i.e. the ensembl schema version to use for loading
  ENS_VERSION=
  if [[ -z $ENS_VERSION ]]; then
    echo "Please define the ENSEMBL VERSION: ENS_VERSION, See $0 (line: 35)"
    exit 0
  fi
fi

##### How to set up the main production environment.
# METHOD A: Setup when using ensembl-mod-env for production
# If using mod-env you must ensure the environment variable MODENV_ROOT is defined !
if [[ $MODENV_ROOT ]] && [[ $MODENV_HOME ]]; then
  echo "Detecting 'ensembl-mod-env' production environment setup...."
  
  PRODUCTION_MODENV_NAME="" #< E.G. NOTE: Ensure MODENV_DIR DOESN'T END WITH: "/"

  if [[ $PRODUCTION_MODENV_NAME ]]; then
    MODENV_DIR="${MODENV_HOME}/${PRODUCTION_MODENV_NAME}" ## MODENV_ROOT must be defined and should be if ensembl-mod-env is correctly setup for $USER
    echo "Using modenv setup ?.... if so its configured to this path: '$MODENV_DIR'"
    ENS_MAIN_METAZOA_PROD=${MODENV_DIR}/ensembl-production-metazoa
    ln -s $ENS_MAIN_METAZOA_PROD ./ensembl-production-metazoa
    ln -s $MODENV_DIR ./ensembl.prod.${ENS_VERSION}
    echo "'venv' path ->: '${VENV_ROOT}/${PRODUCTION_MODENV_NAME}/bin'"
    echo "'modenv' created module repos ->: '$MODENV_DIR'"
  else
    echo "Named ensembl-mod-env module not defined 'PRODUCTION_MODENV_NAME' ! See $0 (line: 47)"
    exit 0
  fi # < PRODUCTION_MODENV_NAME

# METHOD B: Setup when using 'mz_generic.sh env_setup_only'
elif [[ -d "${PWD}/ensembl.prod.${ENS_VERSION}" ]]; then
  echo "Attempting to detect standard 'ensembl.prod.${ENS_VERSION}' non-module-env production environment setup"
  STANDARD_REPO_SETUP="$PWD/ensembl.prod.${ENS_VERSION}"
  ENS_MAIN_METAZOA_PROD="$PWD/ensembl.prod.${ENS_VERSION}/ensembl-production-metazoa"
  echo "'venv' path ->: '${STANDARD_REPO_SETUP}/venv/bin'"
  echo "'standard setup' repos ->: '$STANDARD_REPO_SETUP'"
else
  echo "Unable to resolve production environment setup to standard ensembl.prod OR ensembl-mod-env !"
  echo "Standard setup procedure:"
  echo "git clone --depth 1 -b main git@github.com:Ensembl/ensembl-production-metazoa.git"
  echo "ensembl-production-metazoa/scripts/mz_generic.sh env_setup_only"
  exit 1
fi # <[[ $MODENV_ROOT ]] && [[ $MODENV_HOME ]]

## set basic requirement env setup vars
PROD_CYCLE_ENS_VERSION=$(( ${ENS_VERSION} + 1 )) # The production release version for which we are running genome loading.
MZ_RELEASE=$(( ${ENS_VERSION} - 53 ))
WORK_DIR=${PWD} #Path to base work directory space for running genome load

#Template containing sbatch params used to construct `sptags_batch_#' Slurm submission batch file
SLURM_BATCH_TEMPLATE="${ENS_MAIN_METAZOA_PROD}/scripts/_template_slurm_jobscript.batch"

if [[ ! -e $SLURM_BATCH_TEMPLATE ]]; then
    echo "Could not find slurm batch submission template (SLURM_BATCH_TEMPLATE) here: $SLURM_BATCH_TEMPLATE"
    exit 0
else
  echo "Using slurm batch tempalte: $SLURM_BATCH_TEMPLATE"
fi

## Host setup, dbs and SLURM queue config
CMD= #Mysql host in which new core DBs will be created and stored (e.g: me1, me2, pl1, pl2)
PROD_SERVER= # Host containing production 'ensembl_production' db
QUEUE=production # QUEUE/PARTITION FOR SLURM SCHEDULER:
if [[ -z $CMD ]] || [[ -z $PROD_SERVER ]] || [[ -z $QUEUE ]]; then
    echo "Ensure following environment vars are defined: CMD, PROD_SERVER, QUEUE"
    exit 0
fi

## WHAT ORGANISM DIVISION ARE YOU LOADING ?
LOAD_DIVISION=
# Check an appropriate division was supplied by user
if [[ -z $LOAD_DIVISION ]]; then
	echo "Organism division not defined. Please define on $0 (line: 100)"
  exit
elif [[ "$LOAD_DIVISION" != "metazoa" ]] && [[ "$LOAD_DIVISION" != "plants" ]]; then
	echo -e -n "Division supplied ('$LOAD_DIVISION') not recognised. Must be defined as: [ metazoa | plants ]\n\n"
	exit 1
else
  echo "Division defined -> '$LOAD_DIVISION'"
fi

## Set up of ensembl-production-metazoa production repo
cd $WORK_DIR; mkdir -p workdir tmp logs data locks

# Requires https://github.com/Ensembl/ensembl-production-metazoa
CONF_DIR_DATE=`date -I`
# If specific loading meta configuration folder already exists with config files generated...define it on next line:
# METACONF_DIR=""
# Or we attempt to build it from other configs defined:
METACONF_DIR=$ENS_MAIN_METAZOA_PROD/meta/${CONF_DIR_DATE}.${ENS_VERSION}_for_${PROD_CYCLE_ENS_VERSION}  #Space in which meta files are stored for a given release.
# Create METACONF_DIR if it doesn't already exist
if [[ ! -d "$METACONF_DIR" ]]; then
    # mkdir -p $METACONF_DIR
    echo "Could not set METACONF_DIR. Path doesn't exist -> '$ENS_MAIN_METAZOA_PROD/meta/${CONF_DIR_DATE}.${ENS_VERSION}_for_${PROD_CYCLE_ENS_VERSION}'"
    echo "You will need to manually create this conf dir and loading meta config files, see $0 (line: 128)"

    # ## If no config files exist for your release loading, create them:
    # echo tmp workdir | xargs -n 1 | xargs -n 1 -I XXX sh -c 'mv XXX XXX.old; mkdir -p XXX; rm -rf XXX.old;'
    # SPECIES_TO_LOAD_META=${METACONF_DIR}_refseq_e${ENS_VERSION}.list # This list is prepared by hand using input from curated spreadsheet (e.g. https://github.com/Ensembl/ensembl-production-metazoa/blob/main/meta/2025-01-15.114_for_115/_refseq_e115.list)
    # CONFIG_DIVISION="${LOAD_DIVISION}.tmpl" # E.G. https://github.com/Ensembl/ensembl-production-metazoa/blob/main/meta/metazoa.tmpl
    # CONFIG_TEMPLATE=${ENS_MAIN_METAZOA_PROD}/meta/$CONFIG_DIVISION
    # OUT_PREFIX="rs8t_" # legacy standard, but feel free to use whatever you prefer
    # python ${ENS_MAIN_METAZOA_PROD}/scripts/tmpl2meta.py \
    #   --template $CONFIG_TEMPLATE \
    #   --param_table $SPECIES_TO_LOAD_META \
    #   --output_dir $METACONF_DIR \
    #   --out_file_pfx $OUT_PREFIX
else
  echo "'METACONF_DIR' var defined -> '$METACONF_DIR'"
fi

### Processing meta_conf to generate batches of species to load (Batch file prefix: sptags_batch_#)
# BATCH_SIZE=4 # Number of species to load in one batch submission
# ls -1 $METACONF_DIR/rs8t_* | \
# perl -pe 's,.*/,,' | \
# xargs -n 1 echo | split --numeric-suffixes=1 -l $BATCH_SIZE - sptags_batch_

## TMUX session connections reminder:
# TMUX CREATE:
# tmux -S /tmp/${USER}_e${ENS_VERSION}_load new -s ${USER}_e${ENS_VERSION}_genome_load
# TMUX ATTACH:
# tmux -S /tmp/${USER}_e${ENS_VERSION}_load att -t ${USER}_e${ENS_VERSION}_genome_load

### Genome Loading and Processing starts from here:

## Uncomment lines as needed to run different sptags batches. Only one BATCH_NO should be uncommented at a time
BATCH_NO="BATCH_1_ROUND1"
# BATCH_NO="BATCH_2_ROUND1"
# BATCH_NO="BATCH_3_ROUND1"
# BATCH_NO="BATCH_4_ROUND1"
# BATCH_NO="BATCH_5_ROUND1"
# BATCH_NO=......."
# BATCH_NO=......."
# BATCH_NO=......."
# BATCH_NO="CUSTOM"

### mz_generic params, this will set the level of throughput in genome loading and production pipeline processing:
## SEE (https://github.com/Ensembl/ensembl-production-metazoa/blob/main/docs/mz_generic_params.md)
MZGEN_MODE="stop_after_conf"
# MZGEN_MODE="stop_after_load"
# MZGEN_MODE="stop_before_xref"
# MZGEN_MODE="pre_final_dc"
# MZGEN_MODE="finalise"

## Species batch number 1:
if [ "$BATCH_NO" == "BATCH_1_ROUND1" ]; then

BATCH_FILE=sptags_batch_01
MODE=$MZGEN_MODE
#Time to wait between genome load, useful to not throttle cluster when loading large genomes with very long chromosomes.
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
done < ${WORK_DIR}/${BATCH_FILE}

fi

## Species batch number 2:
if [ "$BATCH_NO" == "BATCH_2_ROUND1" ]; then

BATCH_FILE=sptags_batch_02
MODE=$MZGEN_MODE
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
done < ${WORK_DIR}/${BATCH_FILE}

fi

## Species batch number 3:
if [ "$BATCH_NO" == "BATCH_3_ROUND1" ]; then

BATCH_FILE=sptags_batch_03
MODE=$MZGEN_MODE
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
done < ${WORK_DIR}/${BATCH_FILE}

fi

## Species batch number 4:
if [ "$BATCH_NO" == "BATCH_4_ROUND1" ]; then

BATCH_FILE=sptags_batch_04
MODE=$MZGEN_MODE
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
done < ${WORK_DIR}/${BATCH_FILE}

fi

## Species batch number 5:
if [ "$BATCH_NO" == "BATCH_5_ROUND1" ]; then

BATCH_FILE=sptags_batch_05
MODE=$MZGEN_MODE
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
done < ${WORK_DIR}/${BATCH_FILE}

fi

## Custom loading section for ad-hoc or odd loading jobs
if [ "$BATCH_NO" == "CUSTOM" ]; then

BATCH_FILE=sptags_batch_custom
MODE=$MZGEN_MODE
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
done < ${WORK_DIR}/${BATCH_FILE}

fi
