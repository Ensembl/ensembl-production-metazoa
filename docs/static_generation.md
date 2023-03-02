# Procedure for generation of static content [Ensembl Metazoa](https://metazoa.ensembl.org/index.html)

Generation of static content is handled via a single BASH wrapper script.

```
sh WikipediaREST_RefSeq_2_static_wrapper.sh \
<RunStage> \
<Input cores> \
<RefSeq/Genbank FTP urls> \
<MYSQL Host> \
<Unique Run Identifier>
```

## Summary of processing performed:

Static wrapper script manages running a number of procesing stages including:
- Downloading Wikipedia summary information, for each species input. [BASH]
- Downloading NCBI assembly and annotation summary files. [BASH]
- Generation of static content .md files. Generate *_about.md, *_assembly.md, *_annotation.md. [Perl] 
- Download species image(s) and associated wikimedia common license information. [BASH, Perl]
- Generate formated list of species processed for **'whatsnew.md'**. See [ensembl-static](https://github.com/EnsemblGenomes/ensembl-static). [Bash]

## Format of input parameters:
In order to run the main static content wrapper to generate species markdown contents, image resources etc.
users must provide the following input parameters:

1. Run-stage option: 
      ['All', 'Wiki', 'NCBI', 'Static', 'Image', 'WhatsNew', 'Tidy'].
2. List of Input Core DBs: Flat textfile listing one one core database name per line.
3. List of species associated RefSeq/Genbank FTP url: Flat textfile listing RefSeq/Genbank ftp URL(s) one per line.
4. Source MySQL server where cores are hosted: Typically staging host server.
5. Unique run identifier: (e.g. RunE107).

### Input core(s) file contents:
```
crassostrea_gigas_core_53_107_1
stylophora_pistillata_gca002571385v1_core_53_107_1
```

### RefSeq | Genbank FTP url(s) file contents:
```
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/902/806/645/GCF_902806645.1_cgigas_uk_roslin_v1
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/002/571/385/GCF_002571385.1_Stylophora_pistillata_v1
```

## Summary of static wrapper output:

- StaticContent_MD_Output-* **(Dir)** 
```
Main output directory containing all markdown .md static content. One sub directory per species.
```
- Output_Image_Licenses.final.tsv
```
Formatted TSV of WikiMedia Licensing meta information related to species images downloaded from Wikipedia.
```
- Source_Images_wikipedia **(Dir)**
```
Species image files obtained from Wikipedia. One per species - !If Available!
```
- WIKI_JSON_OUT **(Dir)**
```
Full JSON dumps from Wikipedia (page/summary/{title}). One JSON file per core_db processed.
```
- RefSeq_Assembly_Reports **(Dir)**
```
NCBI-RefSeq genome assembly reports (.txt), one per species
```
- RefSeq_Annotation_Reports **(Dir)**
```
NCBI Ref-Seq genome annotation reports (.txt), one per species
```
- Commons_Licenses **(Dir)**
```
Full JSON dumps files of WikiMedia commons licensing meta information ([Commons: API/MediaWiki](https://commons.wikimedia.org/wiki/Commons:API/MediaWiki)).
```

### Other log and intermediate files generated:

**Log_Outputs_and_other_intermediates (DIR)**

- generate_Wiki_JSON_Summary.sh
```
wget commands that generated Wikipedia JSON files.
```
- Wikipedia_URL_listed.check.txt
```
Main wikipedia landing page URLs for each species. Useful for checking web content for that species.
```
- wiki_sp2image.tsv
```
Intermediate output of all species image resource URLs.
```
- Without_Wikipedia_Summary_Content.txt
```
List of all species found to be lacking Wikipedia summary info at time of processing.
NB: In such cases, a template '_about.md' file is generated which needs to be manually processed to include species information.
```
- StaticContent_Gen_*.log
```
Summary log of static markdown file generation. Cat this file for log information formatted with colourised text.
```
- *_checkDone **(DIR)**
```
Stage processing check, stops specific stage processing if preceeding stage wasn't completed.
```
