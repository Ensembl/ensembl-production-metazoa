#!/usr/bin/env perl
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

# Set colour functionality, allows single line color printing without using "reset"
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;

## A script to transfer the license info from Image_resource_gather.sh into static MD files.

my $infile = <temp_output_license.tsv>;
my $release = $ARGV[0];
my $CWD = $ARGV[1];
chomp $CWD;
my $release_dir = "StaticContent_MD_Output-${release}";

if(!open(INFILE,"<",$infile))
{
print "Missing inputfile: temp_output_license.tsv. Exiting\n";
exit 1;
}

open (INFILE, "<$infile");
while (<INFILE>){

    my $curr_line = $_;
    chomp $curr_line;
    my @split_line = split ("\t", $curr_line);

    my $sp_name = @split_line[0];
    $sp_name = ucfirst($sp_name);

    my $license_full = @split_line[1];
    my @array_split_sp_name = split ("_", $sp_name);
    my $binomial_sp = $array_split_sp_name[0]."_".$array_split_sp_name[1];
    $binomial_sp =~ s/_gca[0-9]+v[0-9][cm|fb|gb|rs|vb|wb]*.?//g;
    $binomial_sp = ucfirst($binomial_sp);    

    # Gather paths+files for new and original '_about' MD files
    my $dir_name = `find ./$release_dir -type d -name "$binomial_sp*" | awk -F "/" {'print \$NF'}`;
    chomp $dir_name;

    my $MD_about_file = $CWD."/".$release_dir."/${dir_name}/${sp_name}_about.md";
    my $MD_about_file_old = "${MD_about_file}.old";
    system("mv $MD_about_file $MD_about_file_old");

    my $temp_MD_about_file = "${CWD}/temp_about_file.md";
    open (ABOUT_FILE, "<$MD_about_file_old") || die "Can\'t open MD about file to parse\n";
    open (NEW_ABOUT_FILE, ">>temp_about_file.md") || "Can\'t open outfile\n";

    while (<ABOUT_FILE>){
        unless ($_ =~ m/^Picture credit/){
            print NEW_ABOUT_FILE $_;
        }
        else{
            print NEW_ABOUT_FILE "$license_full";
        }
    }
    close ABOUT_FILE;
    close NEW_ABOUT_FILE;

    system("mv $temp_MD_about_file $MD_about_file");
}

#Close input and remove the temporary license file
close INFILE;

system("rm ${CWD}/temp_output_license.tsv");
print "Looking for old MD files\n";
system("find ${CWD}/${release_dir}/ -type f -name \"*_about.md.old\" | xargs -n 1 -I XXX rm XXX");

print BRIGHT_GREEN "* Finished updating species *_about.md files <--> On Wiki Image licenses.\n\n";

exit 0;
