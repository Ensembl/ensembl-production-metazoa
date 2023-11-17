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

=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <dev@ensembl.org>.

  Questions may also be sent to the Ensembl help desk at
  <helpdesk@ensembl.org>.
  
=head1 SYNOPSIS

set_core_samples.pl [arguments]

  --user=user                      username for the core databases

  --pass=pass                      password for the core databases

  --host=host                      server for the core databases

  --port=port                      port for the core databases

  --pattern=pattern                      pattern for the core databases
  
   --comparauser=user                     username for the compara database

  --comparapass=pass                     password for compara database

  --comparahost=host                     server where the compara database is stored

  --comparaport=port                     port for compara database
  
  --comparadbname=dbname                 name of compara database to process
  
     --panuser=user                     username for the pan database

  --panpass=pass                     password for pan database

  --panhost=host                     server where the pan database is stored

  --panport=port                     port for pan database
  
  --pandbname=dbname                 name of pan database to process
  
  --help                              print help (this message)

=head1 DESCRIPTION

This script is used to set the sample for a core species based on genes that can be found in compara and pan compara

=head1 AUTHOR

Mark McDowall

=head1 MAINTANER

$Author$

=head1 VERSION

$Revision$
=cut

use strict;
use warnings;

use Pod::Usage;
use Bio::EnsEMBL::Compara::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Utils::CliHelper;
use List::Util qw/shuffle/;
use Data::Dumper;
use Carp;
use Log::Log4perl qw(:easy);

Log::Log4perl->easy_init($INFO);
my $logger = get_logger();

my $cli_helper = Bio::EnsEMBL::Utils::CliHelper->new();
# get the basic options for connecting to a database server
my $optsd = [ @{ $cli_helper->get_dba_opts() },
			  @{ $cli_helper->get_dba_opts('compara') },
			  @{ $cli_helper->get_dba_opts('pan') } ];
push @$optsd, "nocache";
push @$optsd, "gene_id:s";
# process the command line with the supplied options plus a help subroutine
my $opts = $cli_helper->process_args( $optsd, \&pod2usage );

if ( !$opts->{user} ||
     !$opts->{pass} ||
     !$opts->{host} ||
     !$opts->{port}) {
    pod2usage(1);
}

if(defined $opts->{gene_id}) {

    for my $dba_args ( @{ $cli_helper->get_dba_args_for_opts($opts) } ) {
	my $dba = Bio::EnsEMBL::DBSQL::DBAdaptor->new( %{$dba_args} );
#  $logger->info($dba->species() . ": " . (in_compara($genome_dba, $dba) ? "compara" : "non-compara") . "; " . (in_compara($pan_genome_dba, $dba) ? "pan" : "non-pan"));
	my $gene = $dba->get_GeneAdaptor()->fetch_by_stable_id($opts->{gene_id});
	if ( defined $gene ) {
	    $logger->info( $dba->species() . "->" .
			   ( $gene->external_name() || $gene->stable_id() ) );
	    store_gene_sample( $dba, $gene );
	} else {
	    $logger->error("Gene ".$opts->{gene_id}." not found for ".$dba->species());
	}
    }
    

} else {
    
    if(!$opts->{comparauser}   ||
       !$opts->{comparahost}   ||
       !$opts->{comparaport}   ||
       !$opts->{comparadbname} ||
       !$opts->{panuser}       ||
       !$opts->{panhost}       ||
       !$opts->{panport}       ||
       !$opts->{pandbname} )
    {
	pod2usage(1);
    }
    
    $logger->info("Getting compara DBA");
# get a compara dba
    my $compara_url = sprintf( 'mysql://%s:%s@%s:%d/%s',
			       $opts->{comparauser},
			       $opts->{comparapass} || '',
			       $opts->{comparahost},
			       $opts->{comparaport},
			       $opts->{comparadbname} );
    my $compara_dba =
	Bio::EnsEMBL::Compara::DBSQL::DBAdaptor->new( -url => $compara_url,
						      -species => 'Multi' );
    $logger->info("Getting pan-compara DBA");
    my $pan_url = sprintf( 'mysql://%s:%s@%s:%d/%s',
			   $opts->{panuser}, $opts->{panpass} || '',
			   $opts->{panhost}, $opts->{panport},
			   $opts->{pandbname} );
    my $pan_dba =
	Bio::EnsEMBL::Compara::DBSQL::DBAdaptor->new( -url     => $pan_url,
						      -species => 'Multi2' );
    
    my $genome_dba           = $compara_dba->get_GenomeDBAdaptor();
    my $pan_genome_dba       = $pan_dba->get_GenomeDBAdaptor();
    my $member_adaptor       = $compara_dba->get_GeneMemberAdaptor();
    my $pan_member_adaptor   = $pan_dba->get_GeneMemberAdaptor();
    my $pan_tree_adaptor     = $pan_dba->get_GeneTreeAdaptor();
    my $compara_tree_adaptor = $compara_dba->get_GeneTreeAdaptor();
    
    for my $dba_args ( @{ $cli_helper->get_dba_args_for_opts($opts) } ) {
	my $dba = Bio::EnsEMBL::DBSQL::DBAdaptor->new( %{$dba_args} );
#  $logger->info($dba->species() . ": " . (in_compara($genome_dba, $dba) ? "compara" : "non-compara") . "; " . (in_compara($pan_genome_dba, $dba) ? "pan" : "non-pan"));
	my @genes = @{ get_random_genes($dba) };
	my $gene;
	while ( scalar(@genes) > 0 ) {
	    $gene = pop @genes;
	    last if ( gene_valid( $dba, $gene ) == 1 );
	}
	if ( defined $gene ) {
	    $logger->info( $dba->species() . "->" .
			   ( $gene->external_name() || $gene->stable_id() ) );
	    store_gene_sample( $dba, $gene );
	}
        $dba->dbc()->disconnect_if_idle(1);
    }
    

    sub in_compara {
	my ( $genome_dba, $dba ) = @_;
	my $genome_db;
	eval { $genome_db = $genome_dba->fetch_by_core_DBAdaptor($dba); };
	return defined($genome_db) ? 1 : 0;
    }

    sub get_random_genes {
	my ($dba) = @_;
	my @genes1 =
	    @{ $dba->get_GeneAdaptor()->fetch_all_by_biotype("protein_coding")
	    };

# select genes on chromosomes if possible. It would be nice to
# avoid any genes on chromosomes but not called chromosome...  (i.e. plasmids and junk like that)
# but chromosome naming across species is not consistent enough to do this.
	my @genes2 = grep {
	    my $slice = $_->slice();
	    ( lc( $slice->coord_system()->name() ) eq "chromosome" ||
	      $slice->seq_region_name() =~ m/chromosome/i )
	} @genes1;
	if ( scalar(@genes2) == 0 ) {
	    @genes2 = @genes1;
	}
# avoid genes where the stable_id is the same as the name - implies not as well annotated
	my @genes = grep {
	    defined $_->external_name() &&
		( $_->external_name() ne $_->stable_id() )
	} @genes2;
	if ( scalar(@genes) == 0 ) {
	    @genes = @genes2;
	}
	# shuffle genes
	@genes = shuffle(@genes);
	return \@genes;
    } ## end sub get_random_genes
    
    sub gene_valid {
	my ( $dba, $gene ) = @_;
	my $is_valid = 1;
	# check compara
	if ( in_compara( $genome_dba, $dba ) == 1 ) {
	    # does it have a family?
	    if ( my $member =
		 $member_adaptor->fetch_by_stable_id( $gene->stable_id() ) )
	    {
		#$member = $member->get_all_SeqMembers->[0];
		my $ctree = $compara_tree_adaptor->fetch_all_by_Member($member);
		if ( !defined $ctree || scalar(@$ctree) == 0 ) {
		    $is_valid = 0;
		}
	    }
	}
	# check pan compara
	if ( in_compara( $pan_genome_dba, $dba ) == 1 ) {
	    # does it have a gene tree?
	    if ( my $member =
		 $member_adaptor->fetch_by_stable_id( $gene->stable_id() ) )
	    {
		my $tree = $pan_tree_adaptor->fetch_all_by_Member($member);
		if ( !defined $tree || scalar(@$tree) == 0 ) {
		    $is_valid = 0;
		}
	    }
	}
	return $is_valid;
    } ## end sub gene_valid
    
}

sub store_gene_sample {
    my ( $dba, $gene ) = @_;
    my $meta     = $dba->get_MetaContainer();
    my $sr_name  = $gene->seq_region_name();
    my $sr_start = $gene->seq_region_start();
    my $sr_end   = $gene->seq_region_end();
    
    # adjust bounds by 10%
    my $flank = int(( $sr_end - $sr_start + 1 )/10);
    $sr_start -= $flank;
    $sr_end += $flank;
    $sr_start = 0 if ( $sr_start < 0 );
    $sr_end = $gene->slice()->seq_region_length()
	if ( $sr_end > $gene->slice()->seq_region_length() );
    
    $logger->info( "Storing sample gene data " .
		   ( $gene->external_name() || $gene->stable_id() ) );
    $meta->delete_key('sample.location_param');
    $meta->store_key_value( 'sample.location_param',
			    "$sr_name:${sr_start}-${sr_end}" );
    $meta->delete_key('sample.location_text');
    $meta->store_key_value( 'sample.location_text',
			    "$sr_name:${sr_start}-${sr_end}" );
    $meta->delete_key('sample.gene_param');
    $meta->store_key_value( 'sample.gene_param', $gene->stable_id() );
    $meta->delete_key('sample.gene_text');
    $meta->store_key_value( 'sample.gene_text',
			    ( $gene->external_name() || $gene->stable_id()
			    ) );
    my $transcript = @{ $gene->get_all_Transcripts() }[0];
    $logger->info( "Storing sample transcript data for " .
		   ( $gene->external_name() || $gene->stable_id() ) );
    $meta->delete_key('sample.transcript_param');
    $meta->store_key_value( 'sample.transcript_param',
			    $transcript->stable_id() );
    $meta->delete_key('sample.transcript_text');
    $meta->store_key_value( 'sample.transcript_text',
			    ( $transcript->external_name() ||
			      $transcript->stable_id() ) );
    $meta->delete_key('sample.search_text');
    $meta->store_key_value( 'sample.search_text', 'synthetase' );
    return;
} ## end sub store_gene_sample
