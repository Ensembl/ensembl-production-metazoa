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

## Obtain from Wikipedia/Annotation summary, annotation and assembly information and produce relevant static content markdown files.

RUN_STAGE=${1^^} # All, Wiki, NCBI, Static, Image, WhatsNew, Tidy
INPUT_DB_LIST=$2 # flat file of core(s) to be processed one per line.
HOST=$3 #MYSQL server hosting the cores listed in $INPUT_DB_LIST.
RELEASE=$4 # Name of final output folder
ENS_DIVISION=$5
CWD=`readlink -f $PWD`

STAGE_LOG="_static_stages_done_${RELEASE}"
OUTPUT_NCBI="$CWD/NCBI_DATASETS"
WIKI_OUTPUT_JSONS="$CWD/WIKI_JSON_OUT"
ENS_PRODUCTION_METAZOA="$ENSEMBL_ROOT_DIR/ensembl-production-metazoa"
DS_SOFTWARE_URL="https://api.github.com/repos/ncbi/datasets/releases/latest"

##Vars for STDOUT colour formatting
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

if [[ -d ${ENS_PRODUCTION_METAZOA} ]]; then
	STATIC_BASE_DIR="${ENS_PRODUCTION_METAZOA}/scripts/static_content_generation"
elif [[ -d ${CWD}/ensembl-production-metazoa ]]; then
	STATIC_BASE_DIR="${CWD}/ensembl-production-metazoa/scripts/static_content_generation"
	ENS_PRODUCTION_METAZOA="${CWD}/ensembl-production-metazoa"
else
	echo "Can not detect required repository 'ensembl-production-metazoa' in CWD. Attemtping to download now..."
	sleep 3
	git clone -b main --depth 1 git@github.com:Ensembl/ensembl-production-metazoa.git ${CWD}/ensembl-production-metazoa
	STATIC_BASE_DIR="${CWD}/ensembl-production-metazoa/scripts/static_content_generation"
	ENS_PRODUCTION_METAZOA="${CWD}/ensembl-production-metazoa"
fi

if [[ $RUN_STAGE == TEMPLATE ]]; then

		# ### Generate blank files for species not linked with GCF_
		read -p "Generating blank MD files. Enter species.production_name : " PROD_NAME_USER
		read -p "Generating blank MD files. Enter the appropriate Division (e.g. metazoa, plants, protists etc) : " ENS_DIVISION
		PROD_NAME=`echo $PROD_NAME_USER | sed 's/ /_/g'`
		TEMPLATE_OUTDIR="${CWD}/${PROD_NAME^}"
		mkdir -p $TEMPLATE_OUTDIR

		if [[ -d $ENS_PRODUCTION_METAZOA ]]; then

			for EXTENSION in _about.md _annotation.md _assembly.md _references.md
			do
			cat $ENS_PRODUCTION_METAZOA/scripts/static_content_generation/template${EXTENSION} | sed s/TEMP_DIVISION/$ENS_DIVISION/g > $CWD/${PROD_NAME^}${EXTENSION};
			done
			mv $CWD/${PROD_NAME^}*.md $TEMPLATE_OUTDIR
			echo -e -n "Generated generic template Markdown files -> $TEMPLATE_OUTDIR.\nContents:\t[${PROD_NAME^}_about.md, ${PROD_NAME^}_annotation.md, ${PROD_NAME^}_assembly.md, ${PROD_NAME^}_references.md]\n"
			echo -e -n "${ORANGE}!!! Please amend these files to fill in the missing values !${NC}\n"
			exit 0
		fi

fi

if [[ -z $INPUT_DB_LIST ]] || [[ -z $HOST ]] || [[ -z $RELEASE ]] || [[ -z $STATIC_BASE_DIR ]] || [[ -z $ENS_DIVISION ]]; then
	echo "Usage: sh CoreList_To_StaticContent.sh Template"
	echo -e -n "\tOR\n"
	echo "Usage: sh CoreList_To_StaticContent.sh <RunStage: All, Wiki, NCBI, Static, Image, LicenseUsage, WhatsNew, Tidy> <INPUT_DB_LIST> <MYSQL_HOST_SERVER> <Unique_Run_Identifier> <Ensembl divsision>"
	exit 1
fi

# Repeat check of stage specific processing and exit or continue pipeline accordingly
function check_exit_status(){
	local EXIT_STATUS=$1
	local CUR_STAGE=$2
	local NEXT_STAGE=$3

	if [[ $EXIT_STATUS == 0 ]]; then
		echo -e -n "${GREEN}Stage: '${CUR_STAGE^}' has finished fully [exit code=$EXIT_STATUS], moving on to $NEXT_STAGE...${NC}\n\n"
		echo "$CUR_STAGE" >> $CWD/$STAGE_LOG
		RUN_STAGE=$NEXT_STAGE
	else
		echo -e -n "${RED}Stage: $CUR_STAGE failed on exit status == '$EXIT_STATUS'. Exiting main processing wrapper.${NC}\n\n"
		exit 1
	fi
}

## Check if SINGULARITY cache dir ENV variable is defined
if [[ ! $NXF_SINGULARITY_CACHEDIR ]]; then
	echo "Required singularity ENV variable 'NXF_SINGULARITY_CACHEDIR' is not defined."
	echo "Please set this variable to a path you wish to store singularity SIF image files.!"
	exit 1
else
	#DATASETS_RELEASE=`curl -s $DS_SOFTWARE_URL | grep browser_download_url | cut -d \" -f4 | grep linux-amd64.cli.package.zip | cut -d "/" -f 8`
	DATASETS_RELEASE="latest"
	DATASETS_DOCKER_BASE_URL="docker://ensemblorg/datasets-cli"

	SIF_IMAGE_W_VERSION="datasets-cli.${DATASETS_RELEASE}.sif"
	SIF_IMAGE_LATEST="datasets-cli.latest.sif"
	DATASETS_DOCKER_LATEST_URL="${DATASETS_DOCKER_BASE_URL}:latest"
	DATASETS_DOCKER_VERSION_URL="${DATASETS_DOCKER_BASE_URL}:${DATASETS_RELEASE}"

	DATASETS_SINGULARITY="${NXF_SINGULARITY_CACHEDIR}/${SIF_IMAGE_W_VERSION}"
	DATASETS_SINGULARITY_LATEST="${NXF_SINGULARITY_CACHEDIR}/${SIF_IMAGE_LATEST}"
fi

## First main stage, obtained wikipedia JSON scrape for each species
if [[ -f $CWD/$STAGE_LOG ]]; then
	STAGE=`grep -e "wikipedia" $CWD/$STAGE_LOG`
	if [[ $STAGE ]];then
		echo "## Wikipedia REST stage Already Done! Moving to NCBI datasets download."
		RUN_STAGE="NCBI"
	fi
fi

if [[ $RUN_STAGE == "ALL" ]] || [[ $RUN_STAGE == "WIKI" ]]; then


	mkdir -p $WIKI_OUTPUT_JSONS
	HOST_NAME=`echo $($HOST details script) | awk {'print $2'}`

	#Make sure to remove any old generate_Wiki_JSON_Summary.sh 
	if [[ -e ./generate_Wiki_JSON_Summary.sh ]]; then
		echo "Deleting old generate_Wiki_JSON_Summary.sh"
		rm ./generate_Wiki_JSON_Summary.sh
	fi

	check_wikipedia_content () {

		local CORE=$1
		local LOCAL_DIR=$2
		local WIKI_DIR=$3
		local LINNEAN_NAME=$4
		local FALL_BACK_NAME=$5

		if [[ -s ${CORE}.spname.wiki.json ]] && [[ -s ${CORE}.commonname.wiki.json ]]; then
			mv $LOCAL_DIR/${CORE}.spname.wiki.json $WIKI_DIR/${CORE}.wiki.json
			rm $LOCAL_DIR/${CORE}.commonname.wiki.json
			echo -e -n  "Wikipedia webpage located on Linnean & Common name.\n${ORANGE}However using linnean $LINNEAN_NAME wikipage as preferred source.${NC}\n\n"
			return
		elif [[ -s ${CORE}.spname.wiki.json ]] && [[ ! -s ${CORE}.commonname.wiki.json ]]; then
			mv $LOCAL_DIR/${CORE}.spname.wiki.json $WIKI_DIR/${CORE}.wiki.json
			rm $LOCAL_DIR/${CORE}.commonname.wiki.json
			echo -e -n "Wikipedia webpage exists based on Linnean name: $LINNEAN_NAME. Now set for $CORE !\n\n"
			return
		elif [[ ! -s ${CORE}.spname.wiki.json ]] && [[ -s ${CORE}.commonname.wiki.json ]]; then
			mv $LOCAL_DIR/${CORE}.commonname.wiki.json $WIKI_DIR/${CORE}.wiki.json
			rm $LOCAL_DIR/${CORE}.spname.wiki.json
			echo -e -n "Wikipedia webpage exists based soley on species common name.\n${ORANGE}Must now use common name $FALL_BACK_NAME wikipage for static.${NC}\n\n"
			echo ${CORE}.spname.wiki.json >> Without_Wikipedia_Summary_Content.txt
			return
		else
			echo -e -n  "${RED}Unable to find wikipedia webpage for the Linnean OR Common name -> $CORE${NC}\n\n"
			echo ${CORE}.spname.wiki.json >> Without_Wikipedia_Summary_Content.txt
			echo ${CORE}.commonname.wiki.json >> Without_Wikipedia_Summary_Content.txt
			rm $LOCAL_DIR/${CORE}.{commonname,spname}.wiki.json
			return
		fi
	}

	## Generate the list of wikipedia_urls and generate wget cmds for JSON summary retrival
	while read CORE
	do
		NAME_COUNT=0
		echo -e -ne "Downloading Wikipedia information (JSON) on species linked to core_db: $CORE\n";
		SCI_NAME=`$HOST_NAME -D $CORE -e "select meta_value from meta where meta_key = \"species.scientific_name\";" \
			| tail -n 1 | tr " " "_"`
		SP_COMMON_NAME=`$HOST_NAME -D $CORE -e "select meta_value from meta where meta_key = \"species.common_name\";" \
			| tail -n 1 | tr " " "_"`
		echo -e -n "${PURPLE}Scientific name: $SCI_NAME | "
		echo -e -n "Common name: $SP_COMMON_NAME${NC}\n"

		# Create both linnean and common name wiki urls and check for content
		if [ ! -z $SCI_NAME ]; then
			NAME_COUNT=$((NAME_COUNT+1))
			FORMAT_NAME=`echo $SCI_NAME | sed 's/_/%20/'`;
			echo $SCI_NAME | xargs -n 1 -I XXX echo "https://en.wikipedia.org/wiki/XXX" >> Wikipedia_URL_listed.check.txt
			echo "wget -qq --header='accept: application/json; charset=utf-8' --header 'Accept-Language: en-en' \
				'https://en.wikipedia.org/api/rest_v1/page/summary/$FORMAT_NAME?redirect=true' -O ${CORE}.spname.wiki.json" >> generate_Wiki_JSON_Summary.sh
		fi

		if [ ! -z $SP_COMMON_NAME ]; then
			NAME_COUNT=$((NAME_COUNT+1))
			FORMAT_NAME=`echo $SP_COMMON_NAME | sed s/\'//g | sed 's/_/%20/'`;
			echo $SP_COMMON_NAME | sed s/\'//g | xargs -n 1 -I XXX echo "https://en.wikipedia.org/wiki/XXX" >> Wikipedia_URL_listed.check.txt
			echo "wget -qq --header='accept: application/json; charset=utf-8' --header 'Accept-Language: en-en' \
				'https://en.wikipedia.org/api/rest_v1/page/summary/$FORMAT_NAME?redirect=true' -O ${CORE}.commonname.wiki.json" >> generate_Wiki_JSON_Summary.sh
		fi

		# Now pull wiki entries if they exist:
		tail -n $NAME_COUNT generate_Wiki_JSON_Summary.sh > $CWD/temp_gen_wiki.sh
		sh $CWD/temp_gen_wiki.sh;
		if [[ $? == 0 ]]; then rm $CWD/temp_gen_wiki.sh; fi
		unset NAME_COUNT

		# Choose from available wikipedia species webpages
		check_wikipedia_content $CORE $CWD $WIKI_OUTPUT_JSONS $SCI_NAME $SP_COMMON_NAME

	done < $INPUT_DB_LIST

	## Check stage exited successfully, and Update stage log if confirmed. Set next stage var 'RUN_STAGE' to continue
	check_exit_status 0 "wikipedia" "NCBI"

fi

## OUTPUT FROM & 2 FILES: 1) Wikipedia urls to check (Done manually), 2) List of wget cmds to scrape Wiki summarys from Wikimedia REST API
if [[ -f $CWD/$STAGE_LOG ]]; then
	STAGE=`grep -e "ncbi_datasets" $CWD/$STAGE_LOG`
	if [[ $STAGE ]];then
		echo "## NCBI DATASETS STAGE Already Done! Moving to Static content MD generation."
		RUN_STAGE="STATIC"
	fi
fi

if [[ $RUN_STAGE == "ALL" ]] || [[ $RUN_STAGE == "NCBI" ]]; then

	## Check if the pre-requisit NCBI-datasets tool singularity image is present
	if [[ ! -f $DATASETS_SINGULARITY ]]; then

		echo -e -n "Do not detect ncbi-datasets singularity image file in $CWD.\nAttemtping to download ($DATASETS_DOCKER_VERSION_URL) from dockerhub...\n\n"

		# Check we have singularity installed
		SING_PRESENT=`which singularity`
		if [[ $SING_PRESENT ]]; then

			# Download the ncbi-datasets singularity image from docker hub https://hub.docker.com/r/ensemblorg/datasets-cli:
			echo -e -n "Attempting to retrive NCBI datasets-cli from docker 'ensemblorg/datasets-cli'\n\
			Image Tag -> '$DATASETS_DOCKER_VERSION_URL'\n"

			# Pull docker image with specific version
			singularity pull --arch amd64 $DATASETS_SINGULARITY $DATASETS_DOCKER_VERSION_URL

			if [[ -f $DATASETS_SINGULARITY ]]; then
				echo -e -n "\nNCBI-datasets Singualrity image downloaded with the exact latest version: $DATASETS_RELEASE!\n\n--> ";
				ls -l $DATASETS_SINGULARITY;
			else
				echo -e -n "\n Specific datasets-cli version was not found! attempting to pull Singualrity image with 'latest' tag instead.";

				# Attempt to pull docker image using 'latest' tag instead:
				singularity pull --arch amd64 $DATASETS_SINGULARITY $DATASETS_DOCKER_LATEST_URL
				DATASETS_SINGULARITY="${NXF_SINGULARITY_CACHEDIR}/${SIF_IMAGE_LATEST}"

				if [[ ! -f $DATASETS_SINGULARITY ]]; then
					echo "Unable to pull Specific latest version OR 'latest' tag datasets-cli SIF image. Exiting..."
					exit 1
				fi
			fi
		else
			echo -e -n "\n\nSingularity doens't appear to be installed. Please verify installation...Exiting\n"
			exit 1
		fi
	else
		echo -e -n "INFO: Detected NCBI-datasets singularity image --> $DATASETS_SINGULARITY.\nProceeding with static content generation !...\n\n"
		sleep 4
	fi

	## Get annotation release reports
	echo -e -n "\n\n *** Now gathering NCBI assembly and annotation summary files.....\n"

	mkdir -p $OUTPUT_NCBI

    while read CORE
    do
        GCA=`$HOST -D $CORE -Ne 'SELECT meta_value FROM meta WHERE meta_key = "assembly.accession";'`
		GCF=`echo "$GCA" | sed 's/GCA/GCF/'`; 
		echo -e -n "processing $CORE -> $GCA\n"
		INSDC=`echo $GCA | awk -F "." {'print $1'} | sed 's/GCA_/GCF_/'`
		VERSION=`echo $GCA | awk -F "." {'print $2'}`

		if [[ $VERSION == 1 ]]; then 
			echo "BaseCase: GCF $GCF."
	     	singularity run $DATASETS_SINGULARITY \
				datasets summary genome accession $GCF --assembly-source RefSeq --as-json-lines --report genome | \
			jq '.' > ${GCA}.genomereport.json
		else
			echo "Iterating over RefSeq (GCF_*) assembly versions {$VERSION..1}"

			ITERATE_VERSIONS=1
		fi

		if [[ $ITERATE_VERSIONS == 1 ]]; then

			while [[ $VERSION -ne 0 ]];
			do
				echo "Trying GCF $INSDC.$VERSION" 
        		singularity run $DATASETS_SINGULARITY \
					datasets summary genome accession $INSDC.$VERSION --assembly-source RefSeq --as-json-lines --report genome | \
				jq '.' > ${GCA}.genomereport.json

				if [[ -s ${GCA}.genomereport.json ]]; then
					echo "Obtained genome report on RefSeq assembly:> $INSDC.$VERSION"
					unset ITERATE_VERSIONS
					break 1
				fi

				VERSION=$(($VERSION-1))

			done

		fi

		## Unless the genome report JSON exists and isn't empty, attempt on GCA accession using genbank source
		if [[ ! -s ${GCA}.genomereport.json ]]; then
			echo "Tried obtaining RefSeq reports, but missing on [$GCF]. Trying GCA instead"
			singularity run $DATASETS_SINGULARITY \
				datasets summary genome accession $GCA --assembly-source GenBank --as-json-lines --report genome | \
			jq '.' > ${GCA}.genomereport.json
			if [[ ! -s ${GCA}.genomereport.json ]]; then echo "WARNING: Unable to obtained genome report for $CORE [$GCA] !!"; fi
		fi

		mv ${GCA}.genomereport.json $OUTPUT_NCBI

    done < $INPUT_DB_LIST

	## Check stage exited successfully, and Update stage log if confirmed. Set next stage var 'RUN_STAGE' to continue
	check_exit_status $? "ncbi_datasets" "STATIC"

fi

### Run the main parser to generate static content and create ensembl-static dirs/*.md files.
if [[ -f $CWD/$STAGE_LOG ]]; then
	STAGE=`grep -e "static_generation" $CWD/$STAGE_LOG`
	if [[ $STAGE ]];then
		echo "## Static Generation Already Done! Moving to Static content MD generation."
		RUN_STAGE="IMAGE"
	fi
fi

if [[ $RUN_STAGE == "ALL" ]] || [[ $RUN_STAGE == "STATIC" ]]; then

	SAFE_DIVISION=`echo "$ENS_DIVISION" | tr " " "_"`

	#Make sure to remove any old/failed partial run of StaticContent_Gen_${RELEASE}_${HOST}.log
	if [[ -e ./StaticContent_Gen_${RELEASE}_${HOST}.log ]]; then
		echo "Deleting old StaticContent_Gen_${RELEASE}_${HOST}.log"
		rm ./StaticContent_Gen_${RELEASE}_${HOST}.log
	fi

	echo -e -n "\n\n *** Now running JSON to Static Parser\n\t---> \
	\"perl Generate_StaticContent_MD.pl $WIKI_OUTPUT_JSONS $OUTPUT_NCBI 'CORE' $HOST $RELEASE $ENS_DIVISION\"\n"
	
	while read CORE_DB_STATIC;
	do
		# echo "perl $STATIC_BASE_DIR/Generate_StaticContent_MD.pl $WIKI_OUTPUT_JSONS $OUTPUT_NCBI $CORE_DB_STATIC $HOST $RELEASE"
		perl $STATIC_BASE_DIR/Generate_StaticContent_MD.pl $WIKI_OUTPUT_JSONS $OUTPUT_NCBI $CORE_DB_STATIC $HOST $RELEASE $SAFE_DIVISION 2>&1 | tee -a StaticContent_Gen_${RELEASE}_${HOST}.log
		
		## Check stage exited successfully, and Update stage log if confirmed. Set next stage var 'RUN_STAGE' to continue
		PER_DB_STATIC_EXIT=$?
		if [[ $PER_DB_STATIC_EXIT != 0 ]]; then
			echo -e -n "${RED} Oh no the static MD file generation on $CORE_DB_STATIC has failed${NC}\n"
			exit 1
		fi
	done < $INPUT_DB_LIST

	check_exit_status $PER_DB_STATIC_EXIT "static_generation" "IMAGE"

fi


### Run the Wiki image resource gathering. Locate species images for each JSON dump file from earlier.
if [[ -f $CWD/$STAGE_LOG ]]; then
	STAGE=`grep -e "image_resources" $CWD/$STAGE_LOG`
	if [[ $STAGE ]];then
		echo "## Image resource stage already Done! Moving to update image usage licensing (_about.md files)."
		RUN_STAGE="LICENSEUSAGE"
	fi
fi

if [[ $RUN_STAGE == "ALL" ]] || [[ $RUN_STAGE == "IMAGE" ]]; then

	echo -e -n "\n\n*** Attempting to gather Species Image Resources from wikipedia.....\n---> \
	\"sh Image_resource_gather.sh $WIKI_OUTPUT_JSONS\"\n\n"
	sh $STATIC_BASE_DIR/Image_resource_gather.sh $WIKI_OUTPUT_JSONS

	## Check stage exited successfully, and Update stage log if confirmed. Set next stage var 'RUN_STAGE' to continue
	check_exit_status $? "image_resources" "LICENSEUSAGE"

fi

### Run the Wiki image usage license update.
if [[ -f $CWD/$STAGE_LOG ]]; then
	STAGE=`grep -e "usage_lisence" $CWD/$STAGE_LOG`
	if [[ $STAGE ]];then
		echo "## Image licensing already updated, moving to generation of Whats_New MD content"
		RUN_STAGE="WHATSNEW"
	fi
fi

if [[ $RUN_STAGE == "ALL" ]] || [[ $RUN_STAGE == "LICENSEUSAGE" ]]; then

	## Now Update any static '_about.md' markdown files with the relevant image resource licenses where 
	## they exist (Input being 'Output_Image_Licenses.tsv').
	echo -e -n "\n\n*** Attempting update of species '_about.md' static image usage licenses in 5 secs.....\nOR - Stop here \
		'CTRL+C' and continue later by calling:\n\n\"perl ./Update_image_licenses.pl $RELEASE $CWD\"\n\n"
	sleep 5

	perl $STATIC_BASE_DIR/Update_image_licenses.pl $RELEASE $CWD

	## Check stage exited successfully, and Update stage log if confirmed. Set next stage var 'RUN_STAGE' to continue
	check_exit_status $? "usage_lisence" "WHATSNEW"

fi

### Run generation of whats_new MD file
if [[ -f $CWD/$STAGE_LOG ]]; then
	STAGE=`grep -e "whats_new_MD" $CWD/$STAGE_LOG`
	if [[ $STAGE ]];then
		echo "## Whats_New MD generated already! Moving to clean up stage."
		RUN_STAGE="TIDY"
	fi
fi

if [[ $RUN_STAGE == "ALL" ]] || [[ $RUN_STAGE == "WHATSNEW" ]]; then

	echo -e -n "\n\n*** Generating static whats_new.md file to output MD formated species content...\n\n\"sh Generate_whatsnew_content.sh $INPUT_DB_LIST\"\n\n"

	sh $STATIC_BASE_DIR/Generate_whatsnew_content.sh $HOST $INPUT_DB_LIST 'pipe'

	## Check stage exited successfully, and Update stage log if confirmed. Set next stage var 'RUN_STAGE' to continue
	check_exit_status $? "whats_new_MD" "TIDY"

	if [[ -e ./StaticContent_MD_Output-${RELEASE} ]]; then
		mv ${CWD}/WhatsNewContent.md ${CWD}/StaticContent_MD_Output-${RELEASE}/
	else
		mkdir -p StaticContent_MD_Output-${RELEASE}
		mv ${CWD}/WhatsNewContent.md ${CWD}/StaticContent_MD_Output-${RELEASE}/
	fi

	echo -e -n "\n* Generated whatsnew.md (MD) content found here --> \t"
	echo "StaticContent_MD_Output-${RELEASE}/WhatsNewContent.md"

fi

## Tidy output / intermediate files
if [[ -f $CWD/$STAGE_LOG ]]; then
	STAGE=`grep -e "tidy_output" $CWD/$STAGE_LOG`
	if [[ $STAGE ]]; then
		echo -e -n "\n*** Pipeline has already completed for run \"$RELEASE\".\n"
		echo -e -n "To perform a full re-run, delete file or remove stages: -> $CWD/$STAGE_LOG\n"
		echo -e -n "## Output gathered and stored here:\n${CWD}/$RELEASE/\n\n"
		exit 0
	fi
fi

if [[ $RUN_STAGE == "ALL" ]] || [[ $RUN_STAGE == "TIDY" ]]; then
	echo -e -n "\n\n*** Cleaning working folder: $CWD\n"

	mkdir -p ${CWD}/Log_Outputs_and_intermediates
	mkdir -p ${CWD}/$RELEASE
	STATIC_DIR="StaticContent_MD_Output-${RELEASE}"

	LOG_FILES=(\
		generate_Wiki_JSON_Summary.sh" \
		"Download_species_image_from_url.sh" \
		"Wikipedia_URL_listed.check.txt" \
		"wiki_sp2image.tsv" \
		"wiki_sp2image_NoMissing.tsv" \
		"Without_Wikipedia_Summary_Content.txt" \
		"StaticContent_Gen_${RELEASE}_${HOST}.log" \
		"Output_Image_Licenses.final.tsv\
		)

	#Tidy log files
	for LOG_FILE in ${LOG_FILES[@]};
	do
		if [[ -e $LOG_FILE ]]; then
			mv ${CWD}/$LOG_FILE ${CWD}/Log_Outputs_and_intermediates/
		else
			echo "No <$LOG_FILE> to tidy..."
		fi
	done


	#Tidy output folders
	OUT_FOLDERS=(\
		Commons_Licenses" \
		"NCBI_DATASETS" \
		"Source_Images_wikipedia" \
		"$STATIC_DIR" \
		"WIKI_JSON_OUT" \
		"Log_Outputs_and_intermediates\
		)
	for OUTFOLDER in ${OUT_FOLDERS[@]};
	do
		if [[ -e $OUTFOLDER ]]; then
			mv ${CWD}/$OUTFOLDER ${CWD}/$RELEASE/
		else
			echo "No <$OUTFOLDER> to tidy..."
		fi
	done

	## Check stage exited successfully, and Update stage log if confirmed. Set next stage var 'RUN_STAGE' to continue
	check_exit_status $? "tidy_output" "null"

	fi

echo -e -n "Log file tidy done! Logs stored here:\n${CWD}/$RELEASE/Log_Outputs_and_intermediates\n\n"
echo -e -n "Output folder tidy done! Output folders all stored here:\n${CWD}/$RELEASE/\n\n"

exit 0
