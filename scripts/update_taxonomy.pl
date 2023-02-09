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

  update_taxonomy.pl

=head1 SYNOPSIS

  get primary xref ids for genes and transcripts

=head1 DESCRIPTION

  collections aware update taxonomy script

=head1 ARGUMENTS

  perl update_taxonomy.pl
         -host
         -port
         -user
         -pass
         -help
         -dbname
         -species
         -dry_run
         -update_common_names

=head1 EXAMPLE

  perl update_taxonomy.pl \
    $(CMD_T details_script_taxonomy_) \
    $($CMD details script) \
    -update_common_names 0 \
    -dry_run 0 \
    -dbname preprok_col_bacteria_9_core_57_109_1 -species achromobacter_sp_root83_gca_001428845 

=cut


# copypasting bits from
#  Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveAssemblyLoading::HiveLoadTaxonomyInfo
#  Bio::EnsEMBL::Production::Pipeline::TaxonomyUpdate::QueryMetadata

use warnings;
use strict;

use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Taxonomy::DBSQL::TaxonomyDBAdaptor;
use Getopt::Long;
use Pod::Usage qw(pod2usage);

my ($taxonomy_host, $taxonomy_port, $taxonomy_user, $taxonomy_dbname);
my ($host, $port, $user, $pass, $dbname, $species);
my ($update_common_names, $dry_run);

# defaults
$taxonomy_dbname = "ncbi_taxonomy";
$update_common_names = 0;
$dry_run = 1;

my $help = 0;

&GetOptions(
  'taxonomy_host=s'      => \$taxonomy_host,
  'taxonomy_port=s'      => \$taxonomy_port,
  'taxonomy_user=s'      => \$taxonomy_user,
  'taxonomy_dbname=s'    => \$taxonomy_dbname,

  'host=s'      => \$host,
  'port=s'      => \$port,
  'user=s'      => \$user,
  'pass=s'      => \$pass,
  'dbname=s'    => \$dbname,
  'species=s'   => \$species,

  'update_common_names=i'   => \$update_common_names,
  'dry_run=i'   => \$dry_run,

  'help|?'      => \$help,
) or pod2usage(-message => "use -help", -verbose => 1);

pod2usage(-verbose => 2) if $help;

if ($dry_run) {
  warn "# dry_run option is on. no chages to be stored. (use -dry_run 0 to allow updates)\n";
}


# get core and taxonomy adaptors
my $core_db = new Bio::EnsEMBL::DBSQL::DBAdaptor(
  -host => $host,
  -user => $user,
  -pass => $pass,
  -port => $port,
  -dbname => $dbname,
  -multispecies_db => 1,
);
die "# FAILED cannot connect to the core db. exiting...\n" if !$core_db;
$core_db->dbc->disconnect_if_idle;

my $taxonomy_db = new Bio::EnsEMBL::Taxonomy::DBSQL::TaxonomyDBAdaptor(
  -host => $taxonomy_host,
  -user => $taxonomy_user,
  -port => $taxonomy_port,
  -dbname => $taxonomy_dbname,
  -multispecies_db => 1,
) ;
die "# FAILED cannot connect to the taxonomy db. exiting...\n" if !$taxonomy_db;
$taxonomy_db->dbc->disconnect_if_idle;

# get species id and name
my $sql = "SELECT DISTINCT species_id, meta_value FROM meta WHERE meta_key IN ('species.production_name', 'species.db_name')";
my $species_id_name_raw = $core_db->dbc->sql_helper()->execute(-SQL => $sql);
$core_db->dbc->disconnect_if_idle;

die "# FAILED not able to get any species id. exiting..." if !$species_id_name_raw;

# forming a list of dicts { "id": id, "name" : name }
my @species_id_name =
  grep { !defined $species || $_->{name} eq $species } 
    map { { "id" => $_->[0], "name" => $_->[1] } }
      @$species_id_name_raw;

# variouscounts
my $total_count = scalar(@species_id_name);
my $skipped = 0;
my $failed = 0;
my $ok = 0;

my $unique_ids = scalar(keys %{{ map {$_->{id} => 1} @species_id_name }});
my $unique_names = scalar(keys %{{ map {$_->{name} => 1} @species_id_name }});

warn "# found $total_count species to process ($unique_names unique names, $unique_ids unique ids)\n";
if ($unique_ids != $total_count || $unique_names != $total_count) {
  die "# FAILED $unique_names unique names, $unique_ids unique ids not equal to total count $total_count\n";
}


for my $id_name (@species_id_name) {
  my $species_id = $id_name->{id};
  my $species_name = $id_name->{name};

  if (!defined $species_id) {
    warn "SKIPPED no id for species $species_name\n";
    $skipped++;
    next;
  }

  # reconnect once again (not able to set species_id otherwise)
  $core_db && $core_db->dbc && $core_db->dbc->disconnect_if_idle;
  $core_db = new Bio::EnsEMBL::DBSQL::DBAdaptor(
    -host => $host,
    -user => $user,
    -pass => $pass,
    -port => $port,
    -dbname => $dbname,
    -species => $species_name,
  );
  if (!$core_db) {
    warn "# SKIPPED cannot connect to the core db for species $species_name (species_id $species_id)\n";
    $skipped++;
    next;
  }

  warn "# using species_id $species_id for species $species_name\n";
  $core_db->species_id($species_id);

  my $meta_container = $core_db->get_MetaContainer;
  my $taxon_id = $meta_container->get_taxonomy_id;
  my $sci_name = $meta_container->get_scientific_name;
  my $common_name = $meta_container->get_common_name;

  if (!defined $taxon_id) {
    warn "# SKIPPED no taxonomy id for species $species_name (species_id $species_id)\n";
    $skipped++;
    next;
  }

  warn "# using $taxon_id as taxonomy id for species $species_name (species_id $species_id)\n";
  my $meta_update = get_taxonomy_info($taxonomy_db, $taxon_id, $sci_name, $common_name);

  if (!$meta_update || !@$meta_update) {
    warn "# SKIPPED no taxonomy or names to update for species $species_name (species_id $species_id, taxonomy id $taxon_id)\n";
    $skipped++; 
    next;
  }

  my $updates_cnt = scalar(@$meta_update);
  my @unique_keys = keys %{{ map {$_->[0] => 1} @$meta_update }}; 
  if (!$dry_run && $updates_cnt) {
    foreach my $key (@unique_keys) {
      warn "# dropping key $key\n";
      $meta_container->delete_key($key);
    }
  }

  foreach my $data (@$meta_update) {
    warn "# adding: [ \"", join ('", "', @$data), "\" ]\n";
    $meta_container->store_key_value(@$data) if (!$dry_run);
  }
  $core_db->dbc->disconnect_if_idle;

  if (!$dry_run) {

    my $sql = "SELECT meta_value FROM meta WHERE species_id = $species_id and meta_key IN ('". join("', '", @unique_keys) ."');";
    my $updated = $core_db->dbc->sql_helper()->execute_simple(-SQL => $sql);
    $core_db->dbc->disconnect_if_idle;

    my $updated_cnt = $updated && scalar(@$updated) || 0;
    if ($updated_cnt != $updates_cnt) {
      warn "# FAILED: too few updates ($updated_cnt instead of $updates_cnt) for species $species_name (species_id $species_id, taxonomy id $taxon_id)\n";
      $failed++;
      next;
    }
  } 

  warn "# OK: species $species_name (species_id $species_id, taxonomy id $taxon_id)\n";
  $ok++;
}

$core_db->dbc->disconnect_if_idle;
$taxonomy_db->dbc->disconnect_if_idle;
warn "# TOTAL found $total_count species ($ok processed, $skipped skipped, failed $failed)\n";


# copied from 
#  Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveAssemblyLoading::HiveLoadTaxonomyInfo

sub get_taxonomy_info {

  my ($tax_db, $tax_id, $sci_name, $common_name) = @_;
  my $output = [];

  $tax_db->dbc->disconnect_if_idle;
  my $node_adaptor = $tax_db->get_TaxonomyNodeAdaptor;
  my $node = $node_adaptor->fetch_by_taxon_id($tax_id);
  return $output if !$node;

  # update scientific_name
  if (!defined $sci_name) {
    my $_sci_name = $node->name("scientific name");
    if ($_sci_name) {
      push @$output, [ "species.scientific_name", $_sci_name ]; 
      warn "# updating scientific name for taxonomy id $tax_id with $_sci_name\n";
    }
  }

  # update common_name
  if (!defined $common_name && $update_common_names) {
    my $_common_name = $node->name("genbank common name");
    if ($_common_name) {
      push @$output, [ "species.common_name", $_common_name ]; 
      warn "# updating common name for taxonomy id $tax_id with $_common_name\n";
    }
  }

  my $all_ancestors = $node_adaptor->fetch_ancestors($node);
  foreach my $ancestor ( @$all_ancestors ) {
    next if ($ancestor->rank eq "genus");
    #push @$output, ["species.classification", $ancestor->name, $ancestor->rank];
    push @$output, ["species.classification", $ancestor->name];
    last if ($ancestor->rank eq "superkingdom");
  }

  return $output;
}

