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

#!/usr/bin/perl

use strict;
use warnings;

# This script will input a set of refseq annotation summary files, and use the information in them to capture the 
# JSON output (already scraped from wiki) and combine the two into a single set of species specific static content
# markdown files

use JSON;
use Data::Dumper;
use Text::Wrap;
use Term::ANSIColor qw(:constants);

# Set colour functionality, allows single line color printing without using "reset"
$Term::ANSIColor::AUTORESET = 1;

## Get dir inforatmion
my $wiki_input_dir = $ARGV[0];
my $genome_report_dir = $ARGV[1];
my $species_cores_listed = $ARGV[2];
my $core_host = $ARGV[3];
my $release = $ARGV[4];
my $safe_division = $ARGV[5];

die "USAGE: Generate_StaticConten_MD.pl <WIKI_JSON_DIR> <NCBI_GENOME_REPORT_DIR> <List_Ensembl_CORE_FILE> <Core(s) Host> <Run_Identifier> <Ensembl Division>\n" unless (@ARGV==6);

my @input_genome_reports = <${genome_report_dir}/*.genomereport.json>;

# Convert machine to lit form of division name
$safe_division =~ tr/_/ /;
my $ens_division = $safe_division;
my $division_url;

if ($safe_division =~ m/[Pp]lants/){
	print "Division is $ens_division\n";
	print "Setting url to plants.ensembl.org\n";
	$division_url = "https://plants.ensembl.org/info/genome/annotation/index.html"
   }
elsif ($safe_division =~ m/[Ff]ungi/){
	print "Division is $ens_division\n";
	print "Setting url to fungi.ensembl.org\n";
        $division_url =	"https://fungi.ensembl.org/info/genome/annotation/index.html"
   }
elsif ($safe_division =~ m/[Bb]ateria/){
        print "Division is $ens_division\n";
        print "Setting url to bacteria.ensembl.org\n";
        $division_url = "https://bacteria.ensembl.org/info/genome/annotation/index.html"
   }
elsif ($safe_division =~ m/[Pp]rotists/){
        print "Division is $ens_division\n";
        print "Setting url to protists.ensembl.org\n";
        $division_url = "https://protists.ensembl.org/info/genome/annotation/index.html"
   }
elsif ($safe_division =~ m/[Mm]etazoa/){
        print "Division is $ens_division\n";
        print "Setting url to metazoa.ensembl.org\n";
        $division_url = "https://metazoa.ensembl.org/info/genome/annotation/index.html"
   }
else{
	print "Division default to ensembl\n";
        print "Setting url to ensembl.org\n";
	$division_url = "https://www.ensembl.org/info/genome/genebuild/index.html"
}



## For each genome report file, locate and combine its assoicated Wilipedia JSON summary file on GCF/GCA accession
system ("mkdir -p ./StaticContent_MD_Output-${release}");

print BLUE "\nParsing JSON/Refseq files\n\n";

foreach my $genome_sum_file (@input_genome_reports){

	print DARK GREEN "Beginning processing RefSeq annotation:\n[$genome_sum_file] genome JSON\n";

	#Species specific static content folder
	my $static_output_folder = "StaticContent_MD_Output-${release}";	
	
	## Control flow and other control variables
	my $has_wiki_json_data=0;
	my $wrap_at = 70; #Length of each paragraph line printed.
	my $wiki_about;

	#per core global vars
	my ($scientific_name, $extract, $jpg_source, $wiki_url, $about_content, $refseq_annotation_content, $community_anno_content, $dtol_community_anno_content, $assembly_content);
	
	# Genome annotation report variables
	my ($species_name, $common_name, $taxa_id, $anno_report_url, $asseb_accession, $release_version, @ncbi_rel, $annotation_source, $assembly_submitter);

	# Convert GCF to GCA and locate its wiki JSON file
	my ($refseq_file, $gca_accession, $core_prodname_gca, $gca_accession_escape, $core_located);

	## Parse species name from ref_seq annotion
	$species_name = `jq '.organism.organism_name' $genome_sum_file | sed 's/"//g'`;
	chomp $species_name;
        print "Retrived organismal name from genome JSON file: $species_name\n";

	$scientific_name = $species_name;
	$species_name =~ tr/ /_/;
	my @temp_split_sp_name = split ("_", $species_name);
	my $count_sp_name = scalar @temp_split_sp_name;

	#Check whether or not the species name is bionomial or trinomial

	if (($count_sp_name > 3 )){
		print YELLOW "!!! Genome JSON contains atypical/long 'organism_name' [$count_sp_name sub names] !!! --> Utilizing just the bionomial: ";
               $species_name = "$temp_split_sp_name[0]_$temp_split_sp_name[1]";
               print "\"Species name set as: $species_name\"\n";
	}
	elsif (($count_sp_name == 3 )){
               print YELLOW "!!! Organismal species name is trinomial --> Utilizing just the bionomial: ";
               $species_name = "$temp_split_sp_name[0]_$temp_split_sp_name[1]";

               print "\"Species name set as: $species_name\"\n";
	}
	else{
		print "Organismal species name is binomial....";
		print "Species name set as: \"$scientific_name\".\n";
	}

        $static_output_folder = $static_output_folder."/".$species_name;
	$species_name = lc$species_name;
	system ("mkdir -p ./$static_output_folder");

	# Obtained common name and taxon_id information from genome report file
	$common_name = `jq '.organism.common_name' $genome_sum_file | sed 's/"//g'`;
	chomp $common_name;
	$taxa_id = `jq '.organism.tax_id' $genome_sum_file`;
	chomp $taxa_id;

	# Try to obtain NCBI refseq release URL, this will only be populated if there is an associated RefSeq annotation
	# If not, likely the genome is community annotated instead i.e. GFF3 submitted with assembly to Genbank.
	$anno_report_url = `jq '.annotation_info.report_url' $genome_sum_file | sed 's/"//g'`;
	chomp $anno_report_url;

	# Import check whether or not the assembly is linked to DToL:
	my $dtol_linked = 0;
	my $sanger_assembly = 0;
	my $dtol_project_acc = "PRJEB40665"; # https://www.ncbi.nlm.nih.gov/bioproject/PRJEB40665/
	$assembly_submitter = `jq '.assembly_info.submitter' $genome_sum_file`;
	chomp $assembly_submitter;
	my $bioproject=`cat $genome_sum_file | jq '.assembly_info.bioproject_lineage' | jq '.[]' | jq '.bioprojects' | jq '.[] | select(.accession=="$dtol_project_acc")' | jq '.title' | sed 's/"//g'`;

	if (( $assembly_submitter =~ "WELLCOME SANGER INSTITUTE") && ( $bioproject =~ "Darwin Tree of Life Project" ) ) {

		$dtol_linked=1;
		$annotation_source = "DToL";
		# cat $genome_sum_file | jq '.assembly_info.bioproject_lineage' | jq '.[]' | jq '.bioprojects' | jq '.[] | select(.accession=="PRJEB40665")' | jq '.title' | sed 's/"//g'
		# Darwin Tree of Life Project: Genome Data and Assemblies
		# jq '.assembly_info.submitter' => "WELLCOME SANGER INSTITUTE"
	}
	elsif (( $assembly_submitter =~ "WELLCOME SANGER INSTITUTE") && ( $bioproject !~ "Darwin Tree of Life Project" ) ) {
		$sanger_assembly=1;
	}

	# Assess if we are dealing with normal refseq, or community annotated genome
	if ( ( $anno_report_url !~ "null") && ( $dtol_linked eq 0 ) ){
		@ncbi_rel = split ("/",$anno_report_url);
		$release_version = $ncbi_rel[-1];
		$annotation_source = "refseq";
	}
	elsif( ( $anno_report_url =~ "null") && ( $dtol_linked eq 0 ) ){

		if( $sanger_assembly eq 1 ){
			$annotation_source = "community_sanger";	
		}
		else{
			$annotation_source = "community_annotation";
		}
	}
	
	$asseb_accession = `jq '.accession' $genome_sum_file | sed 's/"//g'`;
	chomp $asseb_accession;
    	$gca_accession = $asseb_accession;
    	$gca_accession =~ s/GCF_/GCA_/;
    	$gca_accession_escape = $gca_accession;
    	$gca_accession_escape =~ s/GCA_/GCA\\_/;
	chomp $gca_accession_escape;

    	$core_prodname_gca = $gca_accession;
    	$core_prodname_gca =~ s/GCA_/gca/;
    	$core_prodname_gca =~ s/\.[0-9]$//;
    	chomp $core_prodname_gca;
    	$core_prodname_gca = "${species_name}_${core_prodname_gca}";

	#Attempt to locate the correct core DB which corresponds to the appropriate genome JSON.

	my $species_core;
	my $species_core_count = `grep -c -E "^${species_name}_core_[0-9]{2}_[0-9]{3}_[0-9]{1}" < $species_cores_listed\n`;
	my $species_gca_core_count = `grep -c -E "^${core_prodname_gca}_core_[0-9]{2}_[0-9]{3}_[0-9]{1}" < $species_cores_listed\n`;
	my $species_trinomial_core_count = `grep -c -E "^${species_name}_[A-Za-z0-9]+_core_[0-9]{2}_[0-9]{3}_[0-9]{1}" < $species_cores_listed\n`;

	if ($species_core_count == 1){
		print GREEN "Core database located solely on binomial style db name.\n";
		$species_core = `grep -e "^${species_name}" < $species_cores_listed\n`;
                $core_located =	1;
	} 
	elsif($species_gca_core_count == 1){
		print GREEN "Core database located on binomial + gca suffic style db name.\n";
		$species_core = `grep -e "^${core_prodname_gca}" < $species_cores_listed\n`;
                $core_located =	1;
	}
	elsif($species_trinomial_core_count == 1){
             	print GREEN "Core database located on trinaomal style db name.\n";
		$species_core = `grep -E "^${species_name}_[A-Za-z0-9]+_core_[0-9]{2}_[0-9]{3}_[0-9]{1}" < $species_cores_listed\n`;
		$core_located = 1;
	}
        else{
		print RED "Unable to match core database nam in provided list to NCBI genome JSON (organism_name) for species $species_name. Exiting....";
		exit;
	}

	#Find the coreDB from the input core list file. Then locate the appropriate JSON file to parse. 
	my ($json_file_name, $json_file_path);

	#Test if core was found based on inclusion of GCA_ in the database name
	if ($core_located == 1){
		chomp $species_core;
		print "Core database located: $species_core\n";
		$json_file_name = "${species_core}.wiki.json";
		print "CHECKING -> ${wiki_input_dir}/${json_file_name}";
		$json_file_path = `ls -1 ${wiki_input_dir}/${json_file_name}`;
		print "FULL JSON PATH ->> $json_file_path";
		chomp $json_file_path;
	}

	#Perform query to obtain production name from to ensure static md will match with ensembl core DB
	my $prod_name=`$core_host -D $species_core -Ne \"SELECT meta_value FROM meta WHERE meta_key = 'species.production_name';"`;
	chomp $prod_name;
        print "Linked with Ensembl CORE_DB [$species_core] & species.production_name [$prod_name]\n";
	$prod_name = ucfirst($prod_name);

	##Open file handles using species.productioin_name to write markdown .md files.
	open (OUT_ABOUT, ">${prod_name}_about.md") || die "Can\'t open ${prod_name}_about.md\n";
	open (OUT_ANNO, ">${prod_name}_annotation.md") || die "Can\'t open ${prod_name}_annotation.md\n";
	open (OUT_ASM, ">${prod_name}_assembly.md") || die "Can\'t open ${prod_name}_assembly.md\n";
 
	# printf "The species %s, otherwise known as the %s.\nTaxon_id=%d\nWas obtained with annotation from %s\nWhich is associated with acc:%s\n", $species_name, $common_name, $taxa_id, $anno_report_url, $asseb_accession;

	## Parse specifc assembly statistics from asm file
	my ($total_asm_len, $scaffold_count, $scaf_N50, $scaf_L50, $contig_count, $cont_N50, $cont_L50, $gc_perc);
	$total_asm_len = `jq '.assembly_stats.total_sequence_length' $genome_sum_file | sed 's/"//g'`;
	$scaffold_count = `jq '.assembly_stats.number_of_scaffolds' $genome_sum_file`;
	chomp ($scaffold_count, $total_asm_len);

	#Check if scaffolds are accounted for or contigs
	if ($scaffold_count eq "null"){

		# print "!!!!!!!!!Entered Contig section !!!!!!!!!!!!!!\n";
		$contig_count = `jq '.assembly_stats.number_of_component_sequences' $genome_sum_file`;
		$cont_N50 = `jq '.assembly_stats.contig_n50' $genome_sum_file`;
		$cont_L50 = `jq '.assembly_stats.contig_l50' $genome_sum_file`;
		$gc_perc = `jq '.assembly_stats.gc_percent' < $genome_sum_file`;

		chomp ($contig_count, $cont_N50, $cont_L50, $gc_perc);

		if (!$gc_perc){
			# $gc_perc="0.0";
			## Print out the assembly summary infortmation without mentioning the absent asm GC%
			printf OUT_ASM "**Assembly**\n--------\n\nThe assembly presented here has been imported from [INSDC](http:\/\/www.insdc.org) and is linked to the assembly accession \[[%s](http:\/\/www.ebi.ac.uk\/ena\/data\/view\/%s)].\n\nThe total length of the assembly is %d bp contained withinin %d contigs.\nThe contig N50 value is %d, the contig L50 value is %d.\n",$gca_accession_escape, $gca_accession, $total_asm_len, $contig_count, $cont_N50, $cont_L50;

		}
		else{
			## Print out the assembly summary infortmation without mentioning the absent asm GC%
			printf OUT_ASM "**Assembly**\n--------\n\nThe assembly presented here has been imported from [INSDC](http:\/\/www.insdc.org) and is linked to the assembly accession [[%s](http:\/\/www.ebi.ac.uk\/ena\/data\/view\/%s)].\n\nThe total length of the assembly is %d bp contained withinin %d contigs.\nThe contig N50 value is %d, the contig L50 value is %d.\nThe GC%% content of the assembly is %.1f%%.\n",$gca_accession_escape, $gca_accession, $total_asm_len, $contig_count, $cont_N50, $cont_L50, $gc_perc;
		}
	}
	else{
		
		$scaf_N50 = `jq '.assembly_stats.scaffold_n50' $genome_sum_file`;
		$scaf_L50 = `jq '.assembly_stats.scaffold_l50' $genome_sum_file`;
		$gc_perc = `jq '.assembly_stats.gc_percent' $genome_sum_file`;

		chomp ($scaf_N50, $scaf_L50, $gc_perc);

		if (!$gc_perc){
			# $gc_perc="0.0";
			printf OUT_ASM "**Assembly**\n--------\n\nThe assembly presented here has been imported from [INSDC](http:\/\/www.insdc.org) and is linked to the assembly accession [[%s](http:\/\/www.ebi.ac.uk\/ena\/data\/view\/%s)].\n\nThe total length of the assembly is %d bp contained within %d scaffolds.\nThe scaffold N50 value is %d, the scaffold L50 value is %d.\n",$gca_accession_escape, $gca_accession, $total_asm_len, $scaffold_count, $scaf_N50, $scaf_L50;
		}
		else{
			## Print out the assembly summary infortmation
			printf OUT_ASM "**Assembly**\n--------\n\nThe assembly presented here has been imported from [INSDC](http:\/\/www.insdc.org) and is linked to the assembly accession [[%s](http:\/\/www.ebi.ac.uk\/ena\/data\/view\/%s)].\n\nThe total length of the assembly is %d bp contained within %d scaffolds.\nThe scaffold N50 value is %d, the scaffold L50 value is %d.\nThe GC%% content of the assembly is %.1f%%.\n",$gca_accession_escape, $gca_accession, $total_asm_len, $scaffold_count, $scaf_N50, $scaf_L50, $gc_perc;
		}
	}


	## Test if the JSON file is empty, if yes raise a warning and produce a placeholder summary in about.md static file to be filled in manually later. 
	unless (-z $json_file_path){
		$has_wiki_json_data = 1;
	}
	else{
		print BOLD RED "Wikipedia summary information NOT FOUND in JSON file: $json_file_path\t<----Skipping parse. Manual editing required for this species !!\n";

		$about_content = "**About *$scientific_name***
-------------------------
!!!!!! PLACEHOLDER SUMMARY. MANUAL EDIT REQUIRED HERE !!!!!!

Picture credit: [LICENSE TYPE]() via Wikimedia Commons [(Image source)]()

Taxonomy ID [$taxa_id](https://www.uniprot.org/taxonomy/${taxa_id})

(Text from [Wikipedia](https://en.wikipedia.org/).)

**More information**
General information about this species can be found in [Wikipedia](https://en.wikipedia.org/wiki/${species_name})\n";
	
	print OUT_ABOUT $about_content;
	}

#check if a file has JSON before attempting to parse it
if ($has_wiki_json_data == 1){
		my $fixed_json;
		$fixed_json = "${json_file_path}.fixed";
		my $file_contents = `cat $json_file_path`;
		chomp $file_contents;
		$fixed_json =~ s/\.json\.fixed/.fixed.json/;
			open(TEMPOUT, ">$fixed_json") || die "Can't open $fixed_json\n";
			print TEMPOUT "[".$file_contents."]";
			close TEMPOUT;
	
		my $json_text = do {
		open(my $json_fh, "<:encoding(UTF-8)", $fixed_json) or die ("Can't open JSON file: $fixed_json: $!\n");
		local $/;
		<$json_fh>
		};
	
		# Create JSON object and data vars we want to capture
		my $json_ob = JSON->new;
		my $jsondata = $json_ob->decode($json_text);
		# print Dumper(\$jsondata);
	
		# Extract data from json.
		foreach (@$jsondata){
			$extract = $_->{extract};
			$extract =~ s/$scientific_name/\*$scientific_name\*/;
			$extract =~ s/$common_name/$common_name (*$scientific_name*)/;
			$jpg_source = $_->{'thumbnail'}{'source'};
			$wiki_url = $_->{'content_urls'}{'desktop'}{'page'};
		}
		#Wrap the summary text
		($wiki_about = $extract) =~ s/(.{0,$wrap_at}(?:\s|$))/$1\n/g;

		# If jpg source is not defined
		unless ($jpg_source){
			$jpg_source="";
		}

$about_content = "**About *$scientific_name***
-------------------------
$wiki_about
Picture credit: [LICENSE TYPE]() via Wikimedia Commons [(Image source)]($jpg_source)

Taxonomy ID [$taxa_id](https://www.uniprot.org/taxonomy/${taxa_id})

(Text from [Wikipedia](https://en.wikipedia.org/).)

**More information**
General information about this species can be found in [Wikipedia]($wiki_url)\n";
	
print OUT_ABOUT $about_content;

	}
	if ( $annotation_source eq "DToL" ){
$dtol_community_anno_content = "**Annotation**
----------

$ens_division displaying genes linked to the assembly with accession [$gca_accession_escape](http:\/\/www.ebi.ac.uk\/ena\/data\/view\/$gca_accession).

Genomic assembly deposited to the INSDC by [Wellcome Sanger Institute](https://www.sanger.ac.uk/). Genome annotation performed by Ensembl as part of the
partnership with the [Darwin Tree of Life (DToL)](https://www.darwintreeoflife.org/) project.

Genome annotation was obtained using re-engineered versions of our Gene Annotation System [Aken *et al.*](https://europepmc.org/article/MED/27337980) with
refinements implemented for [non-vertebrate genomic annotation](https://rapid.ensembl.org/info/genome/genebuild/anno.html).

Find more information regarding DToL and Ensembl partnership [here](https://projects.ensembl.org/darwin-tree-of-life/).
";
	print OUT_ANNO $dtol_community_anno_content;
	print YELLOW "Double check DTOL linked: $scientific_name / $gca_accession for correct annotation information !!\n";
	}
elsif ( $annotation_source eq "refseq" ){
$refseq_annotation_content = "**Annotation**
----------

The annotation presented is derived from annotation submitted to
[INSDC](http:\/\/www.insdc.org) with the assembly accession [$gca_accession_escape](http:\/\/www.ebi.ac.uk\/ena\/data\/view\/$gca_accession).

$ens_division displaying genes imported from [NCBI RefSeq]($anno_report_url) annotation release v${release_version}.
Small RNA features, protein features, BLAST hits and cross-references have been
computed by [$ens_division]($division_url).
";
	print OUT_ANNO $refseq_annotation_content;
	}
elsif ( $annotation_source eq "community_annotation" ){
$community_anno_content = "**Annotation**
----------

$ens_division displaying genes imported from GenBank entry linked to the assembly with accession [$gca_accession_escape](http:\/\/www.ebi.ac.uk\/ena\/data\/view\/$gca_accession).

Genomic annotation was deposited along with initial assembly submission by [$assembly_submitter](URL_GOES_HERE).

Small RNA features, protein features, BLAST hits and cross-references have been
computed by [$ens_division]($division_url).
";
	print OUT_ANNO $community_anno_content;
	print YELLOW "Double check Community linked assembly: $scientific_name / $gca_accession for correct annotation information !!\n";
	}
elsif ( $annotation_source eq "community_sanger" ){
$community_anno_content = "**Annotation**
----------

$ens_division displaying genes imported from GenBank entry linked to the assembly with accession [$gca_accession_escape](http:\/\/www.ebi.ac.uk\/ena\/data\/view\/$gca_accession).

Genomic annotation was deposited along with assembly deposited to the INSDC by [Wellcome Sanger Institute](https://www.sanger.ac.uk/).

Small RNA features, protein features, BLAST hits and cross-references have been
computed by [$ens_division]($division_url).
";
	print OUT_ANNO $community_anno_content;
	print YELLOW "Double check Sanger (Non-DToL) Community assembly: $scientific_name / $gca_accession for correct annotation information !!\n";
	}
else{
	print RED "Something has gone wrong with annotation source parsing: $scientific_name / $gca_accession!!\n";
	}

system ("mv ./*.md ./$static_output_folder");

## Close outfiles
close OUT_ANNO;
close OUT_ABOUT;
close OUT_ASM;

print YELLOW "\n\n--> Be sure to double check all MD files. Particularly _annotation.md for assembly submitter URL <--\n";

print BRIGHT_GREEN "\t** Finished processing **\n\n";

}

system("rm ${wiki_input_dir}/*.fixed.json");

exit;

