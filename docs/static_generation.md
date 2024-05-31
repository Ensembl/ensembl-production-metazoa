# Procedure for generation of static content [Ensembl Metazoa](https://metazoa.ensembl.org/index.html)

Generation of static content is handled via a single BASH wrapper script. This pipeline produces the full set of Ensembl static content for any genome CoreDB loaded from RefSeq or NCBI GenBank. 
      
- NB: Non RefSeq loaded cores: *May require some manual editing to their static `_annotation.md` files*

## Example run command:

```
>>> sh CoreList_To_StaticContent.sh \
<RunStage> \
<Input cores> \
<MYSQL Host> \
<Unique Run Identifier>

E.g. 
>>> sh CoreList_To_StaticContent.sh All CoreDB.list.txt staging-2 StaticContentE112
```

## Summary of processing performed:

Static content wrapper performs a number of processing stages:
- Download Wikipedia summary information, for each species input. [BASH]
- Download NCBI assembly and annotation summary files via NCBI datasets client. [BASH]
      - Implemented via Singularity and datasets-cli SIF image.
- Generation of static content *.md files (*_about.md, *_assembly.md, *_annotation.md.) [Perl] 
- Download species images and associated wikimedia common license information. [BASH, Perl]
- Generate formated list of species processed for **'whatsnew.md'**. See [ensembl-static](https://github.com/EnsemblGenomes/ensembl-static). [Bash]

## Format of input parameters:
In order to run the main static content wrapper to generate species markdown contents, image resources etc.
users must provide the following input parameters:

1. Run-stage option: 
      ['All', 'Wiki', 'NCBI', 'Static', 'Image', 'LicenseUsage', 'WhatsNew', 'Tidy'].
2. List of Input Core DBs: Flat text file listing one one core database per line.
3. Source MySQL server where cores are hosted: Typically staging host server.
4. Unique run identifier: (e.g. StaticContentE112).

### Input core(s) file contents:
```
crassostrea_gigas_core_53_107_1
stylophora_pistillata_gca002571385v1_core_53_107_1
```



## Summary of static wrapper output:

- StaticContent_MD_Output-* **(Dir)** 
    
        Main output directory containing all markdown .md static content. One sub directory per species.

- Log_Outputs_and_intermediates **(Dir)**

        Directory containing run log files, including auto generated scripts used in pulling information from Wikipedia and WikiCommons. 

- Source_Images_wikipedia **(Dir)**

        - Species image files obtained from Wikipedia. One per species, IF available. Image file name convention follows 'species.production_name'. 

        - Images will need subsampled, typically can be done using 'imagemagik'

- WIKI_JSON_OUT **(Dir)**

        Full JSON dumps from Wikipedia (page/summary/{title}). One JSON file per core_db processed.

- NCBI_DATASETS **(Dir)**

        NCBI RefSeq genome assembly reports obtained via 'datasets' client (.json), one per species

- Commons_Licenses **(Dir)**

        Full JSON dumps files of WikiMedia commons licensing meta information ([Commons: API/MediaWiki](https://commons.wikimedia.org/wiki/Commons:API/MediaWiki)).


## Log files and auto generated scripts:


**Log_Outputs_and_other_intermediates (DIR)**

- generate_Wiki_JSON_Summary.sh

        - wget commands that generated Wikipedia JSON files.

- Output_Image_Licenses.final.tsv

        Formatted TSV of WikiMedia Licensing meta information related to species images downloaded from Wikipedia.

- Wikipedia_URL_listed.check.txt

        Main wikipedia landing page URLs for each species. Useful for checking web content for that species.

- wiki_sp2image.tsv

        Intermediate output of all species image resource URLs.

- Without_Wikipedia_Summary_Content.txt

        List of all species found to be lacking Wikipedia summary info at time of processing.
        NB: In such cases, a template '_about.md' file is generated which needs to be manually processed to include species information.

- StaticContent_Gen_[*Pipeline_Run_Name*].log

        Summary log of static markdown file generation. Cat this file for log information formatted with colourised text.

- _static_stages_done_[*Pipeline_Run_Name*]

        Checkpoint file used to preventing rerunning of completed stages. Use this to control workflow if needed. 
        
## Helper Scripts:

- Automatic_Ensembl-Static_Update.sh
    
        A script to automatically update the Ensembl static content repository with static content files generated from the main wrapper above.
        Requires a forked repo of 'ensembl-static' and a specific release e.g. 'release/eg/60' 

- Generate_WIKI_Sp_ImagesFromText.sh

        - A script to retrieve species images and associated licening information from wikipedia. Accepts flat text file of wikipedia page title (One or more lines, one title per line).
E.g. Input: A flat text file containing the text 'Bumblebee' which will pull images from this [wikipedia page](https://en.wikipedia.org/wiki/Bumblebee)

