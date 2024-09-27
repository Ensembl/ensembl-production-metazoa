#!/usr/bin/sh
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

## Generate the list of wikipedia_url, JSON metadata and download available species images from wikipedia using a set of one or more species names.
## Species name(s) should be prodived as the sole input to this script inside a flat text file. Format = Apis_melifera (one sp per line)

INPUT_SP=$1
CWD=`readlink -f $PWD`
if [ -z $INPUT_SP ]; then

	echo "usage: sh Generate_WIKI_Sp_ImagesFromText.sh <Species_names_infile>"
	exit 1;
fi

INPUT_FILE=`readlink -f $INPUT_SP`
ENS_PRODUCTION_METAZOA="${CWD}/ensembl-production-metazoa/scripts/static_content_generation"


function gen_wiki_url (){

	local SCI_NAME=$1
	local OUT_DIR=$2

	FORMAT_SCI_NAME=`echo $SCI_NAME | sed 's/_/%20/' | sed 's/(/%28/' | sed 's/)/%29/'`;
        FORMAT_FILE_NAME=`echo $SCI_NAME | sed 's/ /_/' | tr -dc '[:alnum:]\n\r'`
	echo -e -ne "Downloading Wikipedia information (JSON) on species: $SCI_NAME\n"

	echo $SCI_NAME | xargs -n 1 -I XXX echo "https://en.wikipedia.org/wiki/XXX" >> Wikipedia_URL_listed.check.txt
	echo "wget -qq --header='accept: application/json; charset=utf-8' --header 'Accept-Language: en-en' 'https://en.wikipedia.org/api/rest_v1/page/summary/${FORMAT_SCI_NAME}?redirect=true' -O ${OUT_DIR}/${FORMAT_FILE_NAME}.wiki.json" >> download_Wiki_JSON_Summary.sh
}

# Generate the WIikipedia JSON download script and download JSON file per species.
mkdir -p $CWD/WIKI_JSON_OUT
export WIKI_DIR=`readlink -f $CWD/WIKI_JSON_OUT`
cd $WIKI_DIR
rm -f ./download_Wiki_JSON_Summary.sh

while read SPECIES
do
gen_wiki_url "$SPECIES" $WIKI_DIR
done < $INPUT_FILE
cd ..

# Run download of Wiki JSONs
`sh $WIKI_DIR/download_Wiki_JSON_Summary.sh`
echo "....done"

# Process images using input JSON folder
echo "Downloading species source image(s)"
sh ${ENS_PRODUCTION_METAZOA}/Image_resource_gather.sh $WIKI_DIR 2>&1 > image_download.log
echo "....done"

echo -e -n "\n\n### Log from image downloading:\n"
cat ./image_download.log

#Clean up
rm ./temp_output_license.tsv

exit 0
