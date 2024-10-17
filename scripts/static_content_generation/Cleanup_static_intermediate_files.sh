#!/usr/bin/bash

## Quick script to remove intermediate static content files on a failed run or unwanted run

RUN_IDENTIFIER=$1

if [[ -z $RUN_IDENTIFIER ]]; then
    echo "Usage: sh Cleanup_static_intermediate_files.sh <Unique_Run_Identifier>"
    exit
fi

CWD=`readlink -f $PWD`

for CONTENT in StaticContent_Gen_${RUN_IDENTIFIER}*.log StaticContent_MD_Output-${RUN_IDENTIFIER} \
_static_stages_done_${RUN_IDENTIFIER} NCBI_DATASETS Without_Wikipedia_Summary_Content.txt WIKI_JSON_OUT \
generate_Wiki_JSON_Summary.sh Wikipedia_URL_listed.check.txt wiki_sp2image.tsv \
wiki_sp2image_NoMissing.tsv \
Download_species_image_from_url.sh; do
    if [[ -s $CWD/$CONTENT ]] || [[ -d $CWD/$CONTENT ]]; then
    echo "Removing: $CONTENT"
    rm -r $CWD/$CONTENT
    fi
done

exit 0
