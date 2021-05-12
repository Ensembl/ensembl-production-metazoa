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

  get_gene_tr_ids.pl

=head1 SYNOPSIS

  get primary xref ids for genes and transcripts

=head1 DESCRIPTION

  get primary xref ids for genes and transcripts

=head1 ARGUMENTS

  perl get_gene_tr_ids.pl
         -host
         -port
         -user
         -pass
         -help
         -dbname
         -xref_types BEEBASE,GeneID

=head1 EXAMPLE

  perl get_gene_tr_ids.pl $($CMD details script) -dbname anopheles_funestus_core_1906_95_3 -xref_types GeneID > prev_xrefs.tsv

=cut

use warnings;
use strict;

use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Getopt::Long;
use Pod::Usage qw(pod2usage);

my ($host, $port, $user, $pass, $dbname);
my ($xref_types);


my $help = 0;

&GetOptions(
  'host=s'      => \$host,
  'port=s'      => \$port,
  'user=s'      => \$user,
  'pass=s'      => \$pass,
  'dbname=s'    => \$dbname,
  'xref_types:s'    => \$xref_types,

  'help|?'      => \$help,
) or pod2usage(-message => "use -help", -verbose => 1);

pod2usage(-verbose => 2) if $help;

my $core_db = new Bio::EnsEMBL::DBSQL::DBAdaptor( -host => $host, -user => $user, -pass => $pass, -port => $port, -dbname => $dbname );

my $types = { map{ $_ => 1} grep { !!$_ } split(/,/, $xref_types // '') };

sub common_pfx {
  my ($gene, $tr) = @_;
  $gene //= '';
  $tr //= '';
  my $min_len = length($gene);
  $min_len = length($tr) if length($tr) < $min_len;
  my $i = 0;
  for (my $i = 0; $i < $min_len; $i++) {
    my $gc = substr($gene, $i, 1);
    my $tc = substr($tr, $i, 1);
    if ($gc ne $tc) {
      return ($i == 0)? "." : substr($gene, 0, $i);
    }
  }
  return substr($gene, 0, $min_len);
}


my $ta = $core_db->get_adaptor("Transcript");
if ($ta) {
  my $pctrs = $ta->fetch_all(); 
  if ($pctrs) {
    while (my $tr = shift @{$pctrs}) {
      next if !$tr;

      my $gene = $tr->get_Gene(); 
      next if !$gene;

      my $dbes = {
        gene => $gene->get_all_DBEntries(),
        tr => $tr->get_all_DBEntries(),
      };

      my $xrefs = {};
      
      for my $feat (keys %$dbes) {
        for my $dbe (@{$dbes->{$feat}}) {
          my $ename = $dbe->dbname() // ''; 
          next if %$types and  not exists $types->{$ename};
          if (!exists $xrefs->{$ename}) {
            $xrefs->{$ename} = { tr => [], gene => [] }
          }
          push @{$xrefs->{$ename}->{$feat}}, $dbe->display_id();
        }
      }

      $xrefs = { NOXREF => { gene => ['.'],  tr => ['.'] } } if ( ! %$xrefs ) ;
      for my $name (keys %$xrefs) {
        my $gene_xrefs = join(",", @{ $xrefs->{$name}->{gene} }  ); 
        my $tr_xrefs = join(",", @{ $xrefs->{$name}->{tr} } ); 
        print(join("\t",
            $gene->dbID(), $gene->stable_id(),
            $tr->dbID(), $tr->stable_id(),
            common_pfx($gene->stable_id(), $tr->stable_id()),
            $name, $gene_xrefs, $name, $tr_xrefs
          ), "\n");
      }
    }
  }
}


