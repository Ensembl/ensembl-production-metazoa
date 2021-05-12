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

=pod

=head1 NAME

  gene_projections_cmp.pl

=head1 SYNOPSIS

  stupid and simple comparison for unprojected genes with an effort to fix using shifts

=head1 DESCRIPTION

  stupid and simple comparison for unprojected genes with an effort to fix using shifts

=head1 ARGUMENTS

  perl gene_projections_cmp.pl
         -{from,to}_dbname
         -{from,to}_host
         -{from,to}_port
         -{from,to}_user
         -{from,to}_pass
         -help

=head1 EXAMPLE

  echo

=cut

use warnings;
use strict;

use Getopt::Long;
use Pod::Usage qw(pod2usage);
use Bio::EnsEMBL::DBSQL::DBAdaptor;

my ($from_host, $from_port, $from_user, $from_pass, $from_dbname);
my ($to_host, $to_port, $to_user, $to_pass, $to_dbname);
my ($object, $xref_name);
my $help = 0;

&GetOptions(
  'from_host=s'      => \$from_host,
  'from_port=s'      => \$from_port,
  'from_user=s'      => \$from_user,
  'from_pass=s'      => \$from_pass,
  'from_dbname=s'    => \$from_dbname,

  'to_host=s'      => \$to_host,
  'to_port=s'      => \$to_port,
  'to_user=s'      => \$to_user,
  'to_pass=s'      => \$to_pass,
  'to_dbname=s'    => \$to_dbname,

  'help|?'      => \$help,
) or pod2usage(-message => "use -help", -verbose => 1);

pod2usage(-verbose => 2) if $help;

my $from_core_db = new Bio::EnsEMBL::DBSQL::DBAdaptor( -host => $from_host, -user => $from_user, -pass => $from_pass, -port => $from_port, -dbname => $from_dbname );
my $to_core_db = new Bio::EnsEMBL::DBSQL::DBAdaptor( -host => $to_host, -user => $to_user, -pass => $to_pass, -port => $to_port, -dbname => $to_dbname );

my $from_ga = $from_core_db->get_adaptor("Gene");
my $to_sa = $to_core_db->get_adaptor("Slice");

while (<STDIN>) {
  chomp;
  my ($contig, $src, $type, $new_start, $new_end, $scr, $new_strand, $gff_phase, $info) = split /\t/;
  next if $type ne "gene";

  $new_strand = ($new_strand eq "-")? -1 : 1;
  my $stable_id = $1 if ( $info =~ m/ID=([^;]+)(?:$|;)/); 

  my $gene = $from_ga->fetch_by_stable_id($stable_id);
  if (!$gene) {
    warn "missing GENE ID $stable_id . probably duplicated\n";
    next;
  }

  my $from_seq = $gene->seq();
  my $old_start = $gene->slice->start; 
 
  my $to_slice = $to_sa->fetch_by_region('toplevel', $contig, $new_start, $new_end, $new_strand);
  my $to_seq = $to_slice->seq();

  
  if ($to_seq eq $from_seq) {
    my ($before_contig_start, $after_contig_end) = (0, 0);
    print join("\t", "OK", $stable_id, $contig, $new_start, $new_end, $new_strand, $before_contig_start, $after_contig_end), "\n"; 
    next;
  }

  my ($from_five_n, $from_seq_eff, $from_three_n) = ($1, $2, $3) if ($from_seq =~ m/^([Nn]*)(.*?)([nN]*)$/);
  next if not $from_seq_eff;
  
  if ($to_seq eq $from_seq_eff) {
    my $delta_n_five = length($from_five_n); 
    my $delta_n_three = length($from_three_n); 

    ($delta_n_five, $delta_n_three) = ($delta_n_three, $delta_n_five) if ($new_strand < 0);

    my ($before_contig_start, $after_contig_end) = (0, 0);
    $new_start -= $delta_n_five;
    $new_end += $delta_n_three;
    
    ($new_start, $before_contig_start) = (1, $new_start - 1) if ($new_start < 1);
    # ($new_end, $before_contig_start) = (1, $new_end - 1) if ($new_end >  );

    print join("\t", "FIXED", $stable_id, $contig, $new_start, $new_end, $new_strand, $before_contig_start, $after_contig_end), "\n"; 

    next;
  }

  warn "unprojected GENE $stable_id STRAND $new_strand LENDIFF ", length($to_seq) - length($from_seq), " GENE_SEQ_LEN ", length($from_seq), " SLICE_SEQ_LEN ", length($to_seq), " FROM_SEQ\t$from_seq\tTO_SEQ\t$to_seq\n";
}

