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

## Commnad line arguments
### First parameter -- [meta configuration file](../(docs/metaconf.md)
Always provide meta configuration file as the first option:
```
./ensembl-production-metazoa/scripts/mz_generic.sh ${METACONF_DIR}/<meta_conf_file>
```
You can use either:
 * abs-path
 * or relative to the dir you're running scripts fromi
 * or just name of the meta configuration file to be searched for in
  `./ensembl-production-metazoa/meta/${ENS_VERSION}` dir

### Second (optional) parameter
In addition to the meta conf paramete you can provide additional option, that controls the generic loader `scripts/mz_generic.sh` behaviour:
| Option | Description | Comments |
| - | - | - | 
| restore | restore from the latest back up | move `bup` symlink, if you need something older than the last saved
| pre_final_dc | run datachecks before patching to the new schema stage | active, only if the goal is reachable |
| finalise | create back up with the `final` tag |  active, only if the goal is reachable


## Ad-hoc environment setup
Sometimes there's a need to have Ensembl environment, that can be used by unrelated pipelines / workflows.
A [`lib.sh`](scripts/lib.sh) wrapper called `get_ensembl_prod` can be used for this task.

To setup environment
```
configs_dir=$(pwd)
cd $configs_dir

git clone git@github.com:Ensembl/ensembl-production-metazoa.git

# source _mz.conf file
# and/or 

ENS_VERSION=105

cat > get_env.sh << EOF
set -o errexit
set -o xtrace

source ${configs_dir}/ensembl-production-metazoa/scripts/lib.sh

get_ensembl_prod ${configs_dir}/ensembl.prod.${ENS_VERSION} $ENS_VERSION \
  ${configs_dir}/ensembl-production-metazoa/scripts/checkout_ensembl.20210208.sh \
  ${configs_dir}/ensembl-production-metazoa/scripts/legacy/create_setup_script.sh
EOF

bash get_env.sh

cd ${configs_dir}
ln -s ensembl.prod.${ENS_VERSION} ensembl.prod

# source environment settings
source ${configs_dir}/ensembl.prod.${ENS_VERSION}/setup.sh
```
