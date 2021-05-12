# Parameters for [mz_genenic](scripts/mz_generic.sh) runner

The process flow is controlled by setting few variables.
The most accurate and uptodate list of them is in the [`conf/_mz.conf`](conf/_mz.conf) file.

There are few ways to specify these parameters.

* By using shell environment variables
* By placing (and editing) `_mz.conf` to the directory `mz_generic.sh` is run from,
* By specifying/setting a single shell variable `MZ_CONFIG=<path_to_conf_file>` with the patch to config file


## Parameters
| Parameter | Example | Description | Comment |
| - | - | - | - |
`MZ_CONFIG` | /path/to/_mz.conf | Paths to the config files with the listed below options, sourced by `mz_generic.sh`
`MZ_RELEASE` | 51 | EnsemblGenomes release version
`ENS_VERSION` | 104 | Ensembl (core db schema) release version
`CMD` | cmd_server_alias | SQL DB server alias, to create *core DB* at and put *e-hive* DBs for running pipelines
`PROD_SERVER` | prod_server_alias | Production SQL DB server alias to get `ensembl_production` and `ncbi_taxonomy` databases from | Should be exported within config file (`export PROD_SERVER`)
`EG_APIS` | /path/to/the/dir/with/bioperl_parents_parent_dir | Path to the BioPerl parent's parent directory to look for `bioperl/ensembl-stable`. In other words, the *BioPerl* library root should be `$EG_APIS/bioperl/ensembl-stable`. | Should be exported within config file (`export EG_APIS`).
`REPUTIL_PATH` | /path/to/repeatmasker/libexec/utildir' | Path where RepeatMasker utility script `queryRepeatDatabase.pl` is located. |  Should be exported within config file (`export REPUTIL_PATH`).

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
EG_APIS=/path/to/the/dir/with/bioperl_parents_parent_dir

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
```
