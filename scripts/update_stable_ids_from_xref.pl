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

  update_stable_ids_from_xref.pl

=head1 SYNOPSIS

  get primary xref ids for genes and transcripts

=head1 DESCRIPTION

  get primary xref ids for genes and transcripts

=head1 ARGUMENTS

  perl update_stable_ids_from_xref.pl
         -host
         -port
         -user
         -pass
         -help
         -dbname
         -type GeneID
         -valid_gene_re '\d{6,}'
         -valid_transcript_re '\d{6,}'
         -store_as_xref 'Ensembl_Metazoa'

=head1 EXAMPLE

  perl update_stable_ids_from_xref.pl $($CMD details script) -dbname anopheles_funestus_core_1906_95_3 -type GeneID > updated_list.tsv

=cut

use warnings;
use strict;

use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::DBEntry;
use Getopt::Long;
use Pod::Usage qw(pod2usage);

my ($host, $port, $user, $pass, $dbname);
my $type = "GeneID";
my $analysis_name = "refseq_import_visible";
my $valid_gene_re = '\d{6,}';
my $valid_tr_re = '\d{6,}';
my $store_as_xref = "Ensembl_Metazoa";
my $dry_run = 1;

my $help = 0;

&GetOptions(
  'host=s'      => \$host,
  'port=s'      => \$port,
  'user=s'      => \$user,
  'pass=s'      => \$pass,
  'dbname=s'    => \$dbname,
  'type:s'    => \$type,
  'analysis_name:s'          => \$analysis_name,
  'valid_gene_re:s'    => \$valid_gene_re,
  'valid_tr_re:s'    => \$valid_tr_re,
  'store_as_xref:s'  => \$store_as_xref,
  'dry_run:s'    => \$dry_run,

  'help|?'      => \$help,
) or pod2usage(-message => "use -help", -verbose => 1);

pod2usage(-verbose => 2) if $help;



my ($core_db, $ga, $ta, $pepa, $analysis);

if (!$dry_run)  {
  $core_db = new Bio::EnsEMBL::DBSQL::DBAdaptor( -host => $host, -user => $user, -pass => $pass, -port => $port, -dbname => $dbname );

  $ga = $core_db->get_adaptor("Gene");
  $ta = $core_db->get_adaptor("Transcript");
  $pepa = $core_db->get_adaptor("Translation");

  my $aa       = $core_db->get_adaptor('Analysis');
  $analysis = $aa->fetch_by_logic_name($analysis_name);
  if (! defined $analysis) {
    die "Analysis '$analysis_name' does not exist in the database.\n";
  }
} else {
  warn("not altering db: dry_run $dry_run\n");
}


my $sub4gene_id = {};
while(<STDIN>) {
  chomp;
  # 30      TRNAM-CAU-5     64      TRNAM-CAU-5_t1  TRNAM-CAU-5     GeneID  107964931       GeneID  107964931
  # 54      Per     133     XM_026444131.1  .       GeneID  406112  GeneID  406112
  # 54      Per     135     XM_026444130.1  .       GeneID  406112  GeneID  406112
  my ($gene_id, $gene_name, $tr_id, $tr_name, $common_pfx, $xrefg, $xrefg_id, $xreftr, $xreftr_id) = split /\t/;
  next if ($gene_name =~ m/$valid_gene_re/ && $tr_name =~ m/$valid_tr_re/);
  next if ($xrefg ne $type or $xreftr ne $type);

  $common_pfx = "" if ($common_pfx eq ".");

  my $new_gene_name = "";
  my $new_tr_name = "";

  if ($gene_name !~ m/$valid_gene_re/ && !exists $sub4gene_id->{$gene_id} ) {
    my $xref_id = $xrefg_id;
    $xref_id = $xreftr_id if (!$xref_id || $xref_id eq ".");
    if (!$xref_id || $xref_id eq ".") {
      warn "no valid xref id for gene $gene_name ($gene_id) transcript $tr_name ($tr_id). skiping...\n";
      next;
    }
    my $name_subst = "${type}_${xref_id}"; 
    $sub4gene_id->{$gene_id} = $name_subst;
    if ($common_pfx) {
      $new_gene_name = $gene_name;
      $new_gene_name =~ s/$common_pfx/$name_subst/;
      $new_tr_name = $tr_name;
      $new_tr_name =~ s/$common_pfx/$name_subst/;
    } else {
      $new_gene_name = $name_subst;
    }
  }  # gene_name 

  if ($tr_name !~ m/$valid_tr_re/ && !$new_tr_name) {
    if ($common_pfx && exists $sub4gene_id->{$gene_id}) {
      $new_tr_name = $tr_name;
      my $name_subst = $sub4gene_id->{$gene_id};
      $new_tr_name =~ s/$common_pfx/$name_subst/;
    } else {
      # process individually
      my $xref_id = $xreftr_id;
      $xref_id = $xrefg_id if (!$xref_id || $xref_id eq ".");
      $new_tr_name = "${type}_${xref_id}_${tr_name}"; 
      warn "individual transcript new name $new_tr_name for transcript $tr_name ($tr_id) gene $gene_name ($gene_id)\n";
    }
  }
  
  print(join("\t", "GENE", $gene_id, $gene_name, $new_gene_name), "\n") if $new_gene_name;
  print(join("\t", "TRANSCRIPT", $tr_id, $tr_name, $new_tr_name), "\n") if $new_tr_name;
  next if ($dry_run);

  update_stable_id("gene", $ga, $new_gene_name, $gene_name, $gene_id);
  update_stable_id("transcript", $ta, $new_tr_name, $tr_name, $tr_id);
} # <STDIN>


if ($dry_run) {
  warn "not fixing transcript and translation versions. exiting...";
  exit(0);
}

fix_stable_id_versions("transcript", $ta);
fix_stable_id_versions("translation", $pepa);

if (!$ta) {
  warn "no transcript adaptor. exiting...";
  exit(0);
}


sub fix_stable_id_versions {
  my ($type, $ad) = @_;

  warn "fixing ${type}s versions\n";
  if (!$ad) {
    warn "no valid $type adaptor. skipping...";
    return;
  }

  my $objects = $ad->fetch_all(); 
  return if !$objects;

  while (my $obj = shift @{$objects}) {
    next if !$obj;
    my $stable_id = $obj->stable_id;
    next if !$stable_id;
    if ($stable_id =~ m/^[^\.]+\.\d{1,2}$/) {
      my $stable_id_raw = $stable_id;
      $stable_id =~ s/\.(\d+)$//;
      my $version = $1;
      warn "updating $type $stable_id_raw with $stable_id version $version\n";
      _update_stable_id_impl($core_db, $type, $obj, $stable_id);
      $obj->version($version);
      eval { $ad->update($obj) };
      if ($@) {
        warn "failed to update $type $stable_id_raw with $stable_id version $version\n";
      }
    }
  }
}


sub update_stable_id {
  my ($type, $ad, $new_name, $name, $id) = @_;
  
  return if !$new_name; 

  my $obj = $ad->fetch_by_dbID($id);
  if (!$obj) {
    warn "failed to get object for $type $name ($id) new_name $new_name\n";
    return;
  }

  my $stable_id = $obj->stable_id;
  if ($stable_id ne $name) {
    warn "stable id from file $name and from db $stable_id for $type $id do not match. ignoring...\n";
    return;
  }

  $obj->stable_id($new_name);  
  _update_stable_id_impl($core_db, $type, $obj, $new_name);
  update_xref($obj, $name, $type);

  eval { $ad->update($obj) };
  if ($@) {
    warn "failed to update $type $name ($id) new_name $new_name: $@\n";
  }
}


sub get_all_xrefs {
  my ($obj) = @_;   
  my $res = {};
  for my $ent (@{$obj->get_all_DBEntries()}) {
    my $dsp_id = $ent->display_id();
    $res->{$dsp_id} = $ent if (!exists $res->{$dsp_id});
  }
  return $res;
}


sub update_xref {
  my ($obj, $name, $type) = @_;   
  my $all_xrefs = get_all_xrefs($obj);
  if (exists $all_xrefs->{$name}) {
    $obj->display_xref($all_xrefs->{$name});
    return;
  }
  
  my $dbea = $core_db->get_DBEntryAdaptor;

  my $entry = new Bio::EnsEMBL::DBEntry(
    -adaptor     => $dbea,
    -primary_id  => $name,
    -display_id  => $name,
    -dbname      => $store_as_xref,
    -info_type   => 'DIRECT',
    -analysis    => $analysis,
  );

  my $ignore_release = 1;
  if ($dbea->store($entry, $obj->dbID, $type, $ignore_release)) {
    $obj->display_xref($entry);
  }
}

sub _update_stable_id_impl {
  my ($dba, $type, $obj, $stable_id) = @_;

  eval {
    my $sth = $dba->dbc->prepare(" UPDATE $type "
                           . " SET stable_id = ? "
                           . " WHERE ${type}_id = ? ");
    $sth->execute($stable_id, $obj->dbID);
    $sth->finish();
  };
  my $id = $obj && $obj->dbID;
  warn "failed to update object's version (id: \"$id\", type \"$type\", version \"$stable_id\"): $@\n" if ($@);
}

