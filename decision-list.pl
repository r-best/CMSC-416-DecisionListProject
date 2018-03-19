use List::MoreUtils qw(uniq);
use Data::Dumper;

sub println { print "@_"."\n" }

if(0+@ARGV < 2){
    die "At least 2 arguments required";
}

my $train = shift @ARGV;
my $test = shift @ARGV;
my $stopwords = "stopwords.txt";

if(!(-f $train)){
    die "Training file '$train' does not exist";
}
if(!(-f $test)){
    die "Test file '$test' does not exist";
}
if(!(-f $stopwords)){
    die "Stopwords file '$stopwords' does not exist";
}

# Read in stopwords
if(open(my $fh, "<:encoding(UTF-8)", $stopwords)){
    $stopwords = do { local $/; <$fh> }; # Read in the entire file as a string
    $stopwords =~ s/(\s|\n)+/\|/g; # Join the words with | so they can be used as a regex
} else {
    die "Error opening '$stopwords'";
}

# %senses maps each sense to all the words it appears with, and all 
# of those words to how often they appear with that sense
# i.e. @senses{sense} = [words]
#      $senses{sense}{word} = freq
my %senses;
my %features; # Maps all features to how often they appear

if(open(my $fh, "<:encoding(UTF-8)", $train)){
    my $text = do { local $/; <$fh> }; # Read in the entire file as a string
    close $fh;
    chomp $text;

    # Get each instance out of the file
    my @instances = ($text =~ /(<instance.*?<\/instance>)/gs);
    
    for my $instance (@instances){
        my $sense = ($instance =~ /senseid=\"(.*)\"/)[0]; # Get the instance's sense
        my @sentences = ($instance =~ /<s>(.*?)<\/s>/gs); # Get all of its sentences (ignoring paragraphs)
        
        for my $sentence (@sentences){
            $sentence =~ s/<s>|<\/s>|<@>|<p>|<\/p>//gs; # Remove the tags so we're left with those good good words
            $sentence =~ s/\b($stopwords)\b//gs; # Remove stopwords
            @words = ($sentence =~ /\b\w+\b/gs); # Split sentence into words

            for my $word (@words){
                # Increment the number of times this word appears
                $features{$word}++;
                # Increment the number of times this word appears with this sense
                $senses{$sense}{$word}++;
            }
        }
    }
    
    # Divide each frequency $senses{sense}{word} by the total frequency of that word,
    # so that the values of %senses{sense}{word} become the probabilities P(sense|word)
    for my $sense (keys %senses){
        for my $word (keys %features){
            # P(sense|word) = (freq(sense, word)+1) / (freq(word)+(sizeof(@features))
            $senses{$sense}{$word} = ($senses{$sense}{$word}+1) / (%features{$word}+(0+(keys %features)));
        }
    }
    
    # For each word, calculate the log ratio of the probabilities
    # of the word given each of the two senses
    # Because of how logs work, if the result is positive it's in
    # favor of sense 1, if it's negative it's in favor of sense 2
    # (At this point I'm assuming there are only two senses)
    my $sense1 = (keys %senses)[0];
    my $sense2 = (keys %senses)[1];
    for my $word (keys %features){
        my $probSense1 = $senses{$sense1}{$word};
        my $probSense2 = $senses{$sense2}{$word};
        $features{$word} = log($probSense1/$probSense2) / log(10);
    }
} else{
    die "Error opening training file '$train'";
}