# Parameters for [mz_genenic](scripts/mz_generic.sh) runner

The process flow is controlled by setting few variables.
The most accurate and uptodate list of them is in the [`conf/_mz.conf`](conf/_mz.conf) file.

There are few ways to specify these parameters.

* By using shell environment variables
* By placing (and editing) `_mz.conf` to the directory `mz_generic.sh` is run from,
* By specifying/setting a single shell variable `MZ_CONFIG=<path_to_conf_file>` with the patch to config file


## Environmental  parameters (variables)
| Parameter | Example | Description | Comment |
| - | - | - | - |
`MZ_CONFIG` | /path/to/_mz.conf | Paths to the config files with the listed below options, sourced by `mz_generic.sh`
`MZ_RELEASE` | 51 | EnsemblGenomes release version
`ENS_VERSION` | 104 | Ensembl (core db schema) release version
`CMD` | cmd_server_alias | SQL DB server alias, to create *core DB* at and put *e-hive* DBs for running pipelines
`PROD_SERVER` | prod_server_alias | Production SQL DB server alias to get `ensembl_production` and `ncbi_taxonomy` databases from | Should be exported within config file (`export PROD_SERVER`)

## Usage and commnad line arguments

### First parameter -- [meta configuration file](../(docs/metaconf.md)
For most of the use cases the meta configuration file (meta-file) should be provide as the first option:
```
./ensembl-production-metazoa/scripts/mz_generic.sh ${METACONF_DIR}/<meta_conf_file>
```
You can use either:
 * abs-path
 * or relative to the dir you're running scripts fromi
 * or just name of the meta configuration file to be searched for in
  `./ensembl-production-metazoa/meta/${ENS_VERSION}` dir

I.e.
```
./ensembl-production-metazoa/scripts/mz_generic.sh ./ensembl-production-metazoa/meta/109_for_110/dmel
```

Though, you can use "help" and "env_setup_only" (see below) options instead of meta-file path on their own
```
./ensembl-production-metazoa/scripts/mz_generic.sh help
```



### Second (optional) parameter
In addition to the meta conf paramete you can provide additional option, that controls the generic loader `scripts/mz_generic.sh` behaviour:
| Option | Description | Comments |
| - | - | - | 
| `help` | print usage and exit | |
| `env_setup_only` | prepare environment and exit | |
| `restore [tag_pattern]` | restore from the latest back up, or from the one matching "tag\_pattern" | move `bup` symlink, if you need something older than the last saved; when pattern is used, back-ups that followed the macthing are removed (drops everything fresher then the one it's restoring from). N.B. as many `${DATA_DIR}/<meta_name>/done` tags as you need (use `ls -lt` to sort tags by time). |
| `stop_after_conf` | get data, validate, prepare cofiguration for the loader and stop | |
| `stop_after_load` | stop after the loader pipeline before running anything else | |
| `stop_before_xref` | stop before running xref helper | |
| `pre_final_dc` | run datachecks before patching to the new schema stage | active, only if the goal is reachable |
| `finalise` | create back up with the `final` tag |  active, only if the goal is reachable |
| `patch_schema` | patch schema to the latest available | | 


## Ad-hoc environment setup
Sometimes there's a need to have Ensembl environment, that can be used by unrelated pipelines / workflows.


To setup environment
```
configs_dir=$(pwd)
cd $configs_dir

git clone git@github.com:Ensembl/ensembl-production-metazoa.git

# source ensembl-production-metazoa/conf/_mz.conf file
# or 
export PROD_SERVER=<prod_server_alias>

export ENS_VERSION=107

# setup environment (you should have proper github keys/permissions in place)
./ensembl-production-metazoa/scripts/mz_generic.sh env_setup_only 2>&1 | tee env_setup.log

cd ${configs_dir}
ln -s ensembl.prod.${ENS_VERSION} ensembl.prod

# source environment settings
source ${configs_dir}/ensembl.prod.${ENS_VERSION}/setup.sh
```
