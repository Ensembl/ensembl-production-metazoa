#!/bin/sh --
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


## We use the script_dir variable to run a sister script below
script_dir=$(dirname $0)

URL_PFX="git@github.com:"
#URL_PFX="https://github.com/"

## The first option to the script is the location for "create_setup_script"
create_setup_script=$1
if [ -z "$create_setup_script" ]; then
    echo "Usage: $0 <create_setup_script> <dir> [branch]" >> /dev/stderr
    exit 1
fi

## The second option to the script is the location for the checkout
dir=$2
if [ -z "$dir" ]; then
    echo "Usage: $0 <create_setup_script> <dir> [branch]" >> /dev/stderr
    exit 1
fi

## The third option is the branch to use (main by default)
## Note, if branch doesn't exist, it falls back to main (typically)
branch="main"
if [ ! -z "$3" ]; then
    branch="$3"
fi

## We don't rename the remote from the default (origin) on clone, but
## I'm paranoid, so I'm open to the idea that it could change...
remote=origin


## BEGIN

dir=$(readlink -f $dir)
if [ ! -e "$dir" ]; then
    echo "Directory $dir does not exist - creating..." >> /dev/stderr
    mkdir -p $dir
fi

dir_full_path=$(readlink -f $dir)

echo "Creating Ensembl work directory in $dir ($dir_full_path)" >> /dev/stderr
echo >> /dev/stderr

cd $dir

[ -f _FAILED ] && rm _FAILED

## First checkout the Ensembl modules that follow the standard
## branching pattern...
for module in \
    ensembl \
    ensembl-io \
    ensembl-compara \
    ensembl-datacheck \
    ensembl-funcgen \
    ensembl-genomio \
    ensembl-metadata \
    ensembl-production \
    ensembl-rest \
    ensembl-tools \
    ensembl-variation \
    ensembl-vep \
    ensembl-orm \
  ;
do
    echo "Checking out $module ($branch)" >> /dev/stderr
    git clone -b $branch --depth 1 --no-single-branch ${URL_PFX}Ensembl/${module} || {
        echo "Could not check out $module ($branch)" >> /dev/stderr
        touch _FAILED
        exit 2
    }
    [ -f _FAILED ] && exit 2
    echo done >> /dev/stderr
    echo >> /dev/stderr
done



## Now checkout Hive

# slurm related bit
git clone -b version/2.6 --depth 1 --no-single-branch ${URL_PFX}Ensembl/ensembl-hive ensembl-hive.lsf

git clone -b version/2.8 --depth 1 --no-single-branch ${URL_PFX}Ensembl/ensembl-hive ensembl-hive.slurm

ln -s ensembl-hive.slurm ensembl-hive

echo "Point symlink '${dir_full_path}/ensembl-hive' to '${dir_full_path}/ensembl-hive.lsf' if you're on LSF" >> /dev/stderr



## Now checkout taxonomy (no release branch!)
branch="main"
for module in \
    ensembl-analysis \
    ensembl-anno \
    ensembl-taxonomy \
    ensembl-genes \
    ensembl-genes-nf \
    ensembl-killlist \
    core_meta_updates \
  ;
do
    echo "Checking out $module ($branch)" >> /dev/stderr
    git clone -b $branch ${URL_PFX}Ensembl/${module} || {
        echo "Could not check out $module ($branch)" >> /dev/stderr
        touch _FAILED
        exit 2
    }
    [ -f _FAILED ] && exit 2
    echo done >> /dev/stderr
    echo
done

## Now checkout ensemblgenomes-api (different URL)
branch="master"
for module in \
    ensemblgenomes-api
do
    echo "Checking out $module ($branch)" >> /dev/stderr
    git clone -b $branch ${URL_PFX}EnsemblGenomes/${module} || {
        echo "Could not check out $module ($branch)" >> /dev/stderr
        touch _FAILED
        exit 2
    }
    [ -f _FAILED ] && exit 2
    echo done >> /dev/stderr
    echo
done

# ATAC stuff
git clone ${URL_PFX}EnsemblGenomes/eg-assemblyconverter

# ensembl-production-metazoa  and ensembl-production-imported stuff
git clone git@github.com:Ensembl/ensembl-production-metazoa.git
git clone git@github.com:Ensembl/ensembl-production-imported.git

# private configs
git clone git@github.com:Ensembl/ensembl-production-imported-private.git || true

# prepare ensembl-genomio
echo "Building python3 venv" >> /dev/stderr

# pyenv local 3.11
python3.11 -m venv venv
source venv/bin/activate
pip3 install Cython

pip3 install -e './ensembl-genomio[cicd]'

# gene annotation related bits
pip3 install deepTools pyBigWig PyMySQL
pip3 install google-auth-oauthlib pyasn1-modules
pip3 install typing-extensions typed-ast chardet gspread
pip3 install pytz toml py retrying

echo "Adding perl deps" >> /dev/stderr
PL_ENV_VERSION=5.26.2
plenv local ${PL_ENV_VERSION}
mkdir -p ${dir}/perl5
cpanm --local-lib=${dir}/perl5 Text::Levenshtein::Damerau::XS
cpanm --local-lib=${dir}/perl5 DateTime::Format::ISO8601

# installing NextFlow
nf_dir=${dir_full_path}/nextflow
mkdir -p $nf_dir
export NXF_HOME=${nf_dir}/dot.nextflow
export NXF_SINGULARITY_NEW_PID_NAMESPACE=false
#   get nextflow and install almost like here: https://www.nextflow.io/index.html#GetStarted
wget -O - https://get.nextflow.io > ${nf_dir}/nextflow.install.bash
pushd $nf_dir
  cat ${nf_dir}/nextflow.install.bash |  bash 2>&1 | tee ${nf_dir}/nextflow.install.log
popd

# installing tkrzw
tkrzw_ver=1.0.32
tkrzw_url="https://dbmx.net/tkrzw/pkg/tkrzw-${tkrzw_ver}.tar.gz"
tkrzw_python_git_url="git+https://github.com/estraier/tkrzw-python"

wget "$tkrzw_url"
tar -zxf "tkrzw-${tkrzw_ver}.tar.gz"
TKRZW_DIR="${dir_full_path}"/"tkrzw-${tkrzw_ver}"
pushd "$TKRZW_DIR"
  ./configure --enable-zlib --enable-lzma --enable-zstd
  make
popd

export PATH="$PATH":"$TKRZW_DIR"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH":"$TKRZW_DIR"

LD_LIBRARY_PATH="$LD_LIBRARY_PATH":"$TKRZW_DIR" \
  LIBRARY_PATH="$TKRZW_DIR" \
  CPATH="$TKRZW_DIR" \
  pip3 install "$tkrzw_python_git_url"

python -c 'import tkrzw' || false

## Gasp!

echo "Checkout complete" >> /dev/stderr
echo "Creating a setup script" >> /dev/stderr

${create_setup_script} $dir

# adding plenv initialization
echo "plenv local ${PL_ENV_VERSION}" >> $dir/setup.sh.plenv
echo 'export PERL5LIB='${dir_full_path}'/perl5/lib/perl5:$PERL5LIB' >> $dir/setup.sh.plenv

# joining
cat $dir/setup.sh > $dir/setup.sh.orig
cat $dir/setup.sh.plenv $dir/setup.sh.orig > $dir/setup.sh

echo 'PERL5LIB='${dir_full_path}'/ensembl-variation/modules:$PERL5LIB' >> $dir/setup.sh
echo 'PATH='${dir_full_path}'/ensembl-variation/scripts:$PATH' >> $dir/setup.sh
echo 'export PERL5LIB=$PERL5LIB:'${dir_full_path}'/ensembl-variation/scripts/import' >> $dir/setup.sh

echo 'PERL5LIB='${dir_full_path}'/ensembl-datacheck/lib:$PERL5LIB' >> $dir/setup.sh
echo 'PATH='${dir_full_path}'/ensembl-datacheck/scripts:$PATH' >> $dir/setup.sh

# echo 'pyenv local 3.7.6' >> $dir/setup.sh
#echo 'pyenv deactivate' >> $dir/setup.sh
echo 'source '${dir_full_path}'/venv/bin/activate' >> $dir/setup.sh

echo 'export PYTHONPATH='${dir_full_path}'/ensembl-hive/wrappers/python3:$PYTHONPATH' >> $dir/setup.sh
echo 'export PERL5LIB='${dir_full_path}'/ensembl-genomio/src/perl:$PERL5LIB' >> $dir/setup.sh
# we use `pip install -e ` instead
# echo 'export PYTHONPATH='${dir_full_path}'/ensembl-genomio/src/python:$PYTHONPATH' >> $dir/setup.sh

echo 'export PERL5LIB='${dir_full_path}'/ensembl-production-imported/lib/perl:$PERL5LIB' >> $dir/setup.sh
echo 'export PYTHONPATH='${dir_full_path}'/ensembl-production-imported/lib/python:$PYTHONPATH' >> $dir/setup.sh

echo 'export PERL5LIB='${dir_full_path}'/ensembl-production-imported-private/lib/perl:$PERL5LIB' >> $dir/setup.sh
echo 'export PYTHONPATH='${dir_full_path}'/ensembl-production-imported-private/lib/python:$PYTHONPATH' >> $dir/setup.sh

echo '# nextflow bit' >> $dir/setup.sh
echo 'export NXF_HOME='${nf_dir}'/dot.nextflow' >> $dir/setup.sh
echo 'export NXF_SINGULARITY_NEW_PID_NAMESPACE=false' >> $dir/setup.sh
echo 'PATH='${nf_dir}':$PATH' >> $dir/setup.sh

echo '# tkrzw bit' >> $dir/setup.sh
echo 'export TKRZW_DIR='${TKRZW_DIR} >> $dir/setup.sh
echo 'PATH=$PATH:'${TKRZW_DIR} >> $dir/setup.sh
echo 'LD_LIBRARY_PATH=$LD_LIBRARY_PATH:'${TKRZW_DIR} >> $dir/setup.sh

echo '# gene annotation related bit' >>  $dir/setup.sh
echo 'PERL5LIB='${dir_full_path}'/ensembl-genes/lib:$PERL5LIB' >> $dir/setup.sh
echo 'PATH='${dir_full_path}'/ensembl-genes/bin:$PATH' >> $dir/setup.sh
echo 'PERL5LIB='${dir_full_path}'/ensembl-killlist/modules:$PERL5LIB' >> $dir/setup.sh
echo 'PATH='${dir_full_path}'/ensembl-killlist/bin:$PATH' >> $dir/setup.sh
echo 'PERL5LIB='${dir_full_path}'/ensembl-orm/modules:$PERL5LIB' >> $dir/setup.sh
echo 'PATH='${dir_full_path}'/ensembl-orm/bin:$PATH' >> $dir/setup.sh
echo 'export ENSCODE=$ENSEMBL_ROOT_DIR' >> $dir/setup.sh

echo 'export PERL5LIB ENSEMBL_ROOT_DIR ENSEMBL_CVS_ROOT_DIR PYTHONPATH LD_LIBRARY_PATH PATH' >> $dir/setup.sh


echo
echo "DONE!" >> /dev/stderr
