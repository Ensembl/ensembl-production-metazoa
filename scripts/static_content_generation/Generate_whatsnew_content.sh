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

HOST=$1
CORE_FILE=$2
PIPE_OR_NO=$3

if [[ -z $HOST ]] || [[ -z $CORE_FILE ]]; then

	echo "usage: sh Generate_whatsnew_content.sh <HOST> <CORE LIST FILE>"
	exit 0
else
	echo -e -n "- **Assembly and gene set data updated**\n- **Updated gene sets**\n- **New assembly for existing species**\n- **New species**\n- **Updated BioMarts for all gene and variation data**\n- **Updated pan-taxonomic gene trees and homologies**\n- **Planned updates**\n\n" > ./WhatsNewContent.md
	while read CORE; do 
	SCI_NAME=`$HOST -D $CORE -N -e "select meta_value from meta where meta_key = 'species.scientific_name';"`;
	COMMON=`$HOST -D $CORE -N -e "select meta_value from meta where meta_key = 'species.common_name';"`;
	ACC=`$HOST -D $CORE -N -e "select meta_value from meta where meta_key = 'assembly.accession';"`;
	ESCAPE_ACC=`echo $ACC | sed 's/_/\\\_/g'`;
	echo "  - _${SCI_NAME}_ ($COMMON, $ESCAPE_ACC)" | tee -a WhatsNewContent.md; done < $CORE_FILE

fi

# Test is running as standalone or within main static content wrapper:
if [[ $PIPE_OR_NO != 'pipe' ]]; then
	echo -e -n "\n* Generated WhatsNew (MD) content found here --> \t"
	readlink -f ./WhatsNewContent.md
fi


exit 1
