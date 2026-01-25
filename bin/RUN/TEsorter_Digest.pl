use strict;
my $searchfile = $ARGV[0];  # tabout.tsv (from LTRDIGEST)
my $searchfor  = $ARGV[1];  # LTR.tsv (from TEsorter)

# Build hash for O(1) lookup instead of O(n) array search
my %parray;
open( PFILE, "<$searchfile" );
while (<PFILE>) {
    chomp();
    if (/(\S+)\t([\S|\s]+)/) {
        my $id   = $1;
        my $rnu  = $2;
        $parray{$id} = $rnu;
    }
}
close PFILE;

open( GFILE, "<$searchfor" );
while (<GFILE>) {
    chomp();
    if (/(\S+)\t([\S|\s]+)/) {
        my $contig  = $1;
        my $gstart  = $2;

        # Extract base ID from TEsorter format
        # TEsorter adds suffixes like "#LTR/Copia" or "_INT#LTR/Copia"
        # Also handle LTR_RETRIEVER format: "seqid:start..end_INT#LTR/Family"
        my $base_id = $contig;

        # Remove TEsorter classification suffix (everything after #)
        $base_id =~ s/#.*//;

        # Remove _INT suffix if present
        $base_id =~ s/_INT$//;

        # Handle LTR_RETRIEVER format: convert "seqid:start..end" to "seqid_start_end"
        if ($base_id =~ /^(\S+):(\d+)\.\.(\d+)$/) {
            $base_id = "${1}_${2}_${3}";
        }

        # Look up in hash (O(1) instead of O(n))
        if (exists $parray{$base_id}) {
            print "$base_id\t$parray{$base_id}\t$gstart\n";
        }
    }
}
close GFILE;
