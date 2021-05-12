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


dir=$1

if [ -z "$dir" ]; then
    echo "Usage: $0 <dir>" 1>&2
    exit 1
fi


dir=$(readlink -f $dir)

if [ ! -e "$dir" ]; then
    echo "Directory '$dir' does not exist" 1>&2
    exit 1
fi


## Used to find BioPerl
if [ -z "$EG_APIS" ]; then
    echo EG_APIS not defined. not possible to find bioperl libs. exiting...
    exit 1
fi



## BEGIN
cd $dir

# create a module file and shell script in parallel

echo -n > setup.sh
echo "#%Module1.0" > setup.module
echo 'module-whatis "enviromment for EnsEMBL databases"' >>setup.module

echo "setenv EG_APIS $EG_APIS" >> setup.module
echo "setenv ENSEMBL_ROOT_DIR $dir" >> setup.module
echo "setenv ENSEMBL_CVS_ROOT_DIR $dir" >> setup.module

echo "EG_APIS=$EG_APIS" >> setup.sh
echo "ENSEMBL_ROOT_DIR=$dir" >> setup.sh
echo "ENSEMBL_CVS_ROOT_DIR=$dir" >> setup.sh

echo "prepend-path PERL5LIB \$env(EG_APIS)/bioperl/ensembl-stable" >> setup.module
echo 'PERL5LIB=$EG_APIS/bioperl/ensembl-stable${PERL5LIB:+:$PERL5LIB}' >> setup.sh

for module in $(ls -d */); do
    # Get full path from relative
    module=$(readlink -f $dir/$module)

    # First add to PERL5LIB
    if [ -d $module/modules ]; then
      echo "prepend-path PERL5LIB $module/modules" >> setup.module
      echo "PERL5LIB=$module/modules:\$PERL5LIB" >> setup.sh
    fi
    if [ -d $module/lib ]; then
      echo "prepend-path PERL5LIB $module/lib" >> setup.module
      echo "PERL5LIB=$module/lib:\$PERL5LIB" >> setup.sh
    fi

    # Next, build up PATH
    if [ -d $module/bin ]; then
        echo "prepend-path PATH $module/bin" >> setup.module
        echo "PATH=$module/bin:\$PATH" >> setup.sh
    fi
    if [ -d $module/scripts ]; then
        echo "prepend-path PATH $module/scripts" >> setup.module
        echo "PATH=$module/scripts:\$PATH" >> setup.sh
    fi
done

echo "export PERL5LIB EG_APIS ENSEMBL_ROOT_DIR ENSEMBL_CVS_ROOT_DIR PATH" >> setup.sh

echo "To set up your environment run '. $dir/setup.sh' or 'module load $dir/setup.module'"
