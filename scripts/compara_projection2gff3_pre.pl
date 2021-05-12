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

  compara_projection2gff3.pl

=head1 SYNOPSIS

  get stats for compara based projection and get gff3 with genes

=head1 DESCRIPTION

  stupid and simple comparison for unprojected genes with an effort to fix using shifts

=head1 ARGUMENTS

  perl compara_projection2gff3.pl
         -{from,to}_dbname
         -{from,to}_host
         -{from,to}_port
         -{from,to}_user
         -{from,to}_pass
         -calc_spliced_distance
         -top_genes
         -only_gene
         -source_gff
         -unplaced_ctg
         -placed_ctg
         -exon_inflation_max
         -exons_lost_max
         -exons_gained_max
         -tra_dist_rel_max

=head1 EXAMPLE

  zcat transcripts.gff3.gz | perl compara_projection2gff3.pl \
    $($CMD details script_from_) -from_dbname <from_db_name> \
    $($CMD details script_to_) -to_dbname <to_db_name> \
    -calc_spliced_distance 0 \
    -exon_inflation_max 2.0 \
    -exons_lost_max 1 \
    -exons_gained_max 3 \
    -tra_dist_rel_max 0.47 \
    -unplaced_ctg UNK1 \
    -unplaced_ctg UNK2 \
    -top_genes 10 \
    -source_gff - \
    > patched.pre_gff3  2> from_to_log 

  ./projections_gff3_pre2gff3.sh 'species_name' patche.pre_gff3 from_to_log outdir

=cut

use warnings;
use strict;

use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Getopt::Long;
use Pod::Usage qw/pod2usage/;
use Text::Levenshtein::Damerau::XS qw/xs_edistance/; 
use List::Util qw/max min sum sum0/;

# GET OPTIONS

my ($from_host, $from_port, $from_user, $from_pass, $from_dbname);
my ($to_host, $to_port, $to_user, $to_pass, $to_dbname);
my ($calc_spliced_distance, $top_genes, $source_gff);
my ($exon_inflation_max, $exons_lost_max, $exons_gained_max, $tra_dist_rel_max);
my @placed_ctg =  ();
my @unplaced_ctg =  ();
my @only_genes = ();
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

  'source_gff=s'   => \$source_gff,

  'calc_spliced_distance' => \$calc_spliced_distance,
  'top_genes=i' => \$top_genes,
  'only_gene=s' => \@only_genes,

  'placed_ctg=s' => \@placed_ctg,
  'unplaced_ctg=s' => \@unplaced_ctg,
  'exon_inflation_max=f' => \$exon_inflation_max,
  'exons_lost_max=i' => \$exons_lost_max,
  'exons_gained_max=i' => \$exons_gained_max,
  'tra_dist_rel_max=f' => \$tra_dist_rel_max,

  'help|?'      => \$help,
) or pod2usage(-message => "use -help", -verbose => 1);

pod2usage(-verbose => 2) if $help;


# CORE DBs AND ADAPTORS
my $from_core_db = new Bio::EnsEMBL::DBSQL::DBAdaptor( -host => $from_host, -user => $from_user, -pass => $from_pass, -port => $from_port, -dbname => $from_dbname );
my $to_core_db = new Bio::EnsEMBL::DBSQL::DBAdaptor( -host => $to_host, -user => $to_user, -pass => $to_pass, -port => $to_port, -dbname => $to_dbname );

my $from_ga = $from_core_db->get_adaptor("Gene");
my $to_ta = $to_core_db->get_adaptor("Transcript");

# globals
my $COL2KEY_TR ={};
my $COL2KEY_GN = {};
my $PON = { (map { $_=> 1} @placed_ctg), (map {$_ => -1} @unplaced_ctg) };
my $GENES_OF_INTEREST = { map {$_ =>1} @only_genes };

#dump conf
my @conf = ();
push @conf, "calc_spliced_distance\t$calc_spliced_distance" if defined $calc_spliced_distance;
push @conf, "source_gff\t$source_gff" if defined $source_gff;
push @conf, "exon_inflation_max\t$exon_inflation_max" if defined $exon_inflation_max;
push @conf, "exons_lost_max\t$exons_lost_max" if defined $exons_lost_max;
push @conf, "exons_gained_max\t$exons_gained_max" if defined $exons_gained_max;
push @conf, "tra_dist_rel_max\t$tra_dist_rel_max" if defined $tra_dist_rel_max;
push @conf, "placed_ctg\t" . join(",", @placed_ctg) if @placed_ctg;
push @conf, "unplaced_ctg\t" . join(",", @unplaced_ctg) if @unplaced_ctg;
push @conf, "top_genes=$top_genes" if defined $top_genes;
push @conf, "only_genes\t" . join(",", @only_genes) if @only_genes;
for my $c (@conf) {
  warn "#CONF\t$c\n";
}

# MAIN
my $st = {};
my $src_genes =  $from_ga->fetch_all_by_biotype('protein_coding');
if ($src_genes) {
  my $gene_stat = {};
  while (my $gene = shift @{$src_genes}) {
     next if (%$GENES_OF_INTEREST && !exists $GENES_OF_INTEREST->{$gene->stable_id});

     my $tr_stat = {
       src_tr_count => 0,
       trg_tr_count => 0,
       trg_tr_conserved_tra => 0,
     };

     # source gene
     $st->{src_genes}++;
     my $src_tr_canon;
     my $src_trs = c2s($gene->get_all_Transcripts, $st, 'src_genes_w_trns', 'src_genes_wo_trns');
     if ($src_trs) {
       $src_tr_canon = c2s($gene->canonical_transcript, $st, 'src_genes_w_canon_tr', 'src_genes_wo_canon_tr');
       for my $src_tr (@$src_trs) {
         $st->{src_tr}++;
         $src_tr = c2s($src_tr, $st, undef, 'src_tr_empty');
         if (my $src_tra = c2s(get_seq($src_tr->translate), $st, 'src_tr_w_tra', 'src_tr_wo_tra')) {  
           $tr_stat->{src_tr_count}++;
           # get src utrs, exons, etc
           my $src_5_utr = c2s(get_seq($src_tr->five_prime_utr), $st, 'src_tr_w_5_utr','src_tr_wo_5_utr');
           my $src_3_utr = c2s(get_seq($src_tr->three_prime_utr), $st, 'src_tr_w_3_utr','src_tr_wo_3_utr');
           my $src_exons = $src_tr->get_all_Exons(); 
           my $stable_id = $src_tr->stable_id;
 
           # projection
           if (my $trg_tr = c2s($to_ta->fetch_by_stable_id($stable_id), $st, 'trg_tr_projected')) {
             if (my $trg_tra = c2s(get_seq($trg_tr->translate), $st, 'trg_tr_w_tra', 'trg_tr_wo_tra')) {
               my $trg_5_utr = c2s(get_seq($trg_tr->five_prime_utr), $st, 'trg_tr_w_5_utr','trg_tr_wo_5_utr');
               my $trg_3_utr = c2s(get_seq($trg_tr->three_prime_utr), $st, 'trg_tr_w_3_utr','trg_tr_wo_3_utr');
               my $trg_exons = $trg_tr->get_all_Exons(); 

               # compare
               smaller_larger(scalar(@$src_exons), scalar(@$trg_exons), $st, 'trg_tr_exon_num');
               my $tra_len_diff = shorter_longer($src_tra, $trg_tra, $st, 'trg_tra');
               if (c2s($tra_len_diff != 0, $st, undef, 'trg_tra_len_changed')) {
                 $tr_stat->{trg_tr_conserved_tra}++;
                 my $utr5_len_diff = shorter_longer($src_5_utr, $trg_5_utr, $st, 'trg_tra_5_utr');
                 my $utr3_len_diff = shorter_longer($src_3_utr, $trg_3_utr, $st, 'trg_tra_3_utr');
               } # tra_len_diff
               stash_tr($tr_stat, $gene,
                       $src_tr, $src_tra, $src_exons, $trg_tr, $trg_tra, $trg_exons,
                       $src_5_utr, $src_3_utr, $trg_5_utr, $trg_3_utr);
             } else {
               stash_tr($tr_stat, $gene, $src_tr, $src_tra, $src_exons, $trg_tr);
             } #trg_tra 
           } else {
             stash_tr($tr_stat, $gene, $src_tr, $src_tra, $src_exons);
           } #trg_tr
         } else {
           stash_tr($tr_stat, $gene, $src_tr);
         } # src_tra
       }# for src_tr      
     } # src_trs
     stash_gene($gene_stat, $gene, $src_tr_canon, $tr_stat);
     last if (defined $top_genes && $top_genes > 0 && $st->{src_genes} >= $top_genes);
  } # gene
  dump_genes($gene_stat);
} # src_genes


sub stash_tr {
  my ($tr_stat, $gene, $src_tr,
      $src_tra, $src_exons,
      $trg_tr,
      $trg_tra, $trg_exons, $src_5_utr, $src_3_utr, $trg_5_utr, $trg_3_utr) = @_; 

  $tr_stat->{src_tr}++;

  my @out = ();
  push @out, (
    { SRC_NAME => $src_tr->stable_id },
    { SRC_ID => $src_tr->dbID },
    { SRC_GENE_NAME =>$gene->stable_id },
    { SRC_GENE_ID => $gene->dbID },
    { SRC_CTG => $src_tr->seq_region_name },
    { SRC_START => $src_tr->seq_region_start  },
    { SRC_END => $src_tr->seq_region_end },
    { SRC_STRAND => $src_tr->seq_region_strand > 0 ?  "+" : "-" },
  );
  if (!$src_tra) {
    $tr_stat->{no_src_tra}++;
    unshift @out, ( {STATUS => "FAIL_NO_SRC_TRA"});
    out2stash($tr_stat, 'TRANSCRIPT', @out); 
    return;
  }
  $tr_stat->{src_tra}++;

  my $src_exons_num = scalar(@$src_exons);
  push @out, (
    { SRC_EXONS       => $src_exons_num },
    { SRC_SPLICED_LEN => length($src_tr->spliced_seq || "") },
    { SRC_CDS_LEN     => length($src_tr->translateable_seq || "") },
    { SRC_TRA_LEN     => length($src_tra) },
  );
  if (!$trg_tr) {
    $tr_stat->{no_trg_tr}++;
    unshift @out, ( {STATUS => "FAIL_NO_TRG_TR"});
    out2stash($tr_stat, 'TRANSCRIPT', @out); 
    return;
  }
  $tr_stat->{trg_tr}++;
  
  push @out, (
    { TRG_CTG => $trg_tr->seq_region_name },
    { TRG_START => $trg_tr->seq_region_start  },
    { TRG_END => $trg_tr->seq_region_end },
    { TRG_STRAND => $trg_tr->seq_region_strand > 0 ?  "+" : "-" },
  );
  if (!$trg_tra) {
    $tr_stat->{no_trg_tra}++;
    unshift @out, ( {STATUS => "FAIL_NO_TRG_TRA"});
    out2stash($tr_stat, 'TRANSCRIPT', @out); 
    return;
  }
  $tr_stat->{trg_tra}++;

  $src_5_utr = defined $src_5_utr && $src_5_utr || "";
  $trg_5_utr = defined $trg_5_utr && $trg_5_utr || "";

  $src_3_utr = defined $src_3_utr && $src_3_utr || "";
  $trg_3_utr = defined $trg_3_utr && $trg_3_utr || "";

  push @out, (
    { TRG_EXONS       => scalar(@$trg_exons) },
    { TRG_SPLICED_LEN => length($trg_tr->spliced_seq || "") },
    { TRG_CDS_LEN     => length($trg_tr->translateable_seq || "") },
    { TRG_TRA_LEN     => length($trg_tra) },
    { SRC_5_UTR_LEN   => length($src_5_utr) },
    { SRC_3_UTR_LEN   => length($src_3_utr) },
    { TRG_5_UTR_LEN   => length($trg_5_utr) },
    { TRG_3_UTR_LEN   => length($trg_3_utr) },
  );

  my $trg_exons_num = scalar(@$trg_exons);
  if (defined $exon_inflation_max) {
    my $infl = calc_exon_inflation($src_exons_num, $trg_exons_num);
    if (defined $infl && $infl > $exon_inflation_max) {
      $tr_stat->{trg_tr_exon_inflation_too_high}++;
      $st->{trg_tr_exon_inflation_too_high}++;
      unshift @out, ( {STATUS => "FAIL_EXON_INFLATION"});
      out2stash($tr_stat, 'TRANSCRIPT', @out); 
      return;
    }
    $tr_stat->{trg_tr_exon_inflation_ok}++;
    $st->{trg_tr_exon_inflation_ok}++;
  }

  my $exons_num_diff = $trg_exons_num - $src_exons_num;
  if (defined $exons_lost_max) {
    if ( ($exons_num_diff + $exons_lost_max) < 0 ) {
      $tr_stat->{trg_tr_exons_lost_too_high}++;
      $st->{trg_tr_exons_lost_too_high}++;
      unshift @out, ( {STATUS => "FAIL_EXON_LOST"});
      out2stash($tr_stat, 'TRANSCRIPT', @out); 
      return;
    }
    $tr_stat->{trg_tr_exons_lost_ok}++;
    $st->{trg_tr_exons_lost_ok}++;
  }
  if (defined $exons_gained_max) {
    if ( ($exons_num_diff - $exons_gained_max) > 0 ) {
      $tr_stat->{trg_tr_exons_gain_too_high}++;
      $st->{trg_tr_exons_gain_too_high}++;
      unshift @out, ( {STATUS => "FAIL_EXON_GAIN"});
      out2stash($tr_stat, 'TRANSCRIPT', @out); 
      return;
    }
    $tr_stat->{trg_tr_exons_gain_ok}++;
    $st->{trg_tr_exons_gain_ok}++;
  }

  my ($status, $tra_status, $tra_dist, $tra_dist_rel);
  if (length($src_tra) == length($trg_tra)) {
    $status = "OK";
    if ($src_tra eq $trg_tra) {
      $tra_status = "OK";
      ($src_tra, $trg_tra) = ('', '');
      $tra_dist = 0;
      $tra_dist_rel = 0;
    } else { 
      $tra_status = "OK_TRA_LEN_SAME";
    }
    $tr_stat->{trg_tra_ok}++;
  } else {
    $status = "CHANGED";
    $tra_status  = "TRA_CHANGED";  
    $tr_stat->{trg_tra_changed}++;
  }


  my $tra_len_sum = length($src_tra) + length($trg_tra);
  $tra_dist = xs_edistance($src_tra, $trg_tra); 
  $tra_dist_rel = $tra_len_sum && ($tra_dist / $tra_len_sum) || 0; 
   
  my $utr_5_status = "UTR_5_OK";
  $utr_5_status = "UTR_5_OK_EMPTY" if (!$src_5_utr && !$trg_5_utr);
  if ($src_5_utr ne $trg_5_utr) {
    $utr_5_status = "UTR_5_CHANGED";
    $utr_5_status = "UTR_5_LOST" if ($src_5_utr && !$trg_5_utr);
    $utr_5_status = "UTR_5_GAINED" if (!$src_5_utr && $trg_5_utr);
  }

  my $utr_3_status = "UTR_3_OK";
  $utr_3_status = "UTR_3_OK_EMPTY" if (!$src_3_utr && !$trg_3_utr);
  if ($src_3_utr ne $trg_3_utr) {
    $utr_3_status = "UTR_3_CHANGED";
    $utr_3_status = "UTR_3_LOST" if ($src_3_utr && !$trg_3_utr);
    $utr_3_status = "UTR_3_GAINED" if (!$src_3_utr && $trg_3_utr);
  }

  my $utr_5_len_sum = length($src_5_utr) + length($trg_5_utr);
  my $utr_3_len_sum = length($src_3_utr) + length($trg_3_utr);

  ($src_5_utr, $trg_5_utr) = ('', '') if ($src_5_utr eq $trg_5_utr);
  ($src_3_utr, $trg_3_utr) = ('', '') if ($src_3_utr eq $trg_3_utr);

  ($src_5_utr, $trg_5_utr) = ('', '') if (!$src_5_utr || !$trg_5_utr);
  ($src_3_utr, $trg_3_utr) = ('', '') if (!$src_3_utr || !$trg_3_utr);
  
  my $utr_5_dist = xs_edistance($src_5_utr, $trg_5_utr); 
  $utr_5_dist = $utr_5_len_sum if (0 == length($src_5_utr) + length($trg_5_utr));  
  my $utr_5_dist_rel = $utr_5_len_sum && ($utr_5_dist / $utr_5_len_sum) || 0;

  my $utr_3_dist = xs_edistance($src_3_utr, $trg_3_utr); 
  $utr_3_dist = $utr_3_len_sum if (0 == length($src_3_utr) + length($trg_3_utr));  
  my $utr_3_dist_rel = $utr_3_len_sum && ($utr_3_dist / $utr_3_len_sum) || 0;
  
  my ($spliced_dist, $spliced_dist_rel) = (-1, -1);
  my $src_spliced_seq = $src_tr->spliced_seq() || "";
  my $trg_spliced_seq = $trg_tr->spliced_seq() || "";
  my $spliced_len_sum = length($src_spliced_seq) + length($trg_spliced_seq);
  if ($calc_spliced_distance) {
    $spliced_dist = xs_edistance($src_spliced_seq, $trg_spliced_seq);
    $spliced_dist_rel = $spliced_len_sum && ($spliced_dist / $spliced_len_sum) || 0;
  }

  push @out, (
    { TRA_STATUS   => $tra_status },
    { UTR_5_STATUS => $utr_5_status },
    { UTR_3_STATUS => $utr_3_status },

    { TRA_DIST     => $tra_dist },
    { TRA_DIST_REL => $tra_dist_rel },
    { TRA_LEN_SUM  => $tra_len_sum },

    { UTR_5_DIST     => $utr_5_dist },
    { UTR_5_DIST_REL => $utr_5_dist_rel },
    { UTR_5_LEN_SUM  => $utr_5_len_sum },

    { UTR_3_DIST     => $utr_3_dist },
    { UTR_3_DIST_REL => $utr_3_dist_rel },
    { UTR_3_LEN_SUM  => $utr_3_len_sum },

    { TR_SPLICED_DIST     => $spliced_dist },
    { TR_SPLICED_DIST_REL => $spliced_dist_rel },
    { TR_SPLICED_LEN_SUM  => $spliced_len_sum },

    { SRC_TRA      => $src_tra },
    { TRG_TRA      => $trg_tra },
    { SRC_5_UTR    => $src_5_utr },
    { SRC_3_UTR    => $src_3_utr },
    { TRG_5_UTR    => $trg_5_utr },
    { TRG_3_UTR    => $trg_3_utr },
  );

  if (defined $tra_dist_rel_max) {
    if ( $tra_dist_rel > $tra_dist_rel_max ) {
      $tr_stat->{trg_tra_dist_too_high}++;
      $st->{trg_tra_dist_too_high}++;
      unshift @out, ( {STATUS => "FAIL_TRA_DIST"});
      out2stash($tr_stat, 'TRANSCRIPT', @out); 
      return;
    }
    $tr_stat->{trg_tra_dist_ok}++;
    $st->{trg_tra_dist_ok}++;
  }

  unshift @out, ({STATUS => $status});
  out2stash($tr_stat, 'TRANSCRIPT', @out); 
}

sub out2stash {
  my ($stash, $tag,  @data) = @_;
  my @keys = map { keys %$_ } @data;
  my @values = map { values %$_ } @data;
  if (@keys && (!exists $stash->{keys} || scalar(@{$stash->{keys}}) < scalar(@keys))) {
    $stash->{keys} = \@keys;
    update_keys_col(($tag eq "GENE") ? $COL2KEY_GN : $COL2KEY_TR, \@keys); # ugly -- use tag instead for keys 
  }
  $stash->{values} = [] if (!exists $stash->{values}); 
  push @{$stash->{values}}, \@values if (@values);
}

sub update_keys_col {
  my ($map, $keys) = @_;
  return if (scalar(%$map) >= scalar(@$keys));
  my $col = 0;
  for my $k (@$keys) {
    my $pcol = $map->{$k};
    warn("UPDATE COL KEY $k PREV $pcol NEW $col\n") if (defined $pcol and $pcol != $col); 
    $map->{$k} = $col;
    $col++;
  }
}

# gen global keys
sub stash_gene {
  my ($gene_stat, $gene, $src_tr_canon, $tr_stat) = @_; 

  # dump transcripts
  if (exists $tr_stat->{keys}) {
    print join("\t", "TRANSCRIPT", @{$tr_stat->{keys}}), "\n";  
    for my $tr (@{$tr_stat->{values} || []}) {
      print join("\t", "TRANSCRIPT", @$tr), "\n";  
    }
  }
  
  # process genes
  $st->{trg_genes}++;

  # tr data keys
  my $STATUS_C = $COL2KEY_TR->{STATUS};
  my $SRC_NAME_C = $COL2KEY_TR->{SRC_NAME};
  my $TRG_CTG_C = $COL2KEY_TR->{TRG_CTG};
  my $TRG_START_C = $COL2KEY_TR->{TRG_START};
  my $TRG_END_C = $COL2KEY_TR->{TRG_END};
  my $TRG_STRAND_C = $COL2KEY_TR->{TRG_STRAND};
  my $TRG_TRA_LEN_C = $COL2KEY_TR->{TRG_TRA_LEN};
  my $SRC_EXONS_C = $COL2KEY_TR->{SRC_EXONS};
  my $TRG_EXONS_C = $COL2KEY_TR->{TRG_EXONS};
  my $TRA_DIST_REL_C = $COL2KEY_TR->{TRA_DIST_REL};

  my @tr_values = @{$tr_stat->{values} || []};

  #strands and contigs
  my @ctgs = map {$_->[$TRG_CTG_C]} @tr_values;
  my @strands = map {$_->[$TRG_STRAND_C]} @tr_values;
  my %ctg_strand = ();
  for (my $i = 0; $i < scalar(@ctgs); $i++) {
    next if (!$ctgs[$i]);
    my $k = $ctgs[$i].":".$strands[$i];
    $ctg_strand{$k}++;  
  } 

  # canonical  
  my $src_tr_canon_name = $src_tr_canon->stable_id || "";
  my @canonicals = grep {$_->[$SRC_NAME_C] eq $src_tr_canon_name} @tr_values;

  my $canon_status = "CANON_TR_FAILED";
  if (!$src_tr_canon_name) {
    $canon_status = "CANON_TR_OK_EMPTY";
  } else {
    if (scalar @canonicals > 0) {
      my @vals = split(/_/, $canonicals[0]->[$STATUS_C]);
      $canon_status = "CANON_TR_".$vals[0];
    } else {
      $canon_status = "CANON_TR_FAIL"; 
    }
  }

  my $status = "OK";
  
  # split_gene
  my $parts = scalar(%ctg_strand);
  my $gene_splitted = $parts > 1;  
  if ($gene_splitted) {
    $status = "SPLITTED";
    $st->{trg_genes_splitted}++;
  }
  my $parts_pfx = ($parts > 1) ? "PART_" : "";
  my $parts_sfx = ($parts > 1) ? "_part" : "";


  my @sorted_keys = sort { $ctg_strand{$b} <=> $ctg_strand{$a} } keys %ctg_strand;
  push @sorted_keys, "" if (!@sorted_keys);

  my $part = 0;
  for my $csk ( @sorted_keys ) {
    $st->{"trg_gene${parts_sfx}"}++;
    $part++;
    # use $gsfx to append to tr names, fix canonical 
    my $gsfx = ($gene_splitted)? "_p$part" : "";

    my ($ctg, $strand) = split /:/, $csk;
    $ctg = defined $ctg && $ctg || "";
    $strand = defined $strand && $strand || "";

    my @tr_values_part = grep {
                               defined $_->[$TRG_CTG_C]
                            && defined $_->[$TRG_STRAND_C]
                            && $_->[$TRG_CTG_C] eq $ctg
                            && $_->[$TRG_STRAND_C] eq $strand
                         } @tr_values;

    my @part_canonicals = grep {($_->[$SRC_NAME_C] || "") eq $src_tr_canon_name} @tr_values_part;
    $canon_status = "CANON_TR_OTHER_PART @part_canonicals" if (scalar(@part_canonicals) == 0 && scalar(@canonicals) > 0);

    my $trg_gene_stable_id = $gene->stable_id . $gsfx;

    my @out = ();
    push @out, (
      { SRC_NAME => $gene->stable_id },
      { TRG_NAME => $trg_gene_stable_id },

      { SPLITTED_STATUS => ($gene_splitted)? "WAS_SPLITTED" : "NOT_SPLITTED"}, 
      { PARTS => $parts },
      { PART => $part },

      { SRC_ID => $gene->dbID },
      { SRC_CTG => $gene->seq_region_name },
      { SRC_START => $gene->seq_region_start  },
      { SRC_END => $gene->seq_region_end },
      { SRC_STRAND => $gene->seq_region_strand > 0 ?  "+" : "-" },

      { SRC_TR_NUM => $tr_stat->{src_tr} || 0 },
      { TRG_TR_NUM => $tr_stat->{trg_tr} || 0 },
      { TR_STATUS => (($tr_stat->{src_tr} || 0) == ($tr_stat->{trg_tr} || 0) ) ? "TR_OK" : "TR_NUM_DIFF" }, 

      { CANON_TR_STATUS => $canon_status },
    );
    if (scalar(@tr_values) == 0) {
      unshift @out, ({STATUS => "FAIL_NO_TR"});
      out2stash($gene_stat, 'GENE', @out); 
      $st->{trg_gene_wo_tr}++;
      next;
    }

    $gene_stat->{src_ctg4gene}->{$trg_gene_stable_id} = $gene->seq_region_name;
    
    my $tra_status = "TRA_UNK";
    if ($tr_stat->{src_tra} == 0) {
      my $tra_status = "TRA_OK_EMPTY";
    } else {
      $tra_status = ($tr_stat->{src_tra} == ($tr_stat->{trg_tra} || 0)) ? "TRA_OK" : "TRA_NUM_DIFF";
    }

    push @out, (
      { SRC_TRA_NUM => $tr_stat->{src_tra} || 0 },
      { TRG_TRA_NUM => $tr_stat->{trg_tra} || 0 },
      { TRG_TRA_OK => $tr_stat->{trg_tra_ok} || 0 },
      { TRG_TRA_CHANGED => $tr_stat->{trg_tra_changed} || 0 },
      { TRA_STATUS => $tra_status }, 
    );

    if (scalar(@tr_values_part) == 0) {
      unshift @out, ({STATUS => ($parts > 1) ? "PART_FAIL_NO_TR" : "FAIL_NO_TR"});
      out2stash($gene_stat, 'GENE', @out); 
      $st->{"trg_gene${parts_sfx}_wo_tr"}++;
      next;
    }
    $st->{"trg_gene${parts_sfx}_w_tr"}++;

    my @part_tr_stable_ids = map { $_->[$SRC_NAME_C] } @tr_values_part;
    $gene_stat->{tr4gene}->{$trg_gene_stable_id} = \@part_tr_stable_ids;
    $gene_stat->{descr4gene}->{$trg_gene_stable_id} = $gene->description;
    
    # exon_inflation
    my @inflations = map { calc_exon_inflation($_->[$SRC_EXONS_C], $_->[$TRG_EXONS_C]) || 0 } @tr_values_part;
    my $inflation_avg = scalar(@inflations) > 0 ? sum0(@inflations) / scalar(@inflations) : 1e5;
    $gene_stat->{exon_inflation_avg4gene}->{$trg_gene_stable_id} = $inflation_avg;
    my @tra_rel_dists = grep {defined $_} map { $_->[$TRA_DIST_REL_C] } @tr_values_part;
    my $tra_rel_dist_avg = scalar(@tra_rel_dists) > 0 ? sum0(@tra_rel_dists) / scalar(@tra_rel_dists) : 1e5;
    $gene_stat->{tra_dist_rel_avg4gene}->{$trg_gene_stable_id} = $tra_rel_dist_avg;

    my $trg_start = min( map {$_->[$TRG_START_C]} @tr_values_part ); 
    my $trg_end = max( map {$_->[$TRG_END_C]} @tr_values_part ); 
    push @out, (
      { TRG_CTG => $ctg },
      { TRG_START => $trg_start },
      { TRG_END => $trg_end },
      { TRG_STRAND => $strand },
    );

    my @tra_len = map {$_->[$TRG_TRA_LEN_C] || 0} @tr_values_part;
    if (scalar( grep {$_ > 0} @tra_len)  == 0 ) {
      unshift @out, ({STATUS => ($parts > 1) ? "PART_FAIL_NO_TRA" : "FAIL_NO_TRA"});
      out2stash($gene_stat, 'GENE', @out); 
      $st->{"trg_gene${parts_sfx}_wo_tra"}++;
      next;
    } 

    # check for parts status
    my @part_st_status = map {$_->[$STATUS_C]} @tr_values_part;
    my $part_st_any = scalar(@part_st_status);
    my $part_st_ok = scalar( grep {$_ eq "OK"} @part_st_status);
    my $part_st_changed = scalar( grep {$_ eq "CHANGED"} @part_st_status);
    my $part_st_failed = scalar( grep {$_ =~ m/^FAIL/} @part_st_status);

    # push parts stat
    push @out, (
      { TRG_TR_OK => $part_st_ok },
      { TRG_TR_CHANGED => $part_st_changed },
      { TRG_TR_FAILED => $part_st_failed },
    );
    
    if ($part_st_any == $part_st_ok) {
      $status = "${parts_pfx}OK";
      $st->{"trg_gene${parts_sfx}_ok"}++;
    } 

    if ($part_st_changed > 0) {
      $status = "${parts_pfx}CHANGED_FEW_TR";
      $st->{"trg_gene${parts_sfx}_changed_few"}++;
    } 
    if ($part_st_any == $part_st_changed) {
      $status = "${parts_pfx}CHANGED";
      $st->{"trg_gene${parts_sfx}_changed_few"}--;
      $st->{"trg_gene${parts_sfx}_changed"}++;
    }

    if ($part_st_failed > 0) {
      $status = "${parts_pfx}FAILED_FEW_TR";
      $st->{"trg_gene${parts_sfx}_failed_few"}++;
    }
    if ($part_st_any == $part_st_failed) {
      $status = "${parts_pfx}FAILED";
      $st->{"trg_gene${parts_sfx}_failed_few"}--;
      $st->{"trg_gene${parts_sfx}_failed"}++;
    }

    unshift @out, ({ STATUS => $status });
    out2stash($gene_stat, 'GENE', @out);
  } # ctg strand key 
}

sub dump_genes {
  my ($gene_stat) = @_; 
  # dump transcripts
  if (exists $gene_stat->{keys}) {
    print join("\t", "GENE", @{$gene_stat->{keys}}), "\n";  
    for my $gn (@{$gene_stat->{values} || []}) {
      print join("\t", "GENE", @$gn), "\n";  
    }

    process_overlaps($gene_stat);
    process_gff($source_gff, $gene_stat);
  }
}

sub process_gff {
  my ($source_gff, $gene_stat) = @_;
  my $values = $gene_stat->{values};
  my $tr4 = $gene_stat->{tr4gene};
  my $descr4 = $gene_stat->{descr4gene};

  my $ovs4 = $gene_stat->{overlaps4gene};
  my $ovs4unstranded = $gene_stat->{overlaps_unstranded4gene};
  my $ovs_filter = $gene_stat->{overlaps_filter};

  my $merged4 = $gene_stat->{merged4gene};
  my $merged4unstranded = $gene_stat->{merged_unstranded4gene};
  my $merge_filter = $gene_stat->{merge_filter};

  my %gff_preced = (
     chromosome => 1,
     gene => 2,
     mRNA => 3,
     exon => 4,
     CDS => 5,
     undefined => 9,
  );

  return if !( defined $source_gff);

  my $in_gff;
  if ($source_gff eq "-") {
    $in_gff = *STDIN;
  } else {
    open($in_gff, "<", $source_gff) or return;
  }

  my $TRG_NAME_C = $COL2KEY_GN->{TRG_NAME};
  my $SRC_ID_C = $COL2KEY_GN->{SRC_ID};
  my $SRC_CTG_C = $COL2KEY_GN->{SRC_CTG};
  my $TRG_CTG_C = $COL2KEY_GN->{TRG_CTG};
  my $TRG_START_C = $COL2KEY_GN->{TRG_START};
  my $TRG_END_C = $COL2KEY_GN->{TRG_END};
  my $TRG_STRAND_C = $COL2KEY_GN->{TRG_STRAND};

  my $tr2gene = {};
  for my $gene (keys %$tr4) {
    for my $tr (@{$tr4->{$gene} || []}) {
      $tr2gene->{$tr} = $gene;
    }
  }

  # dump genes gff3 lines
  my @gff_out = ();
  for my $gnline (sort {$a->[$TRG_NAME_C] cmp $b->[$TRG_NAME_C]} @$values) {
    my ($name, $id,  $ctg, $start, $end, $strand) =
            map {$gnline->[$_]} ($TRG_NAME_C, $SRC_ID_C, $TRG_CTG_C, $TRG_START_C, $TRG_END_C, $TRG_STRAND_C);

    next if (!exists $tr4->{$name});

    # merged and overlapping filters
    next if (exists $merge_filter->{$name});
    next if (exists $ovs_filter->{$name});

    my $descr = $descr4->{$name};
    $descr =~ s/;/%3B/g if ($descr);

    my $nid = "${name}:${id}";

    my @mrg = exists $merged4->{$name} ? @{$merged4->{$name}} : ();
    my @mrg_uns = exists $merged4unstranded->{$name} ? @{$merged4unstranded->{$name}} : ();

    my @ovs = exists $ovs4->{$name} ? grep { !exists $merge_filter->{$_} } @{$ovs4->{$name}} : ();
    my @ovs_uns = exists $ovs4unstranded->{$name} ? grep { !exists $merge_filter->{$_} } @{$ovs4unstranded->{$name}} : ();

    my $note = "";
    if (@mrg) { $note .= ($note ? "," : "") . "MERGED:" . join('|', @mrg); }
    if (@mrg_uns) { $note .= ($note ? "," : "") . "MERGED_UNSTRANDED:" . join('|', @mrg_uns); }
    if (@ovs) { $note .= ($note ? "," : "") . "OVERLAPS:" . join('|', @ovs); }
    if (@ovs_uns) { $note .= ($note ? "," : "") . "OVERLAPS_UNSTRANDED:" . join('|', @ovs_uns); }

    my @attribs = ();
    push @attribs, [ 'ID', $name ]; 
    push @attribs, [ 'biotype', 'protein_coding' ];
    push @attribs, [ 'description', $descr ] if ($descr);
    push @attribs, [ 'note', $note ] if ($note);
    my $attr_new = join (';', map {$_->[0].'='.$_->[1]} @attribs);
    push @gff_out, join ("\t", $gff_preced{gene}, "GFF3", $ctg, "ensembl", "gene", $start, $end, ".", $strand, ".", $attr_new);
  }

  # read and patch gff3
  my $ignore_if_parent = { map {$_ => 1} ((keys %$ovs_filter), (keys %$merge_filter)) };

  while (<$in_gff>) {
    next if (m/^#/);

    chomp;
    my ($ctg, $source, $tag, $start, $end, $score, $strand, $frame, $attr) = split /\t/;   

    next if ($tag eq "gene");

    my @attr_keys_order = map {$1 if m/^([^=]+)=/} split(/;/, $attr); 
    my $attrs = { map {$1 => $2 if m/^([^=]+)=(.*)$/} split(/;/, $attr) };

    # mRNA
    if ($tag eq "transcript") {
      $tag = "mRNA";
      $attrs->{biotype} = "protein_coding";

      my $parent = $tr2gene->{$attrs->{ID}};
      if (!$parent) {
        warn "ERR\tTRANSCRIPT $attrs->{ID} has no parent: $_ \n"; 
      } else {
        push @attr_keys_order, "Parent" if (!exists $attrs->{Parent});
        $attrs->{Parent} = $parent;
      }
    }

    # exon, CDS
    if ($tag eq "exon" || $tag eq "CDS") {
      delete $attrs->{Name};
      $attrs->{ID} =~ s/-R(.+)$/-P$1/ if ($attrs->{ID});
    }
    if ($tag eq "CDS") {
      push @attr_keys_order, "protein_id" if (!exists $attrs->{protein_id});
      $attrs->{protein_id} = $attrs->{ID}; 
    }

    # filtering
    my $filtered_ID = exists $attrs->{ID} && exists $ignore_if_parent->{$attrs->{ID}};
    my $filtered_parent = exists $attrs->{Parent} && exists $ignore_if_parent->{$attrs->{Parent}};
    if ($filtered_ID || $filtered_parent) {
      $ignore_if_parent->{$attrs->{ID}} = 1 if (exists $attrs->{ID});
      next;
    } 
    
    # dump
    my $attr_new = join (';', map { $_."=".$attrs->{$_} }
                               grep {exists $attrs->{$_} and defined $attrs->{$_}} @attr_keys_order);
    push @gff_out, join("\t", $gff_preced{$tag} || $gff_preced{undefined}, "GFF3", $ctg, $source, $tag, $start, $end, $score, $strand, $frame, $attr_new);
  }

  close ($in_gff) if ($source_gff ne "-");
  for my $s (sort @gff_out) {
    $s =~ s/^\d+\t//;
    print $s, "\n";
  }
}

sub pon4 {
  my ($name_id, $src_ctg) = @_;
  my ($name, $id) = split /:/, $name_id;
  return 0 if (!exists $src_ctg->{$name});
  return 0 if (!exists $PON->{$src_ctg->{$name}});
  return $PON->{$src_ctg->{$name}};
}

sub nm4 {
  my ($name_id) = @_;
  my ($name, $id) = split /:/, $name_id;
  return $name;
}


sub process_overlaps {
  my ($gene_stat) = @_;

  return if (!exists $gene_stat->{keys});

  my @pre_o = ();
  get_gene_coords(\@pre_o, $gene_stat->{values}, $COL2KEY_GN);
  get_gene_coords(\@pre_o, $gene_stat->{values}, $COL2KEY_GN, ".");
  my @gng_keys = qw/name id ctg start end strand/;

  my $og = {};
  my $merged_genes = {};

  # gather overlapping and merged loci
  my @sorted = sort {  
                     $a->{ctg} cmp $b->{ctg}   || $a->{strand} cmp $b->{strand}
                || $a->{start} <=> $b->{start} ||    $b->{end} <=> $a->{end}
                   } @pre_o;

  my @st = ();
  for my $gn ( @sorted ) {
    if (!$gn || ! defined $gn->{ctg}) { next; }     
    if (!@st ) { push @st, $gn; next; }

    my $head = $st[-1];
    if ($gn->{ctg} ne $head->{ctg}) { @st = ( $gn ); next; }
    if ($gn->{strand} ne $head->{strand}) { @st = ( $gn ); next; }

    # warning: accumulates not intersecting intervals 
    while ($head->{end} < $gn->{start}) {
      pop @st;
      last if (!@st);
      $head = $st[-1];
    } 

    my $gn_id = $gn->{name}.":".$gn->{id};
    my $strand = $gn->{strand};
    for my $g (@st) {
      if ($g->{end} >= $gn->{start}) {
        my $g_id = $g->{name}.":".$g->{id};

        if ($g->{start} == $gn->{start} && $g->{end} == $gn->{end}) {
          my $k = join("\t", map {$gn->{$_}} qw/ctg start end strand/);
          $merged_genes->{$k}->{$gn_id} = 1;
          $merged_genes->{$k}->{$g_id} = 1;
        } else {
          $og->{$strand}->{$gn_id}->{$g_id} = [ $gn, $g ];
          $og->{$strand}->{$g_id}->{$gn_id} = [ $g, $gn ];
        }
      }
    }

    push @st, $gn;
  }
 
  # dump out merged and overlapping
  my $src_ctg = $gene_stat->{src_ctg4gene};

  # dump overlapping loci
  if (%$og) {
    # fill filter, no filtering for unstranded
    my $filter = {};
    for my $strand (qw/+ -/) {
      next if (!exists $og->{$strand});

      for my $gn_id (keys %{$og->{$strand}}) {
        next if (exists $filter->{$gn_id});

        my $gn_placed = pon4($gn_id, $src_ctg);

        my @vs_raw = keys %{$og->{$strand}->{$gn_id}};
        my @vs = grep {!exists $filter->{$_} } @vs_raw;
        my $vs_placed_max = max( map {pon4($_, $src_ctg)} @vs );

        my $gn = $og->{$strand}->{$gn_id}->{$vs_raw[0]}->[0];
        $filter->{$gn_id} = $gn if ($gn_placed  == -1 && $vs_placed_max > -1);

        if ($gn_placed == 1) {
          for my $vs_gn_id (@vs) {
            my $vs_gn = my $gn = $og->{$strand}->{$gn_id}->{$vs_gn_id}->[1];
            $filter->{$vs_gn_id} = $vs_gn if (pon($vs_gn_id) != 1);
          }
        }
      }
    } # fill filter

    #dump what is not filetered, fill stats, fill lists, outer_filters
    my $processed_pair = {};
    for my $strand (qw/+ - ./) {
      next if (!exists $og->{$strand});
      my $unstranded_pfx = ($strand eq ".") ? "UNSTRANDED_" : "";
      my $unstranded_sfx = ($strand eq ".") ? "_unstranded" : "";

      for my $gn_id (sort keys %{$og->{$strand}}) {
        next if (exists $filter->{$gn_id});

        my ($name, $id) = split /:/, $gn_id;

        my @overlaps = ();
        my @vs = sort grep {!exists $filter->{$_} } keys %{$og->{$strand}->{$gn_id}};
        for my $vs_gn_id (@vs) {
          my ($vs_name, $vs_id) = split /:/, $vs_gn_id;
          my ($gn, $g) = @{ $og->{$strand}->{$gn_id}->{$vs_gn_id} };

          # for unstranded
          if ($strand eq ".") {
            next if (exists $processed_pair->{"+\t$gn_id\t$vs_gn_id"});
            next if (exists $processed_pair->{"-\t$gn_id\t$vs_gn_id"});
            next if (exists $processed_pair->{"+\t$vs_gn_id\t$gn_id"});
            next if (exists $processed_pair->{"-\t$vs_gn_id\t$gn_id"});
          }

          next if (exists $processed_pair->{"$strand\t$gn_id\t$vs_gn_id"});
          push @overlaps, $vs_name;

          next if (exists $processed_pair->{"$strand\t$vs_gn_id\t$gn_id"});

          $st->{"genes_pairs_overlapped${unstranded_sfx}"}++;
          print join("\t", "PAIR_GENE", "${unstranded_pfx}OVERLAP",
                      (map {$gn->{$_}} @gng_keys), (map {$g->{$_}} @gng_keys) ), "\n";  

          $processed_pair->{"$strand\t$gn_id\t$vs_gn_id"} = 1;
        }
        $gene_stat->{"overlaps${unstranded_sfx}4gene"}->{$name} = \@overlaps if (@overlaps);
      }
    }
   
    # copy names to ext filter, update stats
    for my $gn_id (keys %$filter) {
      my ($name, $id) = split /:/, $gn_id;
      $gene_stat->{overlaps_filter}->{$name} = 1;
      $st->{gene_pairs_overlapped_filtered}++;

      print join("\t", "OVERLAP_FILTER", "FILTER", (map {$filter->{$gn_id}->{$_}} @gng_keys)), "\n";  
    }
  }

  # dump merged loci
  if (%$merged_genes) {
    my $inf = $gene_stat->{exon_inflation_avg4gene};
    my $rd = $gene_stat->{tra_dist_rel_avg4gene};

    for my $loc (keys %$merged_genes) {
      my ($ctg, $start, $end, $strand) = split/\t/, $loc;

      my $unstranded_pfx = ($strand eq ".") ? "UNSTRANDED_" : "";
      my $unstranded_sfx = ($strand eq ".") ? "_unstranded" : "";
      if ($strand eq ".") {
        next if exists $merged_genes->{join("\t", $ctg, $start, $end, "+")};
        next if exists $merged_genes->{join("\t", $ctg, $start, $end, "-")};
      }
      $st->{"genes_merged_loci${unstranded_sfx}"}++;
       
      my @gene_names_ids = keys %{$merged_genes->{$loc}};
      my $genes_merges_at_loci = scalar(@gene_names_ids);
      $st->{"genes_merged${unstranded_sfx}"} += $genes_merges_at_loci;

      #order by from_placed, exon inflation, tra rel dist
      my @nids_s = sort {         pon4($b, $src_ctg) <=> pon4($a, $src_ctg)  ||
                          abs($inf->{nm4($a)} || 0) <=> abs($inf->{nm4($b)} || 0)   ||
                              ($rd->{nm4($a)} || 0) <=> ($rd->{nm4($b)} || 0)
                        } @gene_names_ids; 

      my @names_s = grep { defined $_ } map { nm4($_) } @nids_s;

      my $chosen = "CHOSEN";
      for my $g_name_id (@nids_s) {
        my ($name, $id) = split /:/, $g_name_id; 
        $gene_stat->{"merged${unstranded_sfx}4gene"}->{$name} = [ grep { $_ ne "$name" } @names_s ];

        if ($chosen ne "CHOSEN" && $strand ne ".") {
          $gene_stat->{merge_filter}->{$name} = $loc;
          $st->{"genes_merged_ignored${unstranded_sfx}"}++;
        }

        print join("\t", "MERGED_LOCI", "${unstranded_pfx}MERGE",
                    $name, $id, $ctg, $start, $end, $strand, $genes_merges_at_loci, $chosen), "\n";

        $chosen = "IGNORED";
      }
    }
  } # if %merged_genes

}


sub get_gene_coords {
    my ($result, $values, $col2key, $unstranded) = @_;

    my $SRC_ID_C = $col2key->{SRC_ID};
    my $TRG_NAME_C = $col2key->{TRG_NAME};
    my $SRC_CTG_C = $col2key->{SRC_CTG};
    my $TRG_CTG_C = $col2key->{TRG_CTG};
    my $TRG_START_C = $col2key->{TRG_START};
    my $TRG_END_C = $col2key->{TRG_END};
    my $TRG_STRAND_C = $col2key->{TRG_STRAND};

    push @$result, ( grep {
                         defined $_->{ctg} && defined $_->{start} && defined $_->{end}
                         && (defined $_->{strand} || defined $unstranded)
                       }
                  map { {
                          name => $_->[$TRG_NAME_C], id => $_->[$SRC_ID_C],
                          ctg => $_->[$TRG_CTG_C],
                          start => $_->[$TRG_START_C], end => $_->[$TRG_END_C],
                          strand => ($unstranded || $_->[$TRG_STRAND_C]),
                          src_ctg => $_->[$SRC_CTG_C],
                      } } @{$values} ); 
}



##### UTILS #####
sub check_2_stat {
  my ($obj, $st, $ok, $fail) = @_;

  if (!$obj) {
    $ok = defined $ok && $ok || "";
    $fail = defined $fail && $fail || "${ok}_not"; 
    $st->{$fail}++;
    return undef;
  }

  $st->{$ok}++ if (defined $ok);
  return $obj;
}

sub c2s {
  return check_2_stat(@_);
}

sub get_seq {
  my ($utr) = @_;
  return undef if (!$utr);
  my $seq = $utr->seq(); 
  return undef if (!$seq || 0 == length($seq));
  return $seq;
}

sub smaller_larger {
  my ($src, $trg, $st, $pfx) = @_;
  if ($src == $trg) {
    $st->{"${pfx}_same"}++;
    return 1;
  }
  if ($trg < $src) {
    $st->{"${pfx}_smaller"}++;
    return 0;
  }
  if ($trg > $src) {
    $st->{"${pfx}_larger"}++;
    return 0;
  }
  return 0;
}

sub shorter_longer {
  my ($src, $trg, $st, $pfx) = @_;

  if (!$src && !$trg) {
    $st->{"${pfx}_intact_empty"}++;
    return 2;
  }

  if (!$src) {
    $st->{"${pfx}_acquired"}++;
    return 1;
  }

  if (!$trg) {
    $st->{"${pfx}_lost"}++;
    return 0;
  }

  if ($src eq $trg) {
    $st->{"${pfx}_intact"}++;
    return 2;
  }
  my $sl = length($src);
  my $tl = length($trg);
  if ($sl == $tl) {
    $st->{"${pfx}_len_same"}++;
    return 1;
  }
  if ($tl < $sl) {
    $st->{"${pfx}_len_shorter"}++;
    return 0;
  }
  if ($tl > $sl) {
    $st->{"${pfx}_len_longer"}++;
    return 0;
  }
  return 0;
}

warn "## stats:\n";
for my $k (sort keys %$st) {
  warn "#STAT\t$k\t",$st->{$k},"\n";  
}


sub calc_exon_inflation {
  my ($src_num, $trg_num) = @_;
  return ($src_num > 0) ? ($trg_num - $src_num) / $src_num : undef;
}


# GENE PROCESSING

# split gene if different strands or scaf_name
##1:GENE 2:STATUS
##  3:SRC_NAME 4:TRG_NAME 5:SPLITTED_STATUS 6:PARTS 7:PART
##  8:SRC_ID 9:SRC_CTG 10:SRC_START 11:SRC_END 12:SRC_STRAND
##  13:SRC_TR_NUM 14:TRG_TR_NUM 15:TR_STATUS 16:CANON_TR_STATUS
##  17:SRC_TRA_NUM 18:TRG_TRA_NUM 19:TRG_TRA_OK 20:TRG_TRA_CHANGED 21:TRA_STATUS
##  22:TRG_CTG 23:TRG_START 24:TRG_END 25:TRG_STRAND
##  26:TRG_TR_OK 27:TRG_TR_CHANGED 28:TRG_TR_FAILED


##1:TRANSCRIPT 2:STATUS
##  3:SRC_NAME 4:SRC_ID 5:SRC_GENE_NAME 6:SRC_GENE_ID
##  7:SRC_CTG 8:SRC_START 9:SRC_END 10:SRC_STRAND
##  11:SRC_EXONS 12:SRC_SPLICED_LEN 13:SRC_CDS_LEN 14:SRC_TRA_LEN
##  15:TRG_CTG 16:TRG_START 17:TRG_END 18:TRG_STRAND
##  19:TRG_EXONS 20:TRG_SPLICED_LEN 21:TRG_CDS_LEN 22:TRG_TRA_LEN
##  23:SRC_5_UTR_LEN 24:SRC_3_UTR_LEN 25:TRG_5_UTR_LEN 26:TRG_3_UTR_LEN
##  27:TRA_STATUS 28:UTR_5_STATUS 29:UTR_3_STATUS
##  30:TRA_DIST 31:TRA_DIST_REL 32:TRA_LEN_SUM
##  33:UTR_5_DIST 34:UTR_5_DIST_REL 35:UTR_5_LEN_SUM
##  36:UTR_3_DIST 37:UTR_3_DIST_REL 38:UTR_3_LEN_SUM
##  39:TR_SPLICED_DIST 40:TR_SPLICED_DIST_REL 41:TR_SPLICED_LEN_SUM
##  42:SRC_TRA 43:TRG_TRA 44:SRC_5_UTR 45:SRC_3_UTR 46:TRG_5_UTR 47:TRG_3_UTR
