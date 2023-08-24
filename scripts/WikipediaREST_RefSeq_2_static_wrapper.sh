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

## Main EnsMetazoa static content wrapper:
## Obtain from Wikipedia/RefSeq summary, annotation and assembly information and produce relevant static content markdown files (.md, image.jpg/png etc).

## NOTE *** REFSEQ urls passed MUST be related to species with annotation (GFC_). Genbank/GCA_ based assemblies will not produce the desired outputs.

RUN_STAGE=$1
INPUT_DB_LIST=$2
INPUT_REFSEQ_URL=$3
HOST=$4 #MYSQL server hosting the cores listed in $INPUT_DB_LIST. Can be short name e.g. st3b
RELEASE=$5

##Vars for STDOUT colour formatting
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

###Check for required env variables
# WorkDir ENV
if [[ -z $MAIN_BASE_DIR ]]; then
	MAIN_BASE_DIR=`readlink -f $PWD`
	echo -e "${ORANGE}**Work base MAIN_BASE_DIR environment var not defined. Setting to CWD !**"
	echo -e -n "--->\"$MAIN_BASE_DIR\"${NC}\n\n"
else
	echo -e -n "${GREEN}Base work directory 'MAIN_BASE_DIR' defined !\n---> \"$MAIN_BASE_DIR\"\n\n"
fi
# Location of ensembl-production-metazoa:
if [[ -z $ENS_MAIN_METAZOA_PROD ]]; then
	echo -e -n "**Location of 'ensembl-production-metazoa' repo not defined !**\nChecking here: 'MAIN_BASE_DIR'\n"

	if [[ -d ${MAIN_BASE_DIR}/ensembl-production-metazoa ]]; then
			echo -e -n "${GREEN}SUCCESS: Located local clone of '${MAIN_BASE_DIR}/ensembl-production-metazoa'.${NC}\n\n"
			ENS_MAIN_METAZOA_PROD="${MAIN_BASE_DIR}/ensembl-production-metazoa"
	else
			echo -e -n "${RED}FAILED: Please define environment var 'ENS_MAIN_METAZOA_PROD' with full path to /ensembl-production-metazoa repo.${NC}\n\nExiting !!\n"
			exit
	fi
fi


## Basic run case: Generate some tempalte markdown files to be filled in manually
if [[ $RUN_STAGE == template ]]; then

	# ### Generate blank files for species not linked with GCF_
	read -p "Generating blank MD files for single species. Enter species.production_name : " PROD_NAME

	BINOMIAL=`echo ${PROD_NAME^} | sed 's/_/ /g'`

	for EXTENSION in _about.md _annotation.md _assembly.md
		do
		cp ${ENS_MAIN_METAZOA_PROD}/scripts/template${EXTENSION} $MAIN_BASE_DIR/${PROD_NAME}${EXTENSION};
		done
	echo -e -n "\n${GREEN}Generated generic template Markdown files:${NC}\n[${PROD_NAME}_about.md, ${PROD_NAME}_annotation.md, ${PROD_NAME}_assembly.md]\n\n \
	${ORANGE}!!! Please amend these files and fill in the required meta info !!!${NC}\n\nBasic run finished. Exiting.\n"

	sed -i "s/scientific_name/$BINOMIAL/" $MAIN_BASE_DIR/${PROD_NAME}_about.md;
	exit 0
fi

## Main run case: Automatted processing of multiple species static content:
if [[ -z $INPUT_DB_LIST ]] || [[ -z $INPUT_REFSEQ_URL ]] || [[ -z $HOST ]] || [[ -z $RELEASE ]]; then

 	echo -e -n "#Basic usage (Generate template MD static files):\n---> 'sh WikipediaREST_RefSeq_2_static_wrapper.sh template'\n\n"
 	echo "-- OR --"
 	echo -e -n "\n#Automated processing usage:\n---> 'sh WikipediaREST_RefSeq_2_static_wrapper.sh <RunStage: All, Wiki, NCBI, Static, Image, WhatsNew, Tidy> <INPUT_DB_LIST> <INPUT_REFSEQ_URLS> <MYSQL_SERVER> <Unique_Run_Identifier>'\n"

 	exit 0
fi

HOST_NAME=`echo $($HOST details url) | awk 'BEGIN{FS="[@:/]";}{print $5}'`
OUTPUT_JSONS="$MAIN_BASE_DIR/WIKI_JSON_OUT"
TRACKING="$MAIN_BASE_DIR/${RELEASE}_checkDone"
mkdir -p $TRACKING

## Stage one: Obtain wikipedia JSON for each species
if [[ $RUN_STAGE == "All" ]] || [[ $RUN_STAGE == "Wiki" ]]; then

	mkdir -p $OUTPUT_JSONS

	#Make sure to remove any old generate_Wiki_JSON_Summary.sh
	if [[ -e $MAIN_BASE_DIR/generate_Wiki_JSON_Summary.sh ]]; then
		echo "Deleting old generate_Wiki_JSON_Summary.sh"
		rm $MAIN_BASE_DIR/generate_Wiki_JSON_Summary.sh
	fi

	echo -e -n "${ORANGE}Downloading Wikipedia information (JSON):${NC}\n\n"
	## Generate the list of wikipedia_urls and generate WGET cmds for JSON summary retrival
	while read CORE
	do
		echo -e -n "-- On species linked to core_db: $CORE\n";
		SCI_NAME=`$HOST_NAME -D $CORE -e "select meta_value from meta where meta_key = \"species.scientific_name\";" | tail -n 1 | tr " " "_"`
		echo -e -n "Scientific name: $SCI_NAME\n\n"
		FORMAT_SCI_NAME=`echo $SCI_NAME | sed 's/_/%20/'`;
		echo $SCI_NAME | xargs -n 1 -I XXX echo "https://en.wikipedia.org/wiki/XXX" >> Wikipedia_URL_listed.check.txt
		echo "wget -qq --header='accept: application/json; charset=utf-8' --header 'Accept-Language: en-en' 'https://en.wikipedia.org/api/rest_v1/page/summary/$FORMAT_SCI_NAME?redirect=true' -O ${CORE}.wiki.json" >> $MAIN_BASE_DIR/generate_Wiki_JSON_Summary.sh
	done < $INPUT_DB_LIST

	## Run the JSON REST wgets and place inside a folder:
	sh $MAIN_BASE_DIR/generate_Wiki_JSON_Summary.sh
	mv $MAIN_BASE_DIR/*.json $OUTPUT_JSONS

	##Find out which species have not got any wikipedia information
	find $OUTPUT_JSONS -empty | awk 'BEGIN{FS="/";}{print $NF}' >> Without_Wikipedia_Summary_Content.txt

	# Generate tracking files and set run next stage
	touch ${TRACKING}/_s1_wiki_gather
	RUN_STAGE="NCBI"

fi

## Stage two: OUTPUT FROM & 2 FILES: 1) Wikipedia urls to check (Done manually), 2) List of wget cmds to scrape Wiki summarys from Wikimedia REST API
if [[ $RUN_STAGE == "All" ]] || [[ $RUN_STAGE == "NCBI" ]]; then

	if [[ -e $TRACKING/_s1_wiki_gather ]]; then

		echo -e -n "\n\n${ORANGE}*** Now gathering NCBI assembly and annotation summary files.....${NC}\n"
		## Get annotation release reports
		while read URL
		do
			GCF_name=`echo $URL | awk 'BEGIN{FS="/";} {print $NF}'`
			echo $URL | xargs -n 1 -I XXX sh -c '
			wget -qq XXX -O - |
			grep -P "README_.*_annotation_release_.*" |
			cut -f 2 -d \" |
			xargs -n 1 -I YYY wget -qq XXX/YYY -O -
			' |
		cat > ${GCF_name}.refseq.anno.txt
		done < $INPUT_REFSEQ_URL

		OUTPUT_REFSEQ_ANNO="$MAIN_BASE_DIR/RefSeq_Annotation_Reports"
		mkdir -p $OUTPUT_REFSEQ_ANNO
		mv $MAIN_BASE_DIR/*.refseq.anno.txt $OUTPUT_REFSEQ_ANNO

		## Get assembly stats reports
		while read URL
		do
			GCF_name=`echo $URL | awk 'BEGIN{FS="/";} {print $NF}'`
			echo $URL | xargs -n 1 -I XXX sh -c '
			wget -qq XXX -O - |
			grep -P "assembly_stats.txt" |
			cut -f 2 -d \" |
			xargs -n 1 -I YYY wget -qq XXX/YYY -O -
			' |
		cat > ${GCF_name}.assemblystats.txt
		done < $INPUT_REFSEQ_URL

		OUTPUT_ASSEMB_STATS="$MAIN_BASE_DIR/RefSeq_Assembly_Reports"
		mkdir -p $OUTPUT_ASSEMB_STATS
		mv $MAIN_BASE_DIR/*.assemblystats.txt $OUTPUT_ASSEMB_STATS
		## Output from above ^ set of files, one per RefSeq url which will need to be parsed into json format and then output as markdown.

		echo -e -n "${GREEN}*Finished generating NCBI resource wget commands.\n${NC}"

		# Generate tracking files and set run next stage
		touch ${TRACKING}/_s2_ncbi_gather
		RUN_STAGE="Static"
	else
		echo -e -n "${ORANGE}Must first run stage [1]: 'Wiki'${NC}\n"
	fi
fi

## Stage three:  Run the main parser to generate static content and create ensembl-static dirs/*.md files.
if [[ $RUN_STAGE == "All" ]] || [[ $RUN_STAGE == "Static" ]]; then

	if [[ -e $TRACKING/_s2_ncbi_gather ]]; then

		echo -e -n "\n\n${ORANGE}*** Now running JSON to Static Parser in 5 secs.....OR - Stop here 'CTRL+C' and continue later by calling:${NC}\n \
---> \"perl Json_and_GCF_into_Static_MD_Parser.pl  $OUTPUT_JSONS $OUTPUT_REFSEQ_ANNO $OUTPUT_ASSEMB_STATS $INPUT_DB_LIST $INPUT_REFSEQ_URL $HOST $RELEASE\"\n"
		sleep 5

		perl $ENS_MAIN_METAZOA_PROD/scripts/Json_and_GCF_into_Static_MD_Parser.pl $OUTPUT_JSONS $OUTPUT_REFSEQ_ANNO $OUTPUT_ASSEMB_STATS $INPUT_DB_LIST $INPUT_REFSEQ_URL $HOST $RELEASE 2>&1 | tee StaticContent_Gen_${RELEASE}_${HOST}.log

		touch ${TRACKING}/_s3_generate_markdown
		RUN_STAGE="Image"
	else
		echo -e -n "${ORANGE}Must first run stage [2]: 'NCBI'${NC}\n"
	fi
fi

## Stage four:  Run the Wiki image resource gathering. Locate species images for each JSON dump file from earlier
if [[ $RUN_STAGE == "All" ]] || [[ $RUN_STAGE == "Image" ]]; then

	if [[ -e $TRACKING/_s3_generate_markdown ]]; then

		echo -e -n "\n\n${ORANGE}*** Gathering Species image resources from wikipedia.....${NC}\n\
		---> \"Image_resource_gather.sh $OUTPUT_JSONS\"\n\n"
		sh ${ENS_MAIN_METAZOA_PROD}/scripts/Image_resource_gather.sh $OUTPUT_JSONS $MAIN_BASE_DIR

		## Now Update any static '_about.md' markdown files with the relevant image resource licenses where they exist (Input being 'Output_Image_Licenses.tsv').
		echo -e -n "\n\n${ORANGE}*** Updating species '_about.md' static files with full image license information${NC}\n\
		---> \"Update_image_licenses.pl $RELEASE\"\n\n"
		# sleep 5

		perl $ENS_MAIN_METAZOA_PROD/scripts/Update_image_licenses.pl $RELEASE $MAIN_BASE_DIR

		# Generate tracking files and set run next stage
		touch ${TRACKING}/_s4_image_retrieval
		RUN_STAGE="WhatsNew"
	else
		echo -e -n "${ORANGE}Must first run stage [3]: 'Static'${NC}\n"
	fi
fi

## Stage five:  Run stage to generate whats_new.md file 
if [[ $RUN_STAGE == "All" ]] || [[ $RUN_STAGE == "WhatsNew" ]]; then

	if [[ -e $TRACKING/_s4_image_retrieval ]]; then

		echo -e -n "\n\n${ORANGE}*** Generating 'whats_new.md' file to output MD formated species content.....${NC}\n\
		---> \"sh Generate_whatsnew_content.sh $INPUT_DB_LIST\"\n\n"

		sh $ENS_MAIN_METAZOA_PROD/scripts/Generate_whatsnew_content.sh $HOST $INPUT_DB_LIST 'pipe'

		if [[ -e $MAIN_BASE_DIR/StaticContent_MD_Output-${RELEASE} ]]; then
			mv ${MAIN_BASE_DIR}/WhatsNewContent.md ${MAIN_BASE_DIR}/StaticContent_MD_Output-${RELEASE}/
		else
			mkdir -p StaticContent_MD_Output-${RELEASE}
			mv ${MAIN_BASE_DIR}/WhatsNewContent.md ${MAIN_BASE_DIR}/StaticContent_MD_Output-${RELEASE}/
		fi

		echo -e -n "\n${GREEN}* Generated generic whatsnew.md species content. MODIFY AS NEEDED!.${NC}\n"

		# Generate tracking files and set run next stage
		touch ${TRACKING}/_s5_whats_new_md
		RUN_STAGE="Tidy"
	else
		echo -e -n "${ORANGE}Must first run stage [4]: 'Image'${NC}\n"
	fi
fi

## Tidy output / intermediate files
if [[ $RUN_STAGE == "All" ]] || [[ $RUN_STAGE == "Tidy" ]]; then
	echo -e -n "\n\n${ORANGE}*** Tidying up WorkDir data${NC}\n"

	mkdir -p ${MAIN_BASE_DIR}/Log_Outputs_and_intermediates
	mkdir -p ${MAIN_BASE_DIR}/$RELEASE
	STATIC_DIR="StaticContent_MD_Output-${RELEASE}"

#Tidy log files
for LOG_FILE in generate_Wiki_JSON_Summary.sh Download_species_image_from_url.sh Wikipedia_URL_listed.check.txt wiki_sp2image.tsv Without_Wikipedia_Summary_Content.txt StaticContent_Gen_${RELEASE}_${HOST}.log Output_Image_Licenses.final.tsv
do
	if [[ -e $MAIN_BASE_DIR/$LOG_FILE ]]; then
		echo "Tidying -> [$LOG_FILE]"
		mv ${MAIN_BASE_DIR}/$LOG_FILE ${MAIN_BASE_DIR}/Log_Outputs_and_intermediates/
	else
		echo "Could not find: < $LOG_FILE >....Skipping tiddying."
	fi
done


#Tidy output folders
for OUTFOLDER in Commons_Licenses RefSeq_Annotation_Reports RefSeq_Assembly_Reports Source_Images_wikipedia $STATIC_DIR WIKI_JSON_OUT Log_Outputs_and_intermediates ${RELEASE}_checkDone
do
	if [[ -e $MAIN_BASE_DIR/$OUTFOLDER ]]; then
		mv ${MAIN_BASE_DIR}/$OUTFOLDER ${MAIN_BASE_DIR}/$RELEASE/
	else
		echo "No <$OUTFOLDER> to tidy..."
	fi
done
echo -e -n "\n* ${GREEN}Log file tidy done! Logs stored here:\n${NC}\"$RELEASE/Log_Outputs_and_intermediates\"\n\n"
echo -e -n "* ${GREEN}Static content and intermedidate data all stored here:${NC}\n\"${MAIN_BASE_DIR}/$RELEASE\"\n\n"
echo -e "${GREEN}DONE: All static content procesing finished !!!${NC}"
fi

exit 0
