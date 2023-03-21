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

use strict;
use warnings;

# This script will input a set of refseq annotation summary files, and use the information in them to capture the JSON output (already scraped from wiki) and combine the two into a single set of species specific 
# static content markdown files

use JSON;
use Data::Dumper;
use Text::Wrap;
use Term::ANSIColor qw(:constants);

# Set colour functionality, allows single line color printing without using "reset"
$Term::ANSIColor::AUTORESET = 1;

## Get dir inforatmion
my $json_dir = $ARGV[0];
my $refseq_dir = $ARGV[1];
my $assembly_dir = $ARGV[2];
my $species_cores_listed = $ARGV[3];
my $species_refseq_urls = $ARGV[4];
my $core_host = $ARGV[5];
my $release = $ARGV[6];

die "USAGE: Parse_json_GCF_into_StaticMD.pl <WIKI_JSON_DIR> <REFSEQ_ANNO_REPORT_DIR> <REFSEQ_ASM_STATS_DIR> <List_Ensembl_CORE_FILE> <Core(s) Host> <Run_Identifier>\n" unless (@ARGV==7);

my @input_refseq_anno_summarys = <${refseq_dir}/*.refseq.anno.txt>;
## For each refseq file, locate and combine its assoicated JSON wiki summary file on GCA/GCA number

system ("mkdir -p ./StaticContent_MD_Output-${release}");

print BLUE "\nParsing JSON/Refseq files\n\n";

foreach my $refseq_sum_file (@input_refseq_anno_summarys){

	print DARK GREEN "Beginning processing RefSeq annotation:\n[$refseq_sum_file]\n";

	#Species specific static content folder
	my $static_output_folder = "StaticContent_MD_Output-${release}";	

	#Base species file name
	my $assembly_file = $refseq_sum_file;
	$assembly_file	=~ s/\.refseq\.anno\.txt/.assemblystats.txt/;
	#$assembly_file	=~ s/REFSEQ_ANNO_OUT/REFSEQ_ASSEMMSTAT_OUT/;
	$assembly_file	=~ s/RefSeq_Annotation_Reports/RefSeq_Assembly_Reports/;
	
	## Control flow and other control variables
	my $has_wiki_json_data=0;
	my $wrap_at = 70; #Length of each paragraph line printed.
	my $wiki_about;
	my $Anno_file_populated = 1;

	#per core global vars
	my ($scientific_name, $extract, $jpg_source, $wiki_url, $about_content, $annotation_content, $assembly_content);
	
	# RefSeq annotation report variables
	my ($species_name, $common_name, $taxa_id, $anno_report, $asseb_accession, $release_version, @ncbi_rel);

	# Convert GCF to GCA and locate its wiki JSON file
	my ($refseq_file, $gcf_num, $gca_accession, $core_prodname, $gca_accession_escape);

	my @split_refseq_path = split ("/", $refseq_sum_file);
	$refseq_file = $split_refseq_path[-1];
	my @split_refseq_file = split ("_", $refseq_file);
	$gcf_num = $split_refseq_file[1];
	$gcf_num =~ s/\.[0-9]$//;
	$gcf_num = "gca".$gcf_num;

	# Check if the RefSeq Annotation file is empty or populated:
	if (-z $refseq_sum_file){
		
		print BOLD RED "RefSeq Annotation summary file :\t$refseq_sum_file\nAnnotation README file is empty. Need to approximate information from assembly report file instead!!\n";
			
		# Define unknown annotation report ftp and version
        $Anno_file_populated = 0;

		my $grep_raw_asm = `grep -e "Organism name" < $assembly_file`;
		my @temp_split_rawname = split (": ", $grep_raw_asm);

		if ($temp_split_rawname[1] =~ m/[A-Z][a-z]+ [a-z]+/){$scientific_name = $&;}
		my $species_name_tmp = $scientific_name;		
		$species_name_tmp =~ tr / /_/;
		$static_output_folder = $static_output_folder."/".$species_name_tmp;
		$species_name = lcfirst($species_name_tmp);

		if ( $temp_split_rawname[1] =~ m/\(\w+ \w+\)/ ){$common_name = $&; $common_name =~ s/\(//g; $common_name =~ s/\)//g;}	
		
		my $temp_cn = ucfirst($common_name); $common_name = $temp_cn;
		
		#Get TaxonID from asm report file
		$grep_raw_asm = `grep -e "Taxid" < $assembly_file`;
		if ( $grep_raw_asm =~ m/\d+/ ){ $taxa_id = $&; chomp $taxa_id; }

		$grep_raw_asm = `grep -e "GenBank assembly accession" < $assembly_file`;
        
		if ( $grep_raw_asm =~ m/GCA_\d+\.\d/ ){ 
			
			$gca_accession=$&;
			chomp $gca_accession;
			$core_prodname = $gca_accession;
	        $gca_accession_escape = $gca_accession;
        	$gca_accession_escape =~ s/GCA_/GCA\\_/;
            $core_prodname =~ s/GCA_/gca/;
            $core_prodname =~ s/\.[0-9]$//;
            chomp $core_prodname;
            $core_prodname = "${species_name}_${core_prodname}";
		}

	}# Ends test on missing anno report


	## Parse species name from ref_seq annotion
	unless (defined $species_name){	$species_name = `grep -e "ORGANISM NAME" < $refseq_sum_file | cut -f2`;
	chomp $species_name;
	$scientific_name = $species_name;
	$species_name =~ tr/ /_/;
	$static_output_folder = $static_output_folder."/".$species_name;
	}
	my @temp_split_sp_name = split ("_", $species_name);

	#Check whether or not the species name is bionomial or trinomial
	if ((scalar @temp_split_sp_name == 3 ) && ($temp_split_sp_name[1] eq $temp_split_sp_name[2])){
		print YELLOW "!!! Found trinomial species name instance !!!! \"$species_name\" --> Utilizing just the bionomial: ";
		$species_name = "$temp_split_sp_name[0]_$temp_split_sp_name[1]";
		print "\"$species_name\"\n";
	}
	else{
		print "Species name: \"$scientific_name\".\n";
	}

	$species_name = lc$species_name;
	system ("mkdir -p ./$static_output_folder");

	# Check if common name and Taxon ID was defined from Assembly report file, otherwise grab from Annotation report file
	# Common name:
	unless (defined $common_name ){ $common_name = `grep -e "^ORGANISM COMMON NAME" < $refseq_sum_file | cut -f2`; chomp $common_name; }
	# Taxon ID:
	unless (defined $taxa_id ){ $taxa_id = `grep -e "^TAXID" < $refseq_sum_file | cut -f2`; chomp $taxa_id; }


	# Check if Annotation report was in place, otherwise we can't get annotation report ftp url and version
	$anno_report = `grep -e "^ANNOTATION REPORT" < $refseq_sum_file | cut -f2`;
	chomp $anno_report;
	
	## If Annotation report is avaialble, obtain annotation report url and release version.
	if ($Anno_file_populated == 1 ){
		@ncbi_rel = split ("/",$anno_report);
		$release_version = $ncbi_rel[-1];
		$asseb_accession = `grep -e "^ASSEMBLY ACCESSION" < $refseq_sum_file | cut -f2`;
        chomp $asseb_accession;
        $gca_accession = $asseb_accession;
        $gca_accession =~ s/GCF_/GCA_/;
        $core_prodname = $gca_accession;
        $gca_accession_escape = $gca_accession;
        $gca_accession_escape =~ s/GCA_/GCA\\_/;
        $core_prodname =~ s/GCA_/gca/;
        $core_prodname =~ s/\.[0-9]$//;
        chomp $core_prodname;
        $core_prodname = "${species_name}_${core_prodname}";
	}
	else{
		my $GCF_from_GCA = $gca_accession;
		$GCF_from_GCA =~ s/GCA_/GCF_/;
		my $grep_acc_for_refseq = `grep -e "$GCF_from_GCA" < $species_refseq_urls`;
		chomp $grep_acc_for_refseq;
		
		#Now redefine Annotation report URL and release version to be the RefSeq FTP url
		$anno_report = $grep_acc_for_refseq;
		$release_version = "ersion is not defined for $gca_accession assembly";
	}
	
	#Initial attempt to locate the correct core DB.
	my $species_core = `grep -E "^${core_prodname}" < $species_cores_listed\n`;
	chomp $species_core;

	#Find the coreDB from the input core list file. Then locate the appropriate JSON file to parse. 
	my ($json_file_name, $json_file_path);

	#Test if core was found based on inclusion of GCA_ in the name
	if ($species_core){
		print "Core DB located: $species_core\n";
		$json_file_name = "$species_name"."_"."$gcf_num";
		$json_file_path = `ls -1 ${json_dir}/${json_file_name}*`;
		chomp $json_file_path;
		#print "JSON_FILE_PATH = $json_file_path\n";
	}
	else{
		print YELLOW "No core DB containing \"_gca\" accession found [$asseb_accession].\n";

		$species_core = `grep -E "^${species_name}_core_[0-9]{2}_[0-9]{3}_[0-9]{1}" < $species_cores_listed\n`;
		chomp $species_core;
		print YELLOW "Located core instead: $species_core\n";
		$json_file_path = `ls -1 ${json_dir}/${species_core}.wiki.json`;
		chomp $json_file_path;
	}

	#Perform query to obtain production name from to ensure static md will match with ensembl core DB
	system("$core_host -D $species_core -e \"SELECT meta_value FROM meta WHERE meta_key = 'species.production_name';\" | tail -n 1 > temp_sql.txt");
	my $prod_name=`cat temp_sql.txt`;
	chomp $prod_name;
	$prod_name = ucfirst($prod_name);
	system("rm ./temp_sql.txt");
	print "Linked with Ensembl CORE_DB [$species_core] & species.production_name [$prod_name]\n";

	##Open file handles using species.productioin_name to write markdown .md files.
	open (OUT_ABOUT, ">${prod_name}_about.md") || die "Can\'t open ${prod_name}_about.md\n";
	open (OUT_ANNO, ">${prod_name}_annotation.md") || die "Can\'t open ${prod_name}_annotation.md\n";
	open (OUT_ASM, ">${prod_name}_assembly.md") || die "Can\'t open ${prod_name}_assembly.md\n";
 
	# printf "The species %s, otherwise known as the %s.\nTaxon_id=%d\nWas obtained with annotation from %s\nWhich is associated with acc:%s\n", $species_name, $common_name, $taxa_id, $anno_report, $asseb_accession;

	## Parse specifc assembly statistics from asm file
	my ($total_asm_len, $scaffold_count, $scaf_N50, $scaf_L50, $contig_count, $cont_N50, $cont_L50, $gc_perc, $total_gap_length);

	$total_asm_len = `grep -E "^all.+total-length" < $assembly_file | cut -f6`;
	$scaffold_count = `grep -E "^all.+scaffold-count" < $assembly_file | cut -f6`;
	chomp ($scaffold_count, $total_asm_len);

	#Check if scaffolds are accounted for or contigs
	if ($scaffold_count eq ""){

		# print "!!!!!!!!!Entered Contig section !!!!!!!!!!!!!!\n";
		$contig_count = `grep -E "^all.+contig-count" < $assembly_file | cut -f6`;
		$cont_N50 = `grep -E "^all.+contig-N50" < $assembly_file | cut -f6`;
		$cont_L50 = `grep -E "^all.+contig-L50" < $assembly_file | cut -f6`;
		$total_gap_length = `grep -E "^all.+total-gap-length" < $assembly_file | cut -f6`;
		$gc_perc = `grep -E "^all.+gc-perc" < $assembly_file | cut -f6`;

		chomp ($contig_count, $cont_N50, $cont_L50, $total_gap_length, $gc_perc);

		if (!$gc_perc){
			# $gc_perc="0.0";
			## Print out the assembly summary infortmation without mentioning the absent asm GC%
			printf OUT_ASM "**Assembly**\n--------\n\nThe assembly presented here has been imported from [INSDC](http:\/\/www.insdc.org) and is linked to the assembly accession [[%s](http:\/\/www.ebi.ac.uk\/ena\/data\/view\/%s)].\n\nThe total length of the assembly is %d bp contained withinin %d contigs.\nThe contig N50 value is %d, the contig L50 value is %d.\nAssembly gaps span %d bp.\n",$gca_accession_escape, $gca_accession, $total_asm_len, $contig_count, $cont_N50, $cont_L50, $total_gap_length;

		}
		else{
			## Print out the assembly summary infortmation without mentioning the absent asm GC%
			printf OUT_ASM "**Assembly**\n--------\n\nThe assembly presented here has been imported from [INSDC](http:\/\/www.insdc.org) and is linked to the assembly accession [[%s](http:\/\/www.ebi.ac.uk\/ena\/data\/view\/%s)].\n\nThe total length of the assembly is %d bp contained withinin %d contigs.\nThe contig N50 value is %d, the contig L50 value is %d.\nAssembly gaps span %d bp. The GC%% content of the assembly is %.1f%%.\n",$gca_accession_escape, $gca_accession, $total_asm_len, $contig_count, $cont_N50, $cont_L50, $total_gap_length, $gc_perc;
		}
	}
	else{

		# print "!!!!!!!!!Entered Scaffold section !!!!!!!!!!!!!!\n";
		$scaf_N50 = `grep -E "^all.+scaffold-N50" < $assembly_file | cut -f6`;
		$scaf_L50 = `grep -E "^all.+scaffold-L50" < $assembly_file | cut -f6`;
		$total_gap_length = `grep -E "^all.+total-gap-length" < $assembly_file | cut -f6`;
		$gc_perc = `grep -E "^all.+gc-perc" < $assembly_file | cut -f6`;

		chomp ($scaf_N50, $scaf_L50, $total_gap_length, $gc_perc);

		if (!$gc_perc){
			# $gc_perc="0.0";
			printf OUT_ASM "**Assembly**\n--------\n\nThe assembly presented here has been imported from [INSDC](http:\/\/www.insdc.org) and is linked to the assembly accession [[%s](http:\/\/www.ebi.ac.uk\/ena\/data\/view\/%s)].\n\nThe total length of the assembly is %d bp contained withinin %d scaffolds.\nThe scaffold N50 value is %d, the scaffold L50 value is %d.\nAssembly gaps span %d bp.\n",$gca_accession_escape, $gca_accession, $total_asm_len, $scaffold_count, $scaf_N50, $scaf_L50, $total_gap_length;
		}
		else{
			## Print out the assembly summary infortmation
			printf OUT_ASM "**Assembly**\n--------\n\nThe assembly presented here has been imported from [INSDC](http:\/\/www.insdc.org) and is linked to the assembly accession [[%s](http:\/\/www.ebi.ac.uk\/ena\/data\/view\/%s)].\n\nThe total length of the assembly is %d bp contained withinin %d scaffolds.\nThe scaffold N50 value is %d, the scaffold L50 value is %d.\nAssembly gaps span %d bp. The GC%% content of the assembly is %.1f%%.\n",$gca_accession_escape, $gca_accession, $total_asm_len, $scaffold_count, $scaf_N50, $scaf_L50, $total_gap_length, $gc_perc;
		}
	}


	## Test if the JSON file is empty, if yes raise a warning and produce a placeholder summary in about.md static file to be filled in manually later. 
	unless (-z $json_file_path){
		$has_wiki_json_data = 1;
	}
	else{
		print BOLD RED "Wikipedia summary information not found in JSON file: $json_file_path\t<----Skipping parse. Manual editing required for this species !!\n";

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
			open(TEMPOUT, ">$fixed_json") || die "can't open $fixed_json\n";
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

$annotation_content = "**Annotation**
----------

The annotation presented is derived from annotation submitted to
[INSDC](http:\/\/www.insdc.org) with the assembly accession [$gca_accession_escape](http:\/\/www.ebi.ac.uk\/ena\/data\/view\/$gca_accession).

Ensembl Metazoa displaying genes imported from [NCBI RefSeq]($anno_report) annotation release v${release_version}.
Small RNA features, protein features, BLAST hits and cross-references have been
computed by [Ensembl Metazoa](https://metazoa.ensembl.org/info/genome/annotation/index.html).
";

print OUT_ANNO $annotation_content;

system ("mv ./*.md ./$static_output_folder");

## Close outfiles
close OUT_ANNO;
close OUT_ABOUT;
close OUT_ASM;

print BRIGHT_GREEN "\t** Finished processing **\n\n";

}

system("rm ${json_dir}/*.fixed.json");

exit;

