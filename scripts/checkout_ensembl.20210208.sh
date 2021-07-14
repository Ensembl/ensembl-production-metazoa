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
    echo "Usage: $0 <create_setup_script> <dir> [branch]" 1>&2
    exit 1
fi

## The second option to the script is the location for the checkout
dir=$2
if [ -z "$dir" ]; then
    echo "Usage: $0 <create_setup_script> <dir> [branch]" 1>&2
    exit 1
fi

## The third option is the branch to use (master by default)
## Note, if branch doesn't exist, it falls back to master (typically)
branch="master"
if [ ! -z "$3" ]; then
    branch="$3"
fi

## We don't rename the remote from the default (origin) on clone, but
## I'm paranoid, so I'm open to the idea that it could change...
remote=origin



## BEGIN

dir=$(readlink -f $dir)
if [ ! -e "$dir" ]; then
    echo "Directory $dir does not exist - creating..." 1>&2
    mkdir -p $dir
fi

echo "Creating Ensembl work directory in $dir"
echo

cd $dir



## First checkout the Ensembl modules that follow the standard
## branching pattern...
for module in \
    ensembl \
    ensembl-datacheck \
    ensembl-compara \
    ensembl-funcgen \
    ensembl-io \
    ensembl-metadata \
    ensembl-production \
    ensembl-rest \
    ensembl-tools \
    ensembl-variation \
    ensembl-vep
do
    echo "Checking out $module ($branch)"
    git clone -b $branch --depth 1 --no-single-branch ${URL_PFX}Ensembl/${module} || {
        echo "Could not check out $module ($branch)" 1>&2
        exit 2
    }
    echo
    echo
done



## Now checkout Hive
#branch="version/2.5"
branch="master"
for module in \
    ensembl-hive
do
    echo "Checking out $module ($branch)"
    git clone -b $branch --depth 1 --no-single-branch ${URL_PFX}Ensembl/${module} || {
        echo "Could not check out $module ($branch)" 1>&2
        exit 2
    }
    echo
    echo
done



## Now checkout taxonomy (no release branch!)
branch="master"
for module in \
    ensembl-taxonomy
do
    echo "Checking out $module ($branch)"
    git clone -b $branch ${URL_PFX}Ensembl/${module} || {
        echo "Could not check out $module ($branch)" 1>&2
        exit 2
    }
    echo
    echo
done

## Now checkout ensemblgenomes-api (different URL)
for module in \
    ensemblgenomes-api
do
    echo "Checking out $module ($branch)"
    git clone -b $branch ${URL_PFX}EnsemblGenomes/${module} || {
        echo "Could not check out $module ($branch)" 1>&2
        exit 2
    }
    echo
    echo
done

## Now checkout analysis (no release branch!) 
## getting dev/hive_master,
(
branch="dev/hive_master"
for module in \
    ensembl-analysis
do
    echo "Checking out $module ($branch)"
    git clone -b $branch --depth 1 --no-single-branch ${URL_PFX}Ensembl/${module} || {
        echo "Could not check out $module ($branch)" 1>&2
        exit 2
    }
    echo
    echo
done
)

# ATAC stuff
git clone ${URL_PFX}EnsemblGenomes/eg-assemblyconverter

# ensembl-production-metazoa  and ensembl-production-imported stuff
git clone git@github.com:Ensembl/ensembl-production-metazoa.git
git clone git@github.com:Ensembl/ensembl-production-imported.git

# private configs
git clone git@github.com:Ensembl/ensembl-production-imported-private.git || true

# grab new_genome_loader
git clone git@github.com:MatBarba/new_genome_loader.git new_genome_loader

echo "Building python3 venv"

pyenv local 3.7.6
python3.7 -m venv venv
source venv/bin/activate
pip3 install Cython
pip3 install -r new_genome_loader/requirements.txt


echo "Adding perl deps"
mkdir -p ${dir}/perl5
cpanm install --local-lib=${dir}/perl5 Text::Levenshtein::Damerau::XS


## Gasp!

echo "Checkout complete"
echo "Creating a setup script"

${create_setup_script} $dir

dir_full_path=$(readlink -f $dir)
echo 'PERL5LIB='${dir_full_path}'/ensembl-variation/modules:$PERL5LIB' >> $dir/setup.sh
echo 'PATH='${dir_full_path}'/ensembl-variation/scripts:$PATH' >> $dir/setup.sh
echo 'export PERL5LIB=$PERL5LIB:'${dir_full_path}'/ensembl-variation/scripts/import' >> $dir/setup.sh

echo 'PERL5LIB='${dir_full_path}'/ensembl-datacheck/lib:$PERL5LIB' >> $dir/setup.sh
echo 'PATH='${dir_full_path}'/ensembl-datacheck/scripts:$PATH' >> $dir/setup.sh

echo 'pyenv local 3.7.6' >> $dir/setup.sh
#echo 'pyenv deactivate' >> $dir/setup.sh
echo 'source '${dir_full_path}'/venv/bin/activate' >> $dir/setup.sh

echo 'export PERL5LIB='${dir_full_path}'/perl5/lib/perl5:$PERL5LIB' >> $dir/setup.sh

echo 'export PYTHONPATH='${dir_full_path}'/ensembl-hive/wrappers/python3:$PYTHONPATH' >> $dir/setup.sh
echo 'export PERL5LIB='${dir_full_path}'/new_genome_loader/lib/perl:$PERL5LIB' >> $dir/setup.sh
echo 'export PYTHONPATH='${dir_full_path}'/new_genome_loader/lib/python:$PYTHONPATH' >> $dir/setup.sh

echo 'export PERL5LIB='${dir_full_path}'/ensembl-production-imported/lib/perl:$PERL5LIB' >> $dir/setup.sh
echo 'export PYTHONPATH='${dir_full_path}'/ensembl-production-imported/lib/python:$PYTHONPATH' >> $dir/setup.sh

echo 'export PERL5LIB='${dir_full_path}'/ensembl-production-imported-private/lib/perl:$PERL5LIB' >> $dir/setup.sh
echo 'export PYTHONPATH='${dir_full_path}'/ensembl-production-imported-private/lib/python:$PYTHONPATH' >> $dir/setup.sh

echo 'export PERL5LIB ENSEMBL_ROOT_DIR ENSEMBL_CVS_ROOT_DIR PYTHONPATH PATH' >> $dir/setup.sh


echo
echo "DONE!"
