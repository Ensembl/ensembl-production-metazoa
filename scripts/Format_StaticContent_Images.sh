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

#convert -define png:size=80x80 Amyelois_transitella_gca001186105v1rs.jpg -thumbnail '80x80>' -background grey -gravity center -extent 80x80 Amyelois_transitella_gca001186105v1rs.png

IN_IMAGE_FORMAT=$1
PREFIX=$2
SOURCE_IMAGE_DIR=$3
OUT_IMAGE_FORMAT="png"
COLOUR=$4

if [[ -z $IN_IMAGE_FORMAT ]] || [[ -z $PREFIX ]] || [[ -z $SOURCE_IMAGE_DIR ]] || [[ -z $COLOUR ]]; then

	echo -e -n "Usage:\tsh Format_StaticContent_Images.sh <Source image format> <File prefix> <Unformatted Images folder> <Background colour>\nE.g:\n"
	echo -e -n "Process all images with JPG format:\t\$ sh Format_StaticContent_Images.sh jpg * ./SourceImages/ black\n"
	echo -e -n "Process all drosophila image files with png format:\t\$ sh Format_StaticContent_Images.sh png Drosophila_* ./SourceImages/ 'rgb(192,192,192)'\n"
        echo -e -n "Only process Apis_mellifera image:\t\$ sh Format_StaticContent_Images.sh png Apis_mellifera ./SourceImages/ white\n"
	exit 0
fi

# Beging processing:
FOLDER_IN=`readlink -f $SOURCE_IMAGE_DIR`
mkdir -p tmp_image_processing
mkdir -p ImageMagick_Formatted_Images

cd ./tmp_image_processing

cp $FOLDER_IN/${PREFIX}.${IN_IMAGE_FORMAT} ./

for IN_IMAGE in ${PREFIX}.${IN_IMAGE_FORMAT}
do
	echo "Processing image file: $IN_IMAGE"
	BASE_NAME=`basename $IN_IMAGE .${IN_IMAGE_FORMAT}`
	convert -define png:size=80x80 $IN_IMAGE \
	-thumbnail '80x80>' -background $COLOUR \
	-gravity center -extent 80x80 \
	${BASE_NAME}.$OUT_IMAGE_FORMAT
	echo "Finished image conversion - ${BASE_NAME}.$OUT_IMAGE_FORMAT"
	mv ${BASE_NAME}.$OUT_IMAGE_FORMAT ../ImageMagick_Formatted_Images
done

## Cleanup
cd ../
rm -rf ./tmp_image_processing
echo -e -n "Image conversion processing finished! \nSee Outdir --> ImageMagick_Formatted_Images\n"


exit
