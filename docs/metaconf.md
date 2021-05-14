# Meta configuration files

The whole process of creating core database is controlled by the meta configuration file.

## Format
Few notations are used.
* Empty lines are ignored.
* One is just a plain text line of the form (tab-separated)
```
meta_key \t meta_value
```
to be loaded as is into core's `meta` table. I.e.
```
assembly.provider_name  FlyBase
assembly.provider_url   https://www.flybase.org
```
* Special technical metadata (options) lines starting with `#CONF` (no spaces after `#`) of the form (tab-separated)
```
#CONF \t CONF_OPTION_NAME \t CONF_OPTION_VALUE
```
. I.e.
```
#CONF   ASM_URL ftp://ftp.flybase.net/genomes/Drosophila_melanogaster/dmel_r6.37_FB2020_01
#CONF   FNA_FILE        fasta/dmel-all-chromosome-r6.37.fasta.gz
```
* Anything else having a `#` sign is a comment (pay attention to the strain names, etc., as no quotation is implemented). I.e. `# CONF` is not longer a technical data, and thus ignored.

## Metaconf options  
For the list of deprecated options see [Metaconf deprecated options](docs/metaconf_deprecated.md) doc.
Most frequently used options can be met in [meta/104/dmel](meta/104/dmel) example.

### Options related to the core db naming schema
Core DB names have structure like this
```
 <db_prefix>_species_bi(_tri)?nomial_core_<ens_version>_<mz_release>_<asm_version>
```
(i.e.`pre_drosophila_melanogaster_core_52_105_10`)

There are ways to set `<db_pfx>` and `<asm_version>` part of the name.

| Option | Example | Type: possible values | Action | Comment|
| - | - | - | -  | - |
`DB_PFX`	| premz	|	`str:` \w+, no `_`	| sets `<db_pfx>` part of the core DB name | cannot be emty
`ASM_VERSION` |	1 |	`int:` \d+ | sets `<asm_version>` part of the name |	|

To override bi(tri)nomial name use
`species.production_name` meta value (not an option, no `#CONF`) to redefine species name
(Only `alnum`s and `_` are allowed (`\w+`), should be trinomial maximum, having not more than 2 `_`).

`<ens_version>` and `<mz_release>` are controlled by `ENS_VERSION` and `MZ_RELEASE` of the environment (at the initialising stage, first run).


### Data retrieval (downloading, copying, etc) options
Data retrieved using `get_asm_ftp` and `get_individual_files_to_asm` wrappers ([lib.sh](scripts/lib.sh) functions).

| Option | Example | Type: possible values | Action | Comment|
| - | - | - | -  | - |
`ASM_URL` | [https://ftp.ncbi.nlm.nih.gov/.../GCA_011764245.1_ASM1176424v1](https://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/011/764/245/GCA_011764245.1_ASM1176424v1), [ftp://ftp.ncbi.nlm.nih.gov/.../GCA_002095265.1_B_xinjiang1.0](ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/002/095/265/GCA_002095265.1_B_xinjiang1.0), `/path/to/data/aatro` | `url`,`abs path`| Fetches directory into `data/raw/`, creates a `data/raw/asm` symlink | Should appear only once; `data/raw/asm` used as a root to put individual files feteched with `ASM_SINGLE` option and as a root dir for various `_FILE` options (see below)
`ASM_SINGLE` | [ftp://ftp.ncbi.nlm.nih.gov/.../GCA_000001215.4..._assembly_report.txt](ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/000/001/215/GCA_000001215.4_Release_6_plus_ISO1_MT/GCA_000001215.4_Release_6_plus_ISO1_MT_assembly_report.txt) | `url`,`abs path` | Fetches individual files into `data/raw/asm` | Can appear more than once in config file; data's stored in the directory fetched by `ASM_URL`
`FNA_FILE` | `fasta/dmel-all-chromosome-r6.37.fasta.gz`, `GCF_902806645.1_cgigas_uk_roslin_v1_genomic.fna.gz`, `/abs/path/to/canu4_A_alt.fa.gz` | `relative` (to `data/raw/asm` dir) or `abs path` | use as DNA sequence data file | If patsh is relative, `data/raw/asm` fetched by `ASM_URL` is used as a root
`GFF_FILE` | `gff/dmel-all-no-analysis-r6.37.gff.gz`, `GCA_002095265.1_B_xinjiang1.0_genomic.gff.gz`, `/abs/path/to/fixed.gff3.gz` | (optional) `relative` (to `data/raw/asm` dir) or `abs path` | use as GFF3 models data file | If path is relative, `data/raw/asm` fetched by `ASM_URL` is used as a root; if absent some stages are not run
`PEP_FILE` | `GCF_003254395.2_Amel_HAv3.1_protein.faa.gz` | `relative` (to `data/raw/asm` dir) or `abs path` | (optional) peptides sequence file, to compare Ensembl models with and create _seqedits_ from | If path is relative, `data/raw/asm` fetched by `ASM_URL` is used as a root. **N.B. sequence IDs should be same with the CDS IDs of the GFF3 file models**
`GBFF_FILE` | `GCA_000001215.4_Release_6_plus_ISO1_MT_genomic.gbff.gz` | `relative` (to `data/raw/asm` dir) or `abs path` | (optional) `GenBank` file to get assembly wide information from (taxon id, assembly name, etc.)| If path is relative, `data/raw/asm` fetched by `ASM_URL` is used as a root
`ASM_REP_FILE` | `GCA_000001215.4_Release_6_plus_ISO1_MT_assembly_report.txt` | `relative` (to `data/raw/asm` dir) or `abs path`  | (optional) GenBank `assembly report` file to get seq region synonyms and cellular components/locations from | If  path is relative, `data/raw/asm` fetched by `ASM_URL` is used as a root
`SR_GFF_FILE` | `GCA_000001215.4_Release_6_plus_ISO1_MT_genomic.gff.gz` | `relative` (to `data/raw/asm` dir) or `abs path`  | (optional) Additional GFF3 file with seq region information to be extracted from. I.e. used for D.melanogaster, as there are no region features with the information parsable in the FlyBase GFF3 | If path is relative, `data/raw/asm` fetched by `ASM_URL` is used as a root. Very specific usecase.

### Data preprocessing options
Options related to data preprocessing affect
`prepare_metada` [wrapper](scripts/lib.sh) and [`mz_generic.sh`](scripts/mz_generic.sh) early termination before running `run_new_loader` stage (see `STOP_AFTER_CONF` below).


#### GFF3 getting stats and fixing ([gff_stats.py](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/gff_stats.py)) options
| Option | Example | Type: possible values | Action | Comment|
| - | - | - | -  | - |
`GFF_STATS_CONF` | /abs/path/valid_structures.conf | `str:` empty, `abs path`, `rel path`(to [conf](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/conf) ) | Sets [gff_stats.py](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/gff_stats.py) `--conf ` option | [`valid_structures.conf`](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/conf/valid_structures.conf) is used by default
`GFF_STATS_OPTIONS`| --rule_options flybase | `str:` `options string` | Used as options passed to  [gff_stats.py](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/gff_stats.py) |


#### Prepare simplified GFF3 and JSON ([gff3_meta_parse.py](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/gff3_meta_parse.py)) options
| Option | Example | Type: possible values | Action | Comment|
| - | - | - | -  | - |
`GFF_PARSER_CONF` | [`gff_metaparser/flybase.conf`](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/conf/gff_metaparser/flybase.conf) |`abs path`, `rel path`(to [gff_metaparser/conf](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/conf))| Sets [gff3_meta_parse.py](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/gff3_meta_parse.py) `--conf` option | [`gff_metaparser.conf`](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/conf/gff_metaparser.conf) is used by default
`GFF_PARSER_CONF_PATCH` | [`gff_metaparser/ids2display.conf`](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/conf/gff_metaparser/ids2display.conf) [`gff_metaparser/xref2gene.patch`](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/conf/gff_metaparser/xref2gene.patch) | `NO`, empty, `abs path`, `rel path`(to [gff_metaparser/conf](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/conf))   |  Ignored, if `NO` or empty; otherwise sets [gff3_meta_parse.py](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/gff3_meta_parse.py) `--conf_patch` option | can be used to override some fractions of the configuration
`GFF_PARSER_PFX_TRIM` | NO | `NO`, (empty to use defaults), `trims string` | Sets [gff3_meta_parse.py](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/gff3_meta_parse.py) `--pfx_trims` option (trim prefixes from GFF3 features IDs) | `ANY!:.+\\\|;,ANY:id-,ANY:gene-,ANY:rna-,ANY:mrna-,cds:cds-,exon:exon-` by default
`GFF_PARSER_OPTIONS` | | `str:` `options string` | Used as options passed to  [gff3_meta_parse.py](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/gff3_meta_parse.py) |
`PEP_MODIFY_ID` | `s/^>([^\s]+)/>$1:cds/` , `s/^>([^\s]+)/>$1-Protein/` | `str:` `perl s/// expression`  | Perl `s///` expression to modify IDs (`>`) of the `PEP_FILE` (copy created) sequences to be used by [gff3_meta_parse.py](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/gff3_meta_parse.py)  (and sequentially, via manifest, by `run_new_loader`, see below) | For more complicated usecases better provide already *fixed* `PEP_FILE` (using `abs path`)

#### Ad-hoc seq region JSON generation ([gff3_meta_parse.py](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/gff3_meta_parse.py)) options
Same parser, different configs to generate seq_region.json from `SR_GFF_FILE` (see above).

| Option | Example | Type: possible values | Action | Comment|
| - | - | - | -  | - |
`SR_GFF_PARSER_CONF` | [`gff_metaparser/flybase.conf`](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/conf/gff_metaparser/flybase.conf) |`abs path`, `rel path`(to [gff_metaparser/conf](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/conf))| Sets [gff3_meta_parse.py](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/gff3_meta_parse.py) `--conf` option | [`gff_metaparser.conf`](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/conf/gff_metaparser.conf) is used by default
`SR_GFF_PARSER_CONF_PATCH` | [`gff_metaparser/regions_no_syns.patch`](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/conf/gff_metaparser/regions_no_syns.patch) | `NO`, empty, `abs path`, `rel path`(to [gff_metaparser/conf](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/conf))   |  Ignored, if `NO` or empty; otherwise sets [gff3_meta_parse.py](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/gff3_meta_parse.py) `--conf_patch` option | can be used to override some fractions of the configuration

#### Configuration generation ([gen_meta_conf.py](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/gen_meta_conf.py)) options
| Option | Example | Type: possible values | Action | Comment|
| - | - | - | -  | - |
`SEQ_REGION_SOURCE_DEFAULT` | GenBank |`str:` `external_db name`| Defines the name of the external database, seq_region synonyms were taken from ([gen_meta_conf.py](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/gen_meta_conf.py) `--syns_src` option) | Default: `GenBank`
`ORDERED_CS_TAG` | `chromosome` , `linkage_group` | `str:` `coord_system_tag` value | [`--cs_tag_for_ordered`](https://github.com/MatBarba/new_genome_loader/blob/master/lib/perl/Bio/EnsEMBL/Pipeline/PipeConfig/BRC4_genome_loader_conf.pm) option; [sets](https://github.com/MatBarba/new_genome_loader/blob/master/lib/python/ensembl/brc4/runnable/load_sequence_data.py) `coord_system_tag` for those seq_regions, which have their ids in `assembly.chromosome_display_order` list of the [`genome.json`](https://github.com/MatBarba/new_genome_loader/blob/master/schema/genome_schema.json) (`manifest.genome`) | `chromosome` by default
`CONTIG_CHR_(.*)` | `CONTIG_CHR_2L 2L` , `CONTIG_CHR_3 CM012072.1` , `CONTIG_CHR_X CM012070.1` (tab separated) | `(.*) suffix is alnum`, `str:` `sequence name` | Adds matched `$1` as a seq region synonym. If present, **only** the mentioned seq_regions are promoted to `ORDERED_CS_TAG` and a karyotype rank is given in the order of occurrence. | `$1` and `sequence name can be the same`. `$1 == MT` is a special case, see below.
`CONTIG_CHR_MT` | `CONTIG_CHR_MT mitochondrion_genome` (tab separated) | `str:` `sequence name` | Same as above and sets seq_region [`location`](https://github.com/MatBarba/new_genome_loader/blob/master/schema/seq_region_schema.json) to  `mitochondrial_chromosome` | Activates  `MT_CODON_TABLE` and `MT_CODON_TABLE` parsing.
`MT_CODON_TABLE`| 5 | `int` | [Sets](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/genmetaconf/seqregionconf.py) seq_region's [`codon_table`](https://github.com/MatBarba/new_genome_loader/blob/master/schema/seq_region_schema.json) | Parsed only if `CONTIG_CHR_MT` present.
`MT_CIRCULAR`| YES | `str:` `1`, `YES`, `TRUE` -- enabled, empty and everything else -- disabled| [Enables](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/genmetaconf/seqregionconf.py) seq_region `circular` [flag](https://github.com/MatBarba/new_genome_loader/blob/master/schema/seq_region_schema.json). | Parsed only if `CONTIG_CHR_MT` present

#### BRC4 related options
| Option | Example | Type: possible values | Action | Comment|
| - | - | - | -  | - |
`BRC4_LOAD` | NO | `str:` `NO`, empty, whatever | If empty or `NO` -- ignored, otherwise `--rule_options load_pseudogene_with_CDS` appended to `GFF_STATS_OPTIONS`; `GFF_PARSER_CONF_PATCH` initialized with [`gff_metaparser/brc4.patch`](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/conf/gff_metaparser/brc4.patch); `GFF3_LOAD_LOGIC_NAME` (see below) initialized with `gff3_genes` by default (can be overridden) | BRC4 perks

#### Premature termination options
| Option | Example | Type: possible values | Action | Comment|
| - | - | - | -  | - |
`IGNORE_UNVALID_SOURCE_GFF)` | NO | `str:` `NO`, empty, whatever | If empty or `NO` -- don't fail when `gt gff3validator` finds errors in the raw source GFF3 | rarely should be set to `YES`
`STOP_AFTER_GFF_STATS` | NO | `str:`  `NO`, empty, whatever | If empty or `NO` -- don't stop after GFF3 getting stats and fixing ([gff_stats.py](https://github.com/MatBarba/new_genome_loader/blob/master/scripts/gff_metaparser/gff_stats.py)) stage | better initialise with `YES` for the first run
`STOP_AFTER_CONF` | NO | `str:` `NO`, empty, anything else | 'NO' or empty -- not to stop, everything else -- stop after `prepare_metadata` stage even if there are no failures | better initialise with `YES` for the first run


### `run_new_loader` related options
For the genome loading itself we use [`new-genome-loader`](https://github.com/MatBarba/new_genome_loader) pipeline.
We use the `run_new_loader` [wrapper](scripts/lib.sh) to initialize and run the `new-genome-loader` pipeline.
Following options are passed onto the pipeline.

#### Analysis (logic) and source names
| Option | Example | Type: possible values | Action | Comment|
| - | - | - | -  | - |
`GFF3_LOAD_LOGIC_NAME` | flybase | `str:` `logic name` (from production.analysis_description table) | logic (_analysis_) name to use when loading models and xrefs; sets `--gff3_load_logic_name` and `--xref_load_logic_name` [pipeline options](https://github.com/MatBarba/new_genome_loader/blob/master/lib/perl/Bio/EnsEMBL/Pipeline/PipeConfig/BRC4_genome_loader_conf.pm) | `refseq_import_visible` by default; or `gff3_genes` by default for `BRC4_LOAD` case (can be overridden)
`GFF3_LOAD_SOURCE_NAME` | RefSeq | `str:` `external_db name` | source (external_db name) of the imported models; sets `--gff3_load_gene_source` [pipeline options](https://github.com/MatBarba/new_genome_loader/blob/master/lib/perl/Bio/EnsEMBL/Pipeline/PipeConfig/BRC4_genome_loader_conf.pm) | `Ensembl_Metazoa` by default
`GCF_TO_GCA`| 1 | `str:` empty, or anything | When non-empty, set `--swap_gcf_gca 1`  [pipeline options](https://github.com/MatBarba/new_genome_loader/blob/master/lib/perl/Bio/EnsEMBL/Pipeline/PipeConfig/BRC4_genome_loader_conf.pm). Pipeline starts to use _GenBank_ ids as the seq_region names. The original _RefSeq_ names are added as seq_region synonyms. Doesn't change `assembly.accession` prefix (in the core DB's meta table). |  Don't forget to override _assembly.accession_: `assembly.accession	GCA_003254395.2`, `#CONF	GCF_TO_GCA	1` (tab-separated)
`GFF_LOADER_OPTIONS` | `--check_manifest 0 --no_feature_version_defaults 1` | `str:` [loader pipeline](https://github.com/MatBarba/new_genome_loader/blob/master/lib/perl/Bio/EnsEMBL/Pipeline/PipeConfig/BRC4_genome_loader_conf.pm) options | options to be passed to the `new-genome-loader` | passed as is

By default, if not in the `BRC4_LOAD` mode, [`run_new_loader`](scripts/lib.sh) additionally adds the following options:
```
--load_pseudogene_with_CDS 0 --no_brc4_stuff 1 \
--ignore_final_stops 1 --xref_display_db_default Ensembl_Metazoa \
--no_feature_version_defaults 1 --skip_ensembl_xrefs 0
```
(see [new-new_genome_loader](https://github.com/MatBarba/new_genome_loader/blob/master/lib/perl/Bio/EnsEMBL/Pipeline/PipeConfig/BRC4_genome_loader_conf.pm) for options details).

When `BRC4_LOAD` is active, doesn't pass anything additional.

### Postprocessing options
The raw, uncommemted data from meta config file is loaded into the core's DB meta table (`meta_key`, `meta_value`, correspondingly).

| Option | Example | Type: possible values | Action | Comment|
| - | - | - | -  | - |
`TR_TRANS_SPLICED`| FBtr0084079,FBtr0084080 | `str`: `, separated` list of `transcipt stable ID`s, no spaces| Sets `trans_spliced` transcript  attrib using `mark_tr_trans_spliced` [`lib.sh`](scripts/lib.sh) wrapper |  Used only for the [D. melanogaster](meta/104/dmel) as for now
`UPDATE_STABLE_IDS` |	NO/1 | `str:` `NO` or empty -- don't update; anything else -- updated |  Try to infer valid stable IDs for genes and transcripts with [`update_stable_ids_from_xref.pl`](scripts/update_stable_ids_from_xref.pl). Uses *GeneID* xref to replace not-uniq ones (like, i.e., *TRNAM-CAU-5*). Trims ID's version (`STABLE_ID.V`) and stores it into the separate field | Stage is run after `run_xref`, only if `GFF_FILE` is present

### Repeat modelling / finding options
Options for `get_repbase_lib`, `construct_repeat_libraries`, `filter_repeat_library` and `run_repeat_masking`
wrappers from [lib.sh](script/lib.sh) used to construct de-novo repeat library, filter it and run repeat masking with it.

*Should be revised, as the new version of the [`RepeatModeler`](https://github.com/Ensembl/ensembl-production-imported/blob/trunk/lib/perl/Bio/EnsEMBL/EGPipeline/PipeConfig/RepeatModeler_conf.pm) pipeline appeared, which incorporates filtering against transcriptom and proteome and deals with the repbase slicing.*


| Option | Example | Type: possible values | Action | Comment|
| - | - | - | -  | - |
`REPBASE_SPECIES_NAME_RAW` | Tetranychus_urticae |`str:` `species name` (spaces or `_` allowed) | String to be used as `species name` to be used as `-species` parameter of the [`DNAFeatures`](https://github.com/Ensembl/ensembl-production-imported/blob/trunk/lib/perl/Bio/EnsEMBL/EGPipeline/PipeConfig/DNAFeatures_conf.pm) pipeline (called from `run_repeat_masking` wrapper), and get (with `get_repbase_lib`) corresponding slice of the RepBase library used by `filter_repeat_library` | The species scientific name is used by default
`DISABLE_REPBASE_NAME_UPCAST` |`NO`| `str:` `YES`, `1` -- to disable; everyting else -- to allow| If it's not possible to get RepBase slice for the inferred or provided `species name` (`REPBASE_SPECIES_NAME_RAW`) an attempts are made to get repeats using higher taxonomical levels (bottom to top) to get non-empty slice. When this option is on (`YES`, `1`) such behaviour is blocked.  | better not to disable
`REP_LIB` | `NO`, `/abs/path/to/final.rm.lib` | `str:` `NO` -- do nothing, empty -- run repeat modelling, `abs path` -- to use library provided  | If provided with `abs path` to the repeats library (fasta file), the later is used to `run_repeat_masking`. If empty -- logic for building de-novo library (`construct_repeat_libraries`) and its filtration(`filter_repeat_library`) is activated. If `NO` -- no custom library is used to `run_repeat_masking` (in addition to the standaert one)  | If provinding a library, better be sure, it's filtered against transcriptome (i.e. like [here](https://blaxter-lab-documentation.readthedocs.io/en/latest/filter-repeatmodeler-library.html))
`REP_LIB_RAW`| `/path/to/unfiletered.rm.lib` | `str:` `abs path`, empty | If non-empty -- no de-novo repeat construction is performed, and the provided libray is filtered against transcriptome. The resulting filtered variant will be used for `run_repeat_masking`. |  
`REPEAT_MODELER_OPTIONS` | `-min_slice_length 1000` , `-max_seq_length 19000000` | `str:` `options ` | Options to be passed to the [`RepeatModeler`](https://github.com/Ensembl/ensembl-production-imported/blob/trunk/lib/perl/Bio/EnsEMBL/EGPipeline/PipeConfig/RepeatModeler_conf.pm) pipeline called from [`construct_repeat_libraries`](scripts/lib.sh)
`REPBASE_FILTER`| NO | `str:` `NO` -- disable, empty and everything else -- enable | Disable filtering the de-novo repeat library | Better not to use, keep enabled
`REPBASE_FILE`| /path/to/curated.lib | `str: ` empty, `abs path` | If non-empty, the provided curated library is used imnstead of RepBase slice to filter proteome against. |
`IGNORE_EMPTY_REP_LIB`| 1 | `str:` empty or anything  | If empty and the inferred (produced by the previous steps) de-novo library is empty terminates execution. If non-empty -- execution is not terminated. | Better not to enable it for the first run as a sanity check measure.

### Various pipeline options
#### RNAFeatures and RNAGenes pipeline related options
Options for `run_rna_features` and `run_rna_genes` wrappers from [lib.sh](script/lib.sh).

| Option | Example | Type: possible values | Action | Comment|
| - | - | - | -  | - |
`RNA_FEAT_PARAMS` |  `-cmscan_threshold 1e-6 -taxonomic_lca 1` | `str:` `pipeline options` | Options to be forwarded to [`RNAFeatures`](https://github.com/Ensembl/ensembl-production-imported/blob/trunk/lib/perl/Bio/EnsEMBL/EGPipeline/PipeConfig/RNAFeatures_conf.pm) pipeline (called from `run_rna_features` wrapper). | Pipeline, not run if there's no `GFF_FILE`
`RUN_RNA_GENES` | NO | `str:` `NO` or empty -- don't run; anything else -- do run | Run [`RNAGenes`](https://github.com/Ensembl/ensembl-production-imported/blob/trunk/lib/perl/Bio/EnsEMBL/EGPipeline/PipeConfig/RNAGenes_conf.pm) pipeline (called from `run_rna_genes` wrapper) or not  | Better not to run, especially for the annotations with present RNA gene models (i.e. from *RefSeq*). If enabled, *species.stable_id_prefix* should present in meta data, i.e.:  `species.stable_id_prefix	ENSTCAL_` (tab-separated, no comments). Pipeline is not run if there's no `GFF_FILE` (no annotaion provided).
`RNA_GENE_PARAMS` | -run_context vb | `str:` `pipeline options` | Options to be forwarded to [`RNAGenes`](https://github.com/Ensembl/ensembl-production-imported/blob/trunk/lib/perl/Bio/EnsEMBL/EGPipeline/PipeConfig/RNAGenes_conf.pm) pipeline (called from `run_rna_genes` wrapper). | Better always to use `-run_context vb`

#### Xref pipeline related options
Options for `run_xref` wrapper from [lib.sh](script/lib.sh).

| Option | Example | Type: possible values | Action | Comment|
| - | - | - | -  | - |
`XREF_PARAMS` |  `-description_source reviewed -description_source unreviewed -gene_name_source reviewed` | `str:` `pipeline options` | Options to be forwarded to [`AllXref`](https://github.com/Ensembl/ensembl-production-imported/blob/trunk/lib/perl/Bio/EnsEMBL/EGPipeline/PipeConfig/AllXref_conf.pm) pipeline (called from `run_xref` wrapper). | Sometimes  `-overwrite_description 1` can be used. For dmel use `-refseq_dna -refseq_peptide 1 -refseq_tax_level invertebrate`. Pipeline is not run if there's no `GFF_FILE` (no annotaion provided).

#### Filling samle meta data options
If there's no `sample.location_param` meta data,
`set_core_random_samples` [wrapper](scripts/lib.sh) is run. If `sample.location_param` is not empty, all the needed sample data shoul be provided manually.

| Option | Example | Type: possible values | Action | Comment|
| - | - | - | -  | - |
`SAMPLE_GENE` | ACON029133 | `str`: `gene stable ID` | If not proviede or empty, sample gene is randomly picked. | Stage is not run if there's no `GFF_FILE` (no annotaion provided).   

## NB
*For the list of deprecated options see [Metaconf deprecated options](docs/metaconf_deprecated.md)*

*For the full list of the options and their meaning please grep `ensembl-production-metazoa/scripts/mz_generic.sh` and `ensembl-production-metazoa/scripts/lib.sh` for `get_meta_conf` wrapper.*