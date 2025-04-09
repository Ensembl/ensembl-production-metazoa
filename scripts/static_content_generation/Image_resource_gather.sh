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

## A basic wrapper to obtain licensing information related to species for which you have wikipedia JSON summary dumps

## Get file image names from Wikipedia summary ".json" files. 

JSON_WIKI_DIR_USER=$1
CWD=$PWD

##Vars for STDOUT colour formatting
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

## WIKI REST Api functions:
function get_wiki_commonsURL (){

	local FILE_IMAGE_NAME=$1
	local SP_DIR_AND_NAME=$2
	local BASEURL="https://commons.wikimedia.org/w/api.php?action=query&titles=Image:${FILE_IMAGE_NAME}&prop=imageinfo&iiprop=extmetadata&format=json"

	echo "Getting Wikipedia Commons info for: $BASEURL"
	wget -qq --header='accept: application/json; charset=utf-8' "$BASEURL" -O $SP_DIR_AND_NAME
}

function get_wiki_altImages (){

	local BINOMIAL_SP=$1
	local SP_DIR_AND_NAME=$2
	local ALL_MEDIA_URL="https://en.wikipedia.org/api/rest_v1/page/media-list/${BINOMIAL_SP}"

	echo "Getting alternate wiki species images (if available): $ALL_MEDIA_URL"
	wget -qq --header='accept: application/json; charset=utf-8; profile="https://www.mediawiki.org/wiki/Specs/Media/1.3.1"' "$ALL_MEDIA_URL" -O ${SP_DIR_AND_NAME}_otherImages.json
}

if [[ -z $JSON_WIKI_DIR_USER ]]; then

	echo "Usage: sh Image_resource_gather.sh <INPUT WIKI JSON(s) DIR>"
	exit 1
fi

JSON_WIKI_DIR_FULL=`readlink -f $JSON_WIKI_DIR_USER`

#Remove older files from past runs if present
rm -f ${CWD}/wiki_sp2image.tsv
rm -f ${CWD}/Download_species_image_from_url.sh
rm -f ${CWD}/wiki_sp2image_NoMissing.tsv


## Gather the main image information for each WIKI json file:
for JSON in ${JSON_WIKI_DIR_FULL}/*.wiki.json
do 
	
	# Get the main path+file name of each species being processed:
	SPECIES=(`echo $JSON | sed -E 's/_core.+$//'`)
	echo -e -n "\nProcessing wikipedia image information:\n --> $SPECIES\n"
	echo -e -n "$SPECIES\t" >> wiki_sp2image.tsv

	# Format species names, using binomial only and replacing space for %20
	LC_BINOMIAL_SP=`echo $SPECIES | awk -F "/" {'print $NF'}`
	#Make file name of (production_name) upper case as needed for static image files:
	BINOMIAL_SP=${LC_BINOMIAL_SP^}
	
	#Obtain the source url from Wiki Json (wiki species landing page)
	SOURCE_URL=`jq -r '. | .originalimage | .source' $JSON`
	#Replace all instances of encoded "(,) - %28/ %29 which I found interfered with obtaining image licensing information"
	MEDIA_VIEW_BASE_URL="https://en.wikipedia.org/wiki/File"
	IMAGE_NAME=`echo $SOURCE_URL | awk -F"/" '{print $NF}' | sed -E 's/[",]//g' | sed 's/%28/(/' | sed 's/%29/)/' | sed -E 's/[0-9]+px-//'`  
	TARGET_IMAGE_URL="${MEDIA_VIEW_BASE_URL}:${IMAGE_NAME}"
	FORMAT=`echo $IMAGE_NAME | awk -F"." '{print $NF}'`
	PROD_IMAGE=${JSON_WIKI_DIR_FULL}/$BINOMIAL_SP.${FORMAT}

	## First check if we have image licensing information on the main image, if not look up information on all images available: /page/media-list/{title}
	if [ $IMAGE_NAME ]; then

		# Format species names, using binomial only and replacing space for %20
		FORMATED_BINOMIAL_SP=`echo $LC_BINOMIAL_SP | awk -F "_" {'print $1,$2'} | sed 's/ /%20/'`
		ALL_MEDIA_URL="https://en.wikipedia.org/api/rest_v1/page/media-list/${FORMATED_BINOMIAL_SP}"

		#Download all available media from wiki
		LICENSE_JSON_URL="$(get_wiki_commonsURL $IMAGE_NAME ${SPECIES}_primaryImage_commonLicense.tmp.json)"

		#Check if there are images assoicated with a given species image file name. Unless jq query returns pages: >0 there are not images associated with species landing page
		CHECK_NULL=`cat ${SPECIES}_primaryImage_commonLicense.tmp.json | jq '.query.pages."-1"'`

		# Now check if there is actual meta commons info to parse, otherwise try any other images that may be available
		if [[ "$CHECK_NULL" =~ 'null' ]]; then
			echo -e -n "${GREEN}Commons license retrieved for the primary wikipedia species image: $IMAGE_NAME${NC}\n"

			#Control var for file tidy
			ALT_JSONS_MADE="NO"
			rm ${SPECIES}_primaryImage_commonLicense.tmp.json
		else	
			echo -e -n  "${ORANGE}WARNING: No license info available for primary wiki image: $IMAGE_NAME${NC}\n"
			echo "....Checking if alternate wiki image(s) are available!"
			rm ${SPECIES}_primaryImage_commonLicense.tmp.json

			#Control var for file tidy
			ALT_JSONS_MADE="YES"

			#Download the alternate images JSON
			get_wiki_altImages $FORMATED_BINOMIAL_SP $SPECIES

			## Get Secondary species image file name(s)
			cat ${SPECIES}_otherImages.json | jq '.items[] | select(.section_id=='0') | select(.leadImage==false).title' > ${SPECIES}.listed.alternative.images.txt
			# echo "Other images to test for licensing information:"
			while read ALT_IMAGE
			do	
				ALT_IMAGE=`echo $ALT_IMAGE | sed 's/"//g' | sed 's/File://g'`
				LICENSE_JSON_URL="$(get_wiki_commonsURL $ALT_IMAGE ${SPECIES}_altImage_commonLicense.json)"

				# Recheck if commons license info on alt image is available:
				CHECK_NULL_2=`cat ${SPECIES}_altImage_commonLicense.json | jq '.query.pages."-1"'`
				if [[ "$CHECK_NULL_2" =~ 'null' ]]; then
					# echo "THERE IS LICENSE ON THE ALTERNATE IMAGE: $ALT_IMAGE"
					TMP_ALT_IMAGE=`cat ${SPECIES}_otherImages.json | jq '.items[] | select(.section_id=='0') | select(.leadImage==false).srcset' | grep -e 'src' | head -n 1 | awk -F ": " {'print $2'} | sed 's/[",]//g'`
					ALT_IMAGE_URL="https:${TMP_ALT_IMAGE}"
					IMAGE_NAME=$ALT_IMAGE
					TARGET_IMAGE_URL=$ALT_IMAGE_URL
					SOURCE_URL=$ALT_IMAGE_URL
				else
					echo -e -n "${RED}WARNING: No wikicommons license info located on non-primary species image: $ALT_IMAGE${NC}\n"
				fi	
			done < ${SPECIES}.listed.alternative.images.txt
		fi

		#Check if we needed to retrieve other wiki JSONs for non-primary files
		if [[ $ALT_JSONS_MADE == "YES" ]];then 
		mkdir -p ${SPECIES}_intermedidate_wiki/;

		#Tidy up files
		for INTER_FILE in _otherImages.json _altImage_commonLicense.json .listed.alternative.images.txt
			do
				mv ${SPECIES}${INTER_FILE} ${SPECIES}_intermedidate_wiki/
			done
		fi
	fi

	if [ $IMAGE_NAME ]; then
		echo -e -n "$IMAGE_NAME\t$TARGET_IMAGE_URL\n"  >> wiki_sp2image.tsv
		echo -e -n "echo \"Downloading species image: $IMAGE_NAME\"\n" >> Download_species_image_from_url.sh
		echo -e -n "wget -qq '$SOURCE_URL' -O $PROD_IMAGE\n" >> Download_species_image_from_url.sh

		# Sleep for ~20s or we get throttled by wiki for to many concurrent connection requests:
		echo -e -n "sleep 20\n" >> Download_species_image_from_url.sh
	else
		echo "**NO SPECIES IMAGE FOUND**" >> wiki_sp2image.tsv
	fi
done

# Check if there were species without available image files on wiki
COUNT_MISSING_IMAGES=`cat wiki_sp2image.tsv | grep -c "NO SPECIES IMAGE FOUND"`
if [[ $COUNT_MISSING_IMAGES = 0 ]]; then
	echo -e -n "\n${GREEN}Great news. All species have images to pull from wikipedia !${NC}\n\n"
	sleep 2
else
	echo -e -n "\n\n${RED}***** Unavailable image resources. JSON file(s) *****\n"
	cat wiki_sp2image.tsv | grep -e "NO SPECIES IMAGE FOUND" | awk {'print $1'}
	echo -e -n "****************************************************${NC}\n\n"
fi
cat wiki_sp2image.tsv | grep -v "NO SPECIES IMAGE FOUND" > wiki_sp2image_NoMissing.tsv

## Move all source image files into single folder
if [[ -e ${CWD}/Download_species_image_from_url.sh ]]; then

	echo -e -n "!! Downloading all original species source images to folder [20s timeout between image retrieval]:\n\n"

	sh ${CWD}/Download_species_image_from_url.sh
	mkdir -p $CWD/Source_Images_wikipedia
	grep -e 'wget' Download_species_image_from_url.sh | awk -F" " '{print $NF}' | xargs -n 1 -I XXX mv XXX $CWD/Source_Images_wikipedia

else
	echo -e -n "${RED}WARNING: No source images were located !! Noting more to do!!${NC}\n"
fi

#Check we don't rewrite over a previous run in case of loss of data
if [ -e ./Output_Image_Licenses.final.tsv ]; then
	mv ./Output_Image_Licenses.final.tsv ./OLD_Image_Licenses.tsv
	echo -e -n "\nPreviously generated wiki license TSV retained as \"OLD_Image_Licenses.tsv\"\n\n"
fi

## Gather licensing information for each image file name
if [[ -e ${CWD}/wiki_sp2image_NoMissing.tsv ]]; then

	echo -e -n "\nBeginning to process image licensing meta info from Wikicommons....\n\n"
	while read LINE
	do

	SPECIES_JSON=`echo $LINE | awk {'print $1'}`
	SPECIES_ONLY=`echo $LINE | awk {'print $1'} | awk -F"/" {'print $NF'}`
	IMAGE=`echo $LINE | awk {'print $2'}`
	IMAGE_URL=`echo $LINE | awk {'print $3'} | sed 's/%28/(/' | sed 's/%29/)/' | sed -E 's/[0-9]+px-//'`

	# Get commons meta info on downloaded image file:
	LICENSE_JSON_URL="$(get_wiki_commonsURL $IMAGE ${SPECIES_JSON}_meta_license.json)"

	
	USAGETERM=`jq '.' ${SPECIES_JSON}_meta_license.json | grep -A 1 -e "UsageTerms" | \
	tail -n 1 | awk -F":" {'print $2'} | sed -E 's/[",]//g' | sed 's/^ //'`
	COMMONS_URL=`jq '.' ${SPECIES_JSON}_meta_license.json | grep -A 1 -e "LicenseUrl" | \
	tail -n 1 | awk -F" " {'print $2'} | sed -E 's/[",]//g' | sed 's/^ //'`
	
	## Check what kind of usage terms is defined on license, common usage or specific usage:
	if [[ $USAGETERM == 'Public domain' ]]; then
		echo -e -n "$SPECIES_ONLY =>\tPicture credit: [${USAGETERM}](https://commons.wikimedia.org/wiki/Main_Page) via Wikimedia Commons [(Image source)](${IMAGE_URL})\n\n" >> Output_Image_Licenses.final.tsv
	else
		echo -e -n "$SPECIES_ONLY =>\tPicture credit: [${USAGETERM}](${COMMONS_URL}) via Wikimedia Commons [(Image source)](${IMAGE_URL})\n\n" >> Output_Image_Licenses.final.tsv
	fi
	done < wiki_sp2image_NoMissing.tsv
	
	
	echo -e -n "${PURPLE} **** Finalised Image License Meta Info ******${NC}\n\n"
	#Cleanup tmp files
	mkdir -p $CWD/Commons_Licenses; mv ${JSON_WIKI_DIR_FULL}/*_meta_license.json ${CWD}/Commons_Licenses
	rm ${CWD}/wiki_sp2image_NoMissing.tsv

	# Print to screen the main licensing information gathered per species/core
	cat Output_Image_Licenses.final.tsv

	# Replace the captured image license information into each of the corresponding MD files
	# Correspondance is via bionomial species name
	cat Output_Image_Licenses.final.tsv | sed 's/ =>//g' | sed '/^$/d' | grep -v -e "Picture credit: \[\]()" > temp_output_license.tsv
else

	echo -e -n "${ORANGE}No source images located. Nothing to do !!${NC}"
	exit 1

fi

echo -e -n "${GREEN}* Finished Species image download stage !!!${NC}\n\n"

exit 0

## Image Magik commands:
#convert +repage -background grey -gravity center -extent 1410x1410 -resize 80x60 image.jpg image.png

#-extent >> to select region from an image (when its not square or where the image subject isn't centered or occupys the majority of the image.
#-resize output image size
