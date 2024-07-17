#!/usr/bin/bash

## Quick script to remove intermediate static content files on a failed run or unwanted run

CWD=`readlink -f $PWD`

for CONTENT in StaticContent_Gen_*.log _assembly.md _annotation.md _about.md StaticContent_MD_Output-* _static_stages_done_* NCBI_DATASETS Without_Wikipedia_Summary_Content.txt WIKI_JSON_OUT generate_Wiki_JSON_Summary.sh Wikipedia_URL_listed.check.txt wiki_sp2image.tsv wiki_sp2image_NoMissing.tsv Download_species_image_from_url.sh
do
echo "Removing: $CONTENT"
rm -r $CWD/$CONTENT
done

exit 0
