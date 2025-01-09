# Ensembl Metazoa scripts for loading ad-hoc annotations

## Prerequisites
The whole thing is intended to be run inside the Ensembl production environment. It tries to get local copies of all the Ensembl repos it needs. Please, make sure you have all the proper credential, keys, etc. set up.

## Installation, sample configuration and run
Simple actions:
1. Getting  this repo
```
  git clone git@github.com:Ensembl/ensembl-production-metazoa.git
```

2. Creating (or copying and modifyingi example) meta configuration file (see below).
```
  ENS_VERSION=114
  mkdir -p ensembl-production-metazoa/meta/$ENS_VERSION
  cp ensembl-production-metazoa/meta/109_for_110/dmel ensembl-production-metazoa/meta/$ENS_VERSION
  # edit ensembl-production-metazoa/meta/$ENS_VERSION/dmel if needed
```
3. Choose/create path for data
```
  mkdir -p data
```

4. Run either locally (under either `tmux` or `screen`)
```
    ENS_VERSION=114 MZ_RELEASE=62 \
    CMD=<DB server alias to build at> \
    PROD_SERVER=<DB server alias to production server> \
      ./ensembl-production-metazoa/scripts/mz_generic.sh ensembl-production-metazoa/meta/105/dmel
```
  You'll see a lot of messages (shell trace mode is on by default) on the screen. Don't panic.

  Or with LSF (i.e. see ensembl-production-metazoa/meta/flybase.tmpl):

```
export PROD_SERVER=<DB server alias to production server>
export CMD=<DB server alias to build at>
# or source proper ensembl-production-metazoa/conf/_mz.conf file

export ENS_VERSION=114
export MZ_RELEASE=62
export LSF_QUEUE=<lsf_queue_name>
```
```
METACONF_DIR=ensembl-production-metazoa/meta/105

mkdir -p logs locks
ls -1 $METACONF_DIR/d* |
  perl -pe 's,.*/,,' |
  xargs -n 1 echo > sptags
```
```
cat sptags | grep -vF '#' | head -n 3 |
  xargs -n 1 echo |
  xargs -n 1 -I XXX -- sh -c \
    "sleep 10; \
     bsub -J load_XXX -q '$LSF_QUEUE' -M 32000 -R 'rusage[mem=32000]' -n 1 \
          -o logs/XXX.stdout -e logs/XXX.stderr \
          flock -n locks/XXX \
            ./ensembl-production-metazoa/scripts/mz_generic.sh ${METACONF_DIR}/XXX ; \
     sleep 7200"

# N.B. A second argument can be passed to/mz_generic.sh, i.e. one of the following:
#        restore pre_final_dc finalise
#      (see docs/mz_generic_params.md for the full list)
```

If running on LSF make sure that `ensembl.prod.${ENS_VERSION}/ensembl-hive` point to the LSF version:
```
pushd ensembl.prod.${ENS_VERSION}/ensembl-hive
rm ensembl-hive
ln -s ensembl-hive.lsf ensembl-hive
popd
```
(don't forget to switch back to the SLURM version `ensembl-hive.slurm` if you need to)

and seed your runs like this
```
SLURM_QUEUE=<slurm_partition_name>

cat sptags | grep -vF '#' | head -n 3 |
  xargs -n 1 echo |
  xargs -n 1 -I XXX -- sh -c \
    "sleep 1; \
     echo XXX; \
     sbatch -J load_XXX \
          --time=168:00:00 \
          -p '$SLURM_QUEUE' --mem 32G \
          --nodes=1 --ntasks=1 --cpus-per-task=1 \
          -o logs/XXX.stdout -e logs/XXX.stderr \
          --wrap='flock -n locks/XXX \
            ./ensembl-production-metazoa/scripts/mz_generic.sh ${METACONF_DIR}/XXX pre_final_dc'; \
     sleep 7200"
```


  If starting your runs like this you'll have to use `tail -f logs/*.stderr` or any other way to peek into logs.

  Instead of setting each environment variable to configure `mz_generic.sh` run,
   you can either create a copy and edit [`conf/_mz.conf`](conf/_mz.conf) specifying each parameter,
   or set a single variable with the path to the config `MZ_CONFIG=<path_to_conf_file>`
   (see ["Parameters for mz_genenic runner"](docs/mz_generic_params.md) for more details).

## While running
5.  If there is a pre-existing and loaded
  [Ensembl modular environmnent](https://github.com/Ensembl/ensembl-mod-env), `mz_generic.sh` will try to use that one (checking for existence of `MODENV_ROOT` env variable).

  If there's no modular environment loaded,
  the first time the process runs it tries to get all the needed Ensembl repos into
  `${SCRIPTS_DIR}/ensembl.prod.${ENS_VERSION}` directory (`SCRIPTS_DIR` is `pwd` by default).

  If you need to load environment used for building you can
  ```
  source ${SCRIPTS_DIR}/ensembl.prod.${ENS_VERSION}/setup.sh
  ```


6. When script runs it creates
  * `${DATA_DIR}/<meta_name>/bup` -- to store most recent core backup (usually, created after each stage by `backup_relink` wrapper)
  * `${DATA_DIR}/<meta_name>/done` --  each stage stores `_<done_tag>`  in this dir and checks if the tag exists before the run. Thus you can run the same command many times and only unfinished stage will be rerun (no automatic snapshot restoration is performed, see below)
  * `${DATA_DIR}/<meta_name>/data/raw` -- to store initially retrieved sequence and model data (i.e. FASTAs and GFF from GenBank). It's better to fetch it only once and preserve between reruns (thus try  not to delete `${DATA_DIR}/<meta_name>/done/_get_asm_ftp` file)
  * `${DATA_DIR}/<meta_name>/data/pipeline_out` -- to store logs/intermediate files for pipelines that are run. Usually, there's a `_continue_pipeline` file with instructions on how to connect to/ continue the pipeline
  * `${DATA_DIR}/<meta_name>/metadata` -- preprocessed metadata to be passed to the `run_new_loader` stage (`new-genome-loader` pipeline)

## If script stops
7. If anything fails script terminates by default.
  * You can either continue pipeline. Source `${SCRIPTS_DIR}/ensembl.prod.${ENS_VERSION}/setup.sh`, use the corresponding `_continue_pipeline` file. (Don't forget to finalise accomplished stage with corresponding `_done_tag` as written in the file).
  * Drop as many `${DATA_DIR}/<meta_name>/done` tags as you need (use `ls -lt` to sort tags by time). Drop as many `${DATA_DIR}/<meta_name>/bup` snapshots as you need (none, ideally) and don't forget to refresh the sym link to point to the latest good one.
  Run [`ensembl-production-metazoa/scripts/mz_generic.sh`](scripts/mz_generic.sh) with additional second command line option `restore`:
  ```
  ./ensembl-production-metazoa/scripts/mz_generic.sh ${METACONF_DIR}/<meta_conf_file> restore
  ```
  Now you can rerun the initial (without `restore`) build command once again.

8. Sometimes the script stops as planned.
In this case edit the raw metadata file by updating stats and metadata generation options (!N.B. tab separated lines, see below for details). I.e. for ensembl-production-metazoa/meta/109_for_110/dmel:
```
# stats and metadata generation options
#CONF   IGNORE_UNVALID_SOURCE_GFF       1
#CONF   STOP_AFTER_GFF_STATS    NO
#CONF   STOP_AFTER_CONF NO
```

## Meta configuration files
The whole process of creating core database is controlled by the meta configuration file.

### Format
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
#CONF	ASM_URL	ftp://ftp.flybase.net/genomes/Drosophila_melanogaster/dmel_r6.46_FB2022_03
#CONF	FNA_FILE	fasta/dmel-all-chromosome-r6.46.fasta.gz
```
* Anything else having a `#` sign is a comment (pay attention to the strain names, etc., as no quotation is implemented). I.e. `# CONF` is not longer a technical data, and thus ignored.

Further description can be found in the [Metaconf options document](docs/metaconf.md)


##  General processing flow
See related ["Metaconf"](docs/metaconf.md) documentation.
```
get_ensembl_prod ...
populate_dirs ...
```
```
get_asm_ftp ...
get_individual_files_to_asm ...
```
```
prepare_metada ...
#STOP_AFTER_CONF
```
```
run_new_loader ...
backup_relink ...
# restore && exit
```
```
# initial test, uncomment for the first run, if not sure
# run_core_stats_new && run_dc && exit 0
```

every step altering core database is followed (at least should be) by `backup_relink` further

```
fill_meta
```
Construction of repeat library and repeat masking
```
get_repbase_lib
construct_repeat_libraries
dump_translations
filter_repeat_library

run_repeat_masking
```
Running various pipelines if models (`GFF_FILE`) present
```
run_rna_features
run_rna_genes # if RUN_RNA_GENES

run_xref

update_stable_ids # if UPDATE_STABLE_IDS

set_core_random_samples SAMPLE_GENE # if no 'ample.location_param'
```
Final stats and synchronisation with the `ensembl_production`
```
run_core_stats_new
update_prod_tables_new
```
Finalization, comment out exit
```
patch_db_schema
run_dc
```


## Back up and restoration from snapshots

* `${DATA_DIR}/<meta_name>/bup` -- to store most recent core backup (usually, created after each stage by `backup_relink` wrapper)

`backup_relink $DBNAME $CMD new_loader $DATA_DIR/bup`

every step altering core database is followed (at least should be) by `backup_relink` further


### Restoration from snapshot {#restore}
* To restore from the latest backup just use the generic runner with the `restore` option
   (see ["Parameters for mz_genenic runner"](docs/mz_generic_params.md) for more details).
I.e.
```
./ensembl-production-metazoa/scripts/mz_generic.sh ${METACONF_DIR}/dmel restore
```

* To restore from the earlier dump, specify additional `tag_pattern` after the `restore` option, i.e.
```
./ensembl-production-metazoa/scripts/mz_generic.sh ${METACONF_DIR}/dmel restore core_stats
```
In this case, the back up file matching the specified `tag_pattern` will be used.
All the back up files that are fresher then the specified one will be droped.

Use `ls -lt ${DATA_DIR}/<meta_name>/bup` to list the available backup files.

N.B. Don't forget to drop as many `${DATA_DIR}/<meta_name>/done` tags as you need (use `ls -lt` to sort tags by time).


### Static Content generation

See related ["Static content"](docs/static_generation.md) documentation.
```
WikipediaREST_RefSeq_2_static_wrapper.sh ...
```

