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
CWD=`readlink -f $PWD`

STAGE_LOG="_static_stages_done_${RELEASE}"
OUTPUT_NCBI="$CWD/NCBI_DATASETS"
WIKI_OUTPUT_JSONS="$CWD/WIKI_JSON_OUT"
ENS_PRODUCTION_METAZOA="$CWD/ensembl-production-metazoa"
DATASETS_SING_IMAGE="library://lcampbell/ensembl-genomio/ncbi-datasets-v16.0:latest" #SyLabs hosted image, contact lcampbell@ebi.ac.uk for further details 
DATASETS_SINGULARITY="$CWD/ncbi-datasets-v16.0_latest.sif"

if [[ -d ${ENS_PRODUCTION_METAZOA} ]]; then
	STATIC_BASE_DIR="${ENS_PRODUCTION_METAZOA}/scripts/static_content_generation"
else
	cd $CWD
	echo "Can not detect required repository 'ensembl-production-metazoa' in CWD. Attemtping to download now..."
	sleep 3
	git clone -b main --depth 1 git@github.com:Ensembl/ensembl-production-metazoa.git
	STATIC_BASE_DIR="${ENS_PRODUCTION_METAZOA}/scripts/static_content_generation"
fi

if [[ $RUN_STAGE == TEMPLATE ]]; then

       	# ### Generate blank files for species not linked with GCF_
        read -p "Generating blank MD files. Enter species.production_name : " PROD_NAME

		if [[ -d $ENS_PRODUCTION_METAZOA ]]; then

		    for EXTENSION in _about.md _annotation.md _assembly.md
            do
            cp $ENS_PRODUCTION_METAZOA/scripts/static_content_generation/template${EXTENSION} $CWD/${PROD_NAME}${EXTENSION};
            done
        	echo -e -n "Generated generic template Markdown files:\n[${PROD_NAME}_about.md, ${PROD_NAME}_annotation.md, ${PROD_NAME}_assembly.md]\n!!! Please amend these files to fill in the missing values !$"
        	exit 0
		fi

fi

if [[ -z $INPUT_DB_LIST ]] || [[ -z $HOST ]] || [[ -z $RELEASE ]] || [[ -z $STATIC_BASE_DIR ]]; then
 	echo "Usage: sh CoreList_To_StaticContent.sh Template"
 	echo -e -n "\tOR\n"
 	echo "Usage: sh CoreList_To_StaticContent.sh <RunStage: All, Wiki, NCBI, Static, Image, WhatsNew, Tidy> <INPUT_DB_LIST> <MYSQL_HOST_SERVER> <Unique_Run_Identifier>"
 	exit 0
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

	## Generate the list of wikipedia_urls and generate wget cmds for JSON summary retrival
	while read CORE
	do
		echo -e -ne "Downloading Wikipedia information (JSON) on species linked to core_db: $CORE\n";
		SCI_NAME=`$HOST_NAME -D $CORE -e "select meta_value from meta where meta_key = \"species.scientific_name\";" | tail -n 1 | tr " " "_"`
		echo "Scientific name: $SCI_NAME"
		FORMAT_SCI_NAME=`echo $SCI_NAME | sed 's/_/%20/'`;
		echo $SCI_NAME | xargs -n 1 -I XXX echo "https://en.wikipedia.org/wiki/XXX" >> Wikipedia_URL_listed.check.txt
		echo "wget -qq --header='accept: application/json; charset=utf-8' --header 'Accept-Language: en-en' 'https://en.wikipedia.org/api/rest_v1/page/summary/$FORMAT_SCI_NAME?redirect=true' -O ${CORE}.wiki.json" >> generate_Wiki_JSON_Summary.sh
	done < $INPUT_DB_LIST

	## Run the JSON REST wgets and place inside a folder:
	`sh generate_Wiki_JSON_Summary.sh; mv *.json $WIKI_OUTPUT_JSONS`

	##Find out which species have not got any wikipedia information
	find $WIKI_OUTPUT_JSONS -empty | awk 'BEGIN{FS="/";}{print $NF}' >> Without_Wikipedia_Summary_Content.txt
	echo "wikipedia" > $CWD/$STAGE_LOG
	RUN_STAGE="NCBI"

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

		echo -e -n "Do not detect ncbi-datasets singularity image file in $CWD.\nAttemtping to download ($DATASETS_SING_IMAGE) from SyLabs now...\n\n"

		# Check we have singularity installed
		SING_PRESENT=`which singularity`
		if [[ $SING_PRESENT ]]; then

			# Download the ncbi-datasets singularity image:
			echo -e -n "Retriving NCBI-datasets tool singularity image from SyLabs:\n -> singularity pull --arch amd64 $DATASETS_SING_IMAGE"

			singularity pull --arch amd64 $DATASETS_SING_IMAGE

			if [[ -f $DATASETS_SINGULARITY ]]; then echo -e -n "\nNCBI-datasets Singualrity image downloaded !"; ls -l $DATASETS_SINGULARITY; fi

		else
			echo -e -n "\n\nSingularity doens't appear to be installed. Please verify installation...Exiting\n"
			exit 0
		fi
	else
		echo -e -n "INFO: Detected NCBI-datasets singularity image --> $DATASETS_SINGULARITY.\nProceeding with static content generation.\n\n"
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
			# GCF=`echo "$GCA" | sed 's/GCA/GCF/'`; 
			echo "BaseCase: GCF $GCF." 
     		singularity run $DATASETS_SINGULARITY \
			datasets summary genome accession $GCF --assembly-source RefSeq --as-json-lines --report genome | \
			jq '.' > ${GCA}.genomereport.json
		else 
			echo "Iterating over GCF versions {$VERSION..1}"

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
					echo "Obtained genome report on ($INSDC.$VERSION)"
					unset ITERATE_VERSIONS
					break 1
				fi

				VERSION=$(($VERSION-1))

			done

		fi

		## Unless the genome report JSON exists and isn't empty, attempt on GCA accession using genbank source
		if [[ ! -s ${GCA}.genomereport.json ]]; then
			echo "Tried RefSeq reports, but missing on [$GCF]. Trying GCA instead"
			singularity run $DATASETS_SINGULARITY \
			datasets summary genome accession $GCA --assembly-source GenBank --as-json-lines --report genome | \
			jq '.' > ${GCA}.genomereport.json
			if [[ ! -s ${GCA}.genomereport.json ]]; then echo "WARNING: Unable to obtained genome report for $CORE [$GCA] !!"; fi
		fi

		mv ${GCA}.genomereport.json $OUTPUT_NCBI

    done < $INPUT_DB_LIST

	# Update stage log 
	echo "ncbi_datasets" >> $CWD/$STAGE_LOG
	RUN_STAGE="STATIC"
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
	echo -e -n "\n\n *** Now running JSON to Static Parser\n\t---> \"perl Generate_StaticContent_MD.pl $WIKI_OUTPUT_JSONS $OUTPUT_NCBI $INPUT_DB_LIST $HOST $RELEASE\"\n"
	
	# echo "perl $STATIC_BASE_DIR/Generate_StaticContent_MD.pl $WIKI_OUTPUT_JSONS $OUTPUT_NCBI $INPUT_DB_LIST $HOST $RELEASE"
	perl $STATIC_BASE_DIR/Generate_StaticContent_MD.pl $WIKI_OUTPUT_JSONS $OUTPUT_NCBI $INPUT_DB_LIST $HOST $RELEASE 2>&1 | tee StaticContent_Gen_${RELEASE}_${HOST}.log

	# Update stage log 
	echo "static_generation" >> $CWD/$STAGE_LOG
	RUN_STAGE="IMAGE"
fi

### Run the Wiki image resource gathering. Locate species images for each JSON dump file from earlier.
if [[ -f $CWD/$STAGE_LOG ]]; then
	STAGE=`grep -e "image_resources" $CWD/$STAGE_LOG`
	if [[ $STAGE ]];then
		echo "## Image resource stage already Done! Moving to whats_new MD generation."
		RUN_STAGE="WHATSNEW"
	fi
fi

if [[ $RUN_STAGE == "ALL" ]] || [[ $RUN_STAGE == "IMAGE" ]]; then
	
	echo -e -n "\n\n*** Attempting to gather Species Image Resources from wikipedia.....\n---> \"sh Image_resource_gather.sh $WIKI_OUTPUT_JSONS\"\n\n"
	sh $STATIC_BASE_DIR/Image_resource_gather.sh $WIKI_OUTPUT_JSONS
	
	## Now Update any static '_about.md' markdown files with the relevant image resource licenses where they exist (Input being 'Output_Image_Licenses.tsv').
	echo -e -n "\n\n*** Updating species '_about.md' static files with full image licenses in 5 secs.....\nOR - Stop here 'CTRL+C' and continue later by calling:\n\n\"perl ./Update_image_licenses.pl $RELEASE\"\n\n"
	sleep 5
	
	perl $STATIC_BASE_DIR/Update_image_licenses.pl $RELEASE $CWD

	# Update stage log 
	echo "image_resources" >> $CWD/$STAGE_LOG
	RUN_STAGE="WHATSNEW"
fi

### Run stage to generate whats_new.md file 
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
	
	if [[ -e ./StaticContent_MD_Output-${RELEASE} ]]; then
		mv ${CWD}/WhatsNewContent.md ${CWD}/StaticContent_MD_Output-${RELEASE}/
	else
		mkdir -p StaticContent_MD_Output-${RELEASE}
		mv ${CWD}/WhatsNewContent.md ${CWD}/StaticContent_MD_Output-${RELEASE}/
	fi

	echo -e -n "\n* Generated whatsnew.md (MD) content found here --> \t"
	echo "StaticContent_MD_Output-${RELEASE}/WhatsNewContent.md"

	# Update stage log 
	echo "whats_new_MD" >> $CWD/$STAGE_LOG
	RUN_STAGE="TIDY"
fi

## Tidy output / intermediate files
if [[ -f $CWD/$STAGE_LOG ]]; then
	STAGE=`grep -e "tidy_output" $CWD/$STAGE_LOG`
	if [[ $STAGE ]]; then
		echo -e -n "\n*** Pipeline has already completed for run \"$RELEASE\".\nTo perform a full re-run, delete file or remove stages: -> $CWD/$STAGE_LOG\n"
		echo -e -n "## Output gathered and stored here:\n${CWD}/$RELEASE/\n\n"
		exit 1
	fi
fi

if [[ $RUN_STAGE == "ALL" ]] || [[ $RUN_STAGE == "TIDY" ]]; then
	echo -e -n "\n\n*** Cleaning working folder: $CWD\n"

	mkdir -p ${CWD}/Log_Outputs_and_intermediates
	mkdir -p ${CWD}/$RELEASE
	STATIC_DIR="StaticContent_MD_Output-${RELEASE}"

	#Tidy log files
	for LOG_FILE in generate_Wiki_JSON_Summary.sh Download_species_image_from_url.sh Wikipedia_URL_listed.check.txt wiki_sp2image.tsv wiki_sp2image_NoMissing.tsv Without_Wikipedia_Summary_Content.txt StaticContent_Gen_${RELEASE}_${HOST}.log Output_Image_Licenses.final.tsv
	do
		if [[ -e $LOG_FILE ]]; then
			mv ${CWD}/$LOG_FILE ${CWD}/Log_Outputs_and_intermediates/
		else
			echo "No <$LOG_FILE> to tidy..."
		fi
	done


	#Tidy output folders
	for OUTFOLDER in Commons_Licenses NCBI_DATASETS Source_Images_wikipedia $STATIC_DIR WIKI_JSON_OUT Log_Outputs_and_intermediates
	do
		if [[ -e $OUTFOLDER ]]; then
			mv ${CWD}/$OUTFOLDER ${CWD}/$RELEASE/
		else
			echo "No <$OUTFOLDER> to tidy..."
		fi
	done

		# Update stage log 
		echo "tidy_output" >> $CWD/$STAGE_LOG

	fi

echo -e -n "Log file tidy done! Logs stored here:\n${CWD}/$RELEASE/Log_Outputs_and_intermediates\n\n"
echo -e -n "Output folder tidy done! Output folders all stored here:\n${CWD}/$RELEASE/\n\n"

exit 1
