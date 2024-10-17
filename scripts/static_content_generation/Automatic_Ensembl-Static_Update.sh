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

## Author: [Lahcen Campbell - lcampbell@ebi.ac.uk].
## A script to automatically updated the ensembl-static repo for metazoan species (or other if needed)
## Input to script is a directory containing one or more directories (one per species+gca). The script checks if this species is already
## present in the ens-static repo, and then copies or creates directories as neeeded. 

##Vars for STDOUT colour formatting
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

# Run vars
STATIC_MD_DIR=$1
RELEASE=$2
DIVISION=$3
STATIC_FLAG=$4
STATIC_IMAGES_DIR=$5
CWD=`readlink -f $PWD`
BASE_REPO="${CWD}/ensembl-static"

# #Check for user input of new static content folders/md files to be copied into ensembl-static repo
if [[ -z $STATIC_MD_DIR ]] || [[ -z $RELEASE ]]; then
	echo "Usage: sh Automatic_Ensembl-Static_Update.sh < Path to new static content dirs> <RELEASE BRANCH> <Division> Optional param: '--images' < + Path to static content images created by Core static pipeline>"
	echo "e.g. Automatic_Ensembl-Static_Update.sh StaticContent_MD/ release/eg/60 metazoa "
	echo "e.g. Automatic_Ensembl-Static_Update.sh StaticContent_MD/ release/eg/60 metazoa --images SourceImages/"
	exit 1
else
	TEMP_STATIC_IN=`readlink -f $STATIC_MD_DIR`
	NEW_STATIC_CONTENT="${TEMP_STATIC_IN}/"
	echo -e -n "${ORANGE} WARNING !!! You must first create a fork of ensembl-staic repo before running this script. Direct commits to Ensembl/ensembl-static are not permotted! ${NC}"
	sleep 2
	echo -e -n "\n--------------Starting static MD file move-------------\n\n"
fi

# Image directory provided ?
if [[ -e $STATIC_IMAGES_DIR ]]; then
	NEW_STATIC_IMAGES=`readlink -f $STATIC_IMAGES_DIR` 
fi

# Check an appropriate division was supplied by user
if [[ "$DIVISION" != "metazoa" ]] \
	&& [[ "$DIVISION" != "plants" ]] \
	&& [[ "$DIVISION" != "fungi" ]] \
	&& [[ "$DIVISION" != "bacteria" ]] \
	&& [[ "$DIVISION" != "protists" ]]; then
	echo -e -n "${RED}Division supplied ($DIVISION) not recognised. Must define as: [ metazoa | plants | fungi | bacteria | protists ]${NC}\n\n"
	exit 1
fi

# Check for fork user URL
AUTO_GIT_USER=`git config --global user.name`
if [[ ! $AUTO_GIT_USER ]]; then
	echo "Appears github user not set in '~/.gitconfig'"
	read -p "Please enter github user name for forked ensembl-static repo:" AUTO_GIT_USER
	echo "Git user set as: $AUTO_GIT_USER"
fi
FORK_REPO_URL="git@github.com:$AUTO_GIT_USER/ensembl-static.git"
echo "Detected Github user from ~/.gitconfig. Set ensembl-static SSH fork URL: $FORK_REPO_URL"

if [[ -d $BASE_REPO ]]; then
    echo "ensembl-static repo present already. Skipping cloning"
    cd $BASE_REPO

	BRANCH=`git branch | grep -e "*" | cut -d ' ' -f2`
	if [[ "$BRANCH" != "$RELEASE" ]]; then
		echo "Precloned ensembl-static is not on the specified branch: '$RELEASE'"
		git branch
		git checkout -b $RELEASE
	else
		echo "Precloned ensembl-static on correct branch: '$RELEASE'"
	fi
    cd ../
else
	echo "cloning ensembl-static now..."
	echo "git clone -b $RELEASE --depth 1 $FORK_REPO_URL"
	sleep 2
	git clone -b $RELEASE --depth 1 $FORK_REPO_URL $BASE_REPO

	if [[ -d $BASE_REPO ]]; then
		cd $BASE_REPO
		echo "Cloning finished ! Local clone found: '$BASE_REPO'"
		git branch
		cd ../
	else
		echo "Clone of ensembl-static appears to have failed. Can't find dir -> $CWD/ensembl-static ! Exiting."
		exit 1
	fi
fi

# Check on static image param
if [[ $STATIC_FLAG == '--images' ]]; then
	STATIC_ONLY=$STATIC_FLAG
else
	unset $STATIC_ONLY
fi

STATIC_REPO="${BASE_REPO}/$DIVISION/species"
IMAGE_REPO="${BASE_REPO}/$DIVISION/images/species"

PREXISTING_GENUS_COUNTER=0
PREXISTING_GENUS_FILE=Preexisting.genus.tmp
NEW_GENUS_FILE=NewGenus.tmp
NEW_SP_COUNTER=0
NEW_SP_FILE=NewSpecies.tmp
PREXISTING_SP_COUNTER=0
PREXISTING_SP_FILE=Preexisting.species.tmp
NEW_SP_ASM_COUNTER=0
NEW_SP_ASM_FILE=NewAsmVersions.species.tmp

find $NEW_STATIC_CONTENT -type d | awk -F "/" {'print $NF'} | cut -f1 -d "_" | sed 's/\.\///g' | sort | uniq > ${NEW_STATIC_CONTENT}/Genus_list.txt
sed -i '/^\s*$/d' ${NEW_STATIC_CONTENT}/Genus_list.txt
find $NEW_STATIC_CONTENT -type d | awk -F "/" {'print $NF'} | sed 's/\.\///g' | sort  > ${NEW_STATIC_CONTENT}/Species_List.txt
sed -i '/^\s*$/d' ${NEW_STATIC_CONTENT}/Species_List.txt

# Functions:
function print_species_bin () {

	# Function to print species/genus when found in particular update category.
	local STATIC_DIR=$1
	local SP_STATS=$2

	if [[ -e ${STATIC_DIR}/$SP_STATS ]]; then 
		cat ${STATIC_DIR}/${SP_STATS} | sort | uniq |  xargs -n 1 -I XXX echo " - XXX"
	else
		echo "Stats file: $SP_STATS not created."
	fi
}


# Main 'static text' content processing starts here, looping over Genus level, then species, and into production name if needing checked.
while read GENUS
do
	#Does genus dir exist
  	if [[ -d ${STATIC_REPO}/$GENUS ]]; then

                ## Genus is already present, next check for species and production name if needed
				echo -e -n "${ORANGE}[1] - Found pre-exisiting genus dir for $GENUS${NC}\n"

				#Increment counter of new genus
				((PREXISTING_GENUS_COUNTER=PREXISTING_GENUS_COUNTER+1))
				echo "$GENUS" >> ${NEW_STATIC_CONTENT}/$PREXISTING_GENUS_FILE

				## Now look to see if species dir exists
				grep -e "$GENUS" ${NEW_STATIC_CONTENT}/Species_List.txt > ${NEW_STATIC_CONTENT}/${GENUS}.species.tmp
				while read SP
				do
					if [[ -d ${STATIC_REPO}/${GENUS}/${SP} ]]; then
						# Species directory also found so need to check if the production name is present
						echo -e -n "\t${ORANGE}[2] - Found pre-exisiting species dir for $SP${NC}\n"

						# Now check if the same production name is found:
						BASE_PROD_NAME=`find ${NEW_STATIC_CONTENT}/${SP}/ -type f -name "*_about.md"`
						PROD_NAME=`basename $BASE_PROD_NAME _about.md`

						#Checking for exact production name
						if [[ -e ${STATIC_REPO}/${GENUS}/${SP}/${PROD_NAME}_about.md ]] || [[ -e ${STATIC_REPO}/${GENUS}/${SP}/${PROD_NAME}_assembly.md ]] || [[ -e ${STATIC_REPO}/${GENUS}/${SP}/${PROD_NAME}_annotation.md ]]; then

							#Increment counter of preexisiting sp
							((PREXISTING_SP_COUNTER=PREXISTING_SP_COUNTER+1))
							echo "$PROD_NAME" >> ${NEW_STATIC_CONTENT}/$PREXISTING_SP_FILE
							#break or ask user
							echo -e -n "\t${RED}[3] MD files with same 'species.production_name' present:${NC} $PROD_NAME ${RED}! MD files = [MANUAL CHECK NEEDED]${NC}\n"
						else

							#Increment counter of new assembly version for pre exisiting species
							((NEW_SP_ASM_COUNTER=NEW_SP_ASM_COUNTER+1))
							echo "$PROD_NAME" >> ${NEW_STATIC_CONTENT}/$NEW_SP_ASM_FILE
							cp -r ${NEW_STATIC_CONTENT}/${SP}/${PROD_NAME}* ${STATIC_REPO}/${GENUS}/${SP}/
							echo -e -n "\t${GREEN}[3] Production name:${NC} ${PROD_NAME}${GREEN} not found. MD files = [COPIED]${NC}\n"

						fi
					else
						# Not found, can now move new species dir to static-repo
						cp -r ${NEW_STATIC_CONTENT}/${SP} ${STATIC_REPO}/${GENUS}/

						#Increment counter of new species
						((NEW_SP_COUNTER=NEW_SP_COUNTER+1))
						echo "$SP" >> ${NEW_STATIC_CONTENT}/$NEW_SP_FILE
						echo -e -n "\t${GREEN}[2] Not found Species dir${NC}: $SP ${GREEN} Species = [COPIED]${NC}\n"

					fi
				done < ${NEW_STATIC_CONTENT}/${GENUS}.species.tmp
    else
            # Genus directory is unique and not already presenet in repo:
			echo -e -n "${GREEN}[1] No directory existis with name:${NC}\"$GENUS\"\n"

			#Increment counter of new genus
			echo "$GENUS" >> ${NEW_STATIC_CONTENT}/$NEW_GENUS_FILE

			mkdir -p ${STATIC_REPO}/${GENUS}/
			echo -e -n "\t${ORANGE}[2] Genus directory: ${NC}${GENUS}${ORANGE} = [CREATED]${NC}\n"

			grep -e "$GENUS" ${NEW_STATIC_CONTENT}/Species_List.txt > ${NEW_STATIC_CONTENT}/${GENUS}.species.tmp

			while read SP;
			do
				#Increment counter of new species
				((NEW_SP_COUNTER=NEW_SP_COUNTER+1))
				echo "$SP" >> ${NEW_STATIC_CONTENT}/$NEW_SP_FILE

				cp -r ${NEW_STATIC_CONTENT}/${SP} ${STATIC_REPO}/${GENUS}/

				echo -e -n "\t${GREEN}[3] Species directory: ${NC}${SP}${GREEN} = [COPIED]${NC}\n"	
			done < ${NEW_STATIC_CONTENT}/${GENUS}.species.tmp

    fi
        echo "------------------------------------------------"
done < ${NEW_STATIC_CONTENT}/Genus_list.txt

echo -e -n "\n^-^-^-^-^-^ Done processing MD files ^-^-^-^-^-^\n\n"

# Now we check for Source images and move accordingly
if [[ $STATIC_ONLY == "--images" ]] && [[ $NEW_STATIC_IMAGES ]]; then

	echo -e -n "-------------- Starting Images processing ensembl-static/$DIVISION/images/species -------------\n"
	cd $NEW_STATIC_IMAGES


	for IMAGE in *.png
	do
		UC_IMAGE=${IMAGE^}
		PROD_NAME_IMAGE=`basename $IMAGE .png`
		GENUS_IMAGE=`echo $PROD_NAME_IMAGE | cut -d "_" -f1`

		if [[ -d ${IMAGE_REPO}/$GENUS_IMAGE ]]; then
			echo -e -n "${GREEN}Dir for genus: $GENUS_IMAGE located.${NC}\n"
			cp $NEW_STATIC_IMAGES/$IMAGE ${IMAGE_REPO}/$GENUS_IMAGE/$UC_IMAGE
			echo -e -n "$IMAGE ${GREEN}[COPIED]${NC}\n---\n"
		else
			echo -e -n "${RED}Dir for genus: $GENUS_IMAGE not found.${NC}\n"
			mkdir -p ${IMAGE_REPO}/$GENUS_IMAGE
			echo -e -n "${ORANGE}Created genus directory.${NC}\n"
			cp $NEW_STATIC_IMAGES/$IMAGE ${IMAGE_REPO}/$GENUS_IMAGE/$UC_IMAGE
			echo -e -n "$IMAGE ${GREEN}[COPIED]${NC}\n---\n"
		fi
	done
	echo -e -n "^-^-^-^-^-^ Done processing static image files ^-^-^-^-^-^\n\n"
fi

## Block printing on various assignments/copies/creates made on input species dirs
echo -e -n "In total: $PREXISTING_GENUS_COUNTER pre-existing genus encountered\n"
print_species_bin $NEW_STATIC_CONTENT $PREXISTING_GENUS_FILE
echo ""

if [[ -e ${NEW_STATIC_CONTENT}/NewGenus.tmp ]]; then
	NEW_GENUS_COUNTER=`cat ${NEW_STATIC_CONTENT}/$NEW_GENUS_FILE | sort | uniq | wc -l`;
	else
		NEW_GENUS_COUNTER=0
	fi
	echo -e -n "In total: $NEW_GENUS_COUNTER new genus encountered (Changes made to repo!)\n"
	print_species_bin $NEW_STATIC_CONTENT $NEW_GENUS_FILE
	echo ""

echo -e -n "In total: $NEW_SP_COUNTER new species encountered (Changes made to repo!)\n"
print_species_bin $NEW_STATIC_CONTENT $NEW_SP_FILE
echo ""

echo -e -n "In total: $NEW_SP_ASM_COUNTER new assembly versions for exisiting species (Changes made to repo!)\n"
print_species_bin $NEW_STATIC_CONTENT $NEW_SP_ASM_FILE
echo ""

echo -e -n "In total: $PREXISTING_SP_COUNTER pre-existing species (No Changes made to repo!)\n"
print_species_bin $NEW_STATIC_CONTENT $PREXISTING_SP_FILE
echo ""

echo "Changes to repo:"
cd ${BASE_REPO}
git status
cd $CWD

rm ${NEW_STATIC_CONTENT}/Genus_list.txt
rm ${NEW_STATIC_CONTENT}/Species_List.txt
rm ${NEW_STATIC_CONTENT}/*.tmp

exit 0


