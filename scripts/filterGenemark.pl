#!/usr/bin/perl

####################################################################################################
#                                                                                                  #
# filterGenemark.pl - reformats and filters the GeneMark-ET output for usage with braker.pl:       #
#                     adds double quotes around ID to match gtf format                             #
#                     filters GeneMark-ET output into good and bad genes, i.e.                     #
#                     genes included and not included in introns file respectively                 #
#                                                                                                  #
# Author: Simone Lange                                                                             #
#                                                                                                  #
# Contact: katharina.hoff@uni-greifswald.de                                                        #
#                                                                                                  #
# Release date: January 7th 2015                                                                   #
#                                                                                                  #
# This script is under the Artistic Licence                                                        #
# (http://www.opensource.org/licenses/artistic-license.php)                                        #
#                                                                                                  #
#################################################################################################### 


# ----------------------------------------------------------------
# | first outline from old version  | Simone Lange   |29.07.2014 |
# | changed to adapt to             |                |03.10.2014 |  
# | GeneMark-ET changes up to       |                |08.10.2014 |
# | Version 4.15                    |                |08.10.2014 |
# | minor corrections and           |                |07.10.2014 |
# | simplifications                 |                |08.10.2014 |
# ----------------------------------------------------------------
 
use strict;
use warnings;
use Getopt::Long;
use File::Compare;
use Data::Dumper;
use POSIX qw(ceil);




my $usage = <<'ENDUSAGE';

filterGenemark.pl     filter GeneMark-ET files and search for "good" genes

SYNOPSIS

filterGenemark.pl [OPTIONS] genemark.gtf introns.gff

  genemark.gtf         file in gtf format
  introns.gff          corresponding introns file in gff format
  
    
    
OPTIONS

    --help                          output this help message
    --introns=introns.gff           corresponding intron file in gff format
    --genemark=genemark.gtf         file in gtf format
    --output=newfile.gtf            specifies output file name. Default is 'genemark-input_file_name.c.gtf' 
                                    and 'genemark-input_file_name.f.good.gtf'
                                    and 'genemark-input_file_name.f.bad.gtf' for filtered genes included and not included in intron file respectively

Format:
  seqname <TAB> source <TAB> feature <TAB> start <TAB> end <TAB> score <TAB> strand <TAB> frame <TAB> gene_id value <TAB> transcript_id value
                           

DESCRIPTION
      
  Example:

    filterGenemark.pl [OPTIONS] --genemark=genemark.gtf --introns=introns.gff

ENDUSAGE


my ($genemark, $introns, $output_file, $help);
my $average_gene_length;    # for length determination
my $bool_good = "true";     # if true gene is good, if false, gene is bad
my $bool_intron = "false";  # true, if currently between exons, false otherwise
my $bool_start = "false";   # true, gene has start codon
my @CDS;                    # contains coding region lines
my $gene_start;             # for length determination
my $ID_new;                 # new ID with doublequotes for each gene
my @ID_old;                 # old ID without quotes
my %introns;                # Hash of arrays of hashes. Contains information from intron file input. 
                            # Format $intron{seqname}{strand}[index]->{start} and ->{end}
my $length = 0;             # for length determination
my @line;                   # each input file line
my $nr_of_bad = 0;          # number of good genes
my $nr_of_complete = 0;     # number of complete genes, i.e. genes with start and stop codon
my $nr_of_good = 0;         # number of bad genes
my $one_exon_gene_count = 0;# counts the number of genes which only consist of one exon
my $start_codon = "";       # contains current start codon for "+" strand (stop codon for "-" strand)
my $stop_codon = "";        # contains current stop codon for "+" strand (start codon for "-" strand)
my $true_count = 0;         # counts the number of true cases per gene



if(@ARGV==0){
  print "$usage\n"; 
  exit(0);
}

GetOptions( 'genemark=s' => \$genemark,
            'introns=s'  => \$introns,
            'output=s'   => \$output_file,
            'help!'      => \$help);

if($help){
  print $usage;
  exit(0);
}

# set $genemark
if(!defined($genemark)){
  $genemark = $ARGV[0];
}

# set $introns
if(!defined($introns)){
  $introns = $ARGV[1];
}

# check whether the genemark file exists
if(!defined($genemark)){
  print "No genemark file specified. Please set a file with --genemark=genemark-ET.gtf.\n";
  exit(1),
}else{
  if(! -f "$genemark"){
    print "Genemark file $genemark does not exist. Please check.\n";
    exit(1);
  }
}

# check for option
if(defined($introns)){
  # check whether the intron file exists
  if(! -f "$introns"){
    print "Intron file $introns does not exist. Please check.\n";
    exit(1);
  }else{
    introns();
    convert_and_filter();
  }
}else{
  convert();
}
print STDOUT "Average gene length: $average_gene_length\n";
print STDOUT "Number of genes: $ID_old[0]\n";
print STDOUT "Number of complete genes: $nr_of_complete\n";
print STDOUT "Number of good genes: $nr_of_good\n";
print STDOUT "Number of one-exon-genes: $one_exon_gene_count\n";
print STDOUT "Number of bad genes: $nr_of_bad\n";
@_ = split(/\./, $genemark);
open (GENELENGTH, ">".$_[0].".average_gene_length.out") or die "Cannot open file: $_[0].average_gene_length.out\n";
print GENELENGTH "$average_gene_length\n";
close GENELENGTH;


                           ############### sub functions ##############

# read in introns and convert them to exon format
sub introns{
  open (INTRONS, $introns) or die "Cannot open file: $introns\n";
  while(<INTRONS>){
    chomp;
    my @line = split(/\t/, $_);
    $introns{$line[0]}{$line[6]}{$line[3]}{$line[4]} = "";
  }  
  close INTRONS;
}



# convert genemark file into regular gtf file with double quotes around IDs
# and split genes into good and bad ones
sub convert_and_filter{
  my @file_name;              # array for splitting file name
  my $exon;                   # current exon
  my $intron_start;
  my $intron_end;
  my $prev_ID = "no_ID";
  if(!defined($output_file)){
    @file_name = split(/\./, $genemark);
    $output_file = "$file_name[0].c.gtf";
  }else{
    @file_name = split(/\./, $output_file);
  }
  my $output_file_good = "$file_name[0].f.good.gtf";
  my $output_file_bad  = "$file_name[0].f.bad.gtf";

  open (GOOD, ">".$output_file_good) or die "Cannot open file: $output_file_good\n";
  open (BAD, ">".$output_file_bad) or die "Cannot open file: $output_file_bad\n";
  open (OUTPUT, ">".$output_file) or die "Cannot open file: $output_file\n";
  open (GENEMARK, "<".$genemark) or die "Cannot open file: $genemark\n";

  while(<GENEMARK>){
    chomp;
    @line = split(/\t/, $_);
    @ID_old = split(/\s/,$line[8]);
    chop($ID_old[1]);
    chop($ID_old[3]);
    my $last_char = substr($line[8], -1);
    if($ID_old[1] =~m/^"\w+"$/ && $ID_old[3] =~m/^"\w+"$/){
      $ID_new = $line[8];
    }else{
      $ID_new = "$ID_old[0] \"$ID_old[1]\"\; $ID_old[2] \"$ID_old[3]\"\;";
    }
     # new gene starts
    if($prev_ID ne $ID_old[1]){
      if(@CDS){
        print_gene();
      }
    }
    if( ($line[2] eq "start_codon" && $line[6] eq "+") || ($line[2] eq "stop_codon" && $line[6] eq "-") ){
      $bool_start = "true";
      $start_codon = "$line[0]\t$line[1]\t$line[2]\t$line[3]\t$line[4]\t$line[5]\t$line[6]\t$line[7]\t$ID_new\n";
      $gene_start = $line[3];

     # gene ends
    }elsif(($line[2] eq "stop_codon" && $line[6] eq "+") || ($line[2] eq "start_codon" && $line[6] eq "-") ){
      if($bool_start eq "true"){
        $length += $line[4] - $gene_start;
        $nr_of_complete++;
      }
      $bool_start = "false";
      $stop_codon = "$line[0]\t$line[1]\t$line[2]\t$line[3]\t$line[4]\t$line[5]\t$line[6]\t$line[7]\t$ID_new\n";
      
    # exons, CDS usw., i.e. no start or stop codon
    }elsif($line[2] ne "start_codon" && $line[2] ne "stop_codon"){
      if($bool_intron eq "false"){
        $intron_start = $line[4]+1;
        $bool_intron = "true";
      }else{
        $intron_end = $line[3]-1;
      
        # check if exons are defined in intron hash made of intron input
        if(defined($introns{$line[0]}{$line[6]}{$intron_start}{$intron_end})){
          $true_count++; 
        }
        $intron_start = $line[4]+1;
      }
      $exon = "$line[0]\t$line[1]\t$line[2]\t$line[3]\t$line[4]\t$line[5]\t$line[6]\t$line[7]\t$ID_new";
      push(@CDS, $exon);
    }

    print OUTPUT "$line[0]\t$line[1]\t$line[2]\t$line[3]\t$line[4]\t$line[5]\t$line[6]\t$line[7]\t$ID_new\n";
    $prev_ID = $ID_old[1];
  }
  @ID_old = split(/\_/,$ID_old[1]);
  print_gene(); # print last gene, since print_gene() was only executed after the ID changed

  close GENEMARK;
  close OUTPUT;
  close BAD;
  close GOOD;
  $average_gene_length = ceil($length / $nr_of_complete);
}



# convert genemark file into regular gtf file with double quotes around IDs
sub convert{
  if(!defined($output_file)){
    my @file_name = split(/\./, $genemark);
    $output_file = "$file_name[0].c.gtf";
  }

  open (OUTPUT, ">".$output_file) or die "Cannot open file: $output_file\n";
  open (GENEMARK, "<".$genemark) or die "Cannot open file: $genemark\n";

  while(<GENEMARK>){
    chomp;
    @line = split(/\t/, $_);
    @ID_old = split(/\s/,$line[8]);
    chop($ID_old[1]);
    chop($ID_old[3]);
    $ID_new = "$ID_old[0] \"$ID_old[1]\"\; $ID_old[2] \"$ID_old[3]\"\;";
    # new gene starts
    if( ($line[2] eq "start_codon" && $line[6] eq "+") || ($line[2] eq "stop_codon" && $line[6] eq "-") ){
      $bool_start = "true";
      $gene_start = $line[3];
    # gene ends
    }elsif(($line[2] eq "stop_codon" && $line[6] eq "+") || ($line[2] eq "start_codon" && $line[6] eq "-") ){
      if($bool_start eq "true"){
        $length += $line[4] - $gene_start;
        $nr_of_complete++;
      }
      $bool_start = "false";
    }
    print OUTPUT "$line[0]\t$line[1]\t$line[2]\t$line[3]\t$line[4]\t$line[5]\t$line[6]\t$line[7]\t$ID_new\n";
  }
  @ID_old = split(/\_/,$ID_old[1]);
  close GENEMARK;
  close OUTPUT;
  $average_gene_length = ceil($length / $nr_of_complete);
}



sub print_gene{
  if( ($true_count + 1 ) != scalar(@CDS) && scalar(@CDS) != 1){
    $bool_good = "false";
  }
  if(scalar(@CDS) == 1){
    $one_exon_gene_count++;
  }
  # all exons in intron file
  if($bool_good eq "true"){
    print GOOD "$start_codon"; $nr_of_good++;
    foreach (@CDS){
      print GOOD "$_\n";
    }
    print GOOD "$stop_codon";
   # not all exons in intron file
   }else{
    print BAD "$start_codon"; $nr_of_bad++;
    foreach (@CDS){
      print BAD "$_\n";
    }
    print BAD "$stop_codon";
  }
  @CDS =();
  $true_count = 0;
  $start_codon = "";
  $stop_codon = "";
  $bool_intron = "false";
  $bool_good = "true";
}


