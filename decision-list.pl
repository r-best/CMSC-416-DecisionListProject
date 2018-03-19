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

my %senses;
my %features;

if(open(my $fh, "<:encoding(UTF-8)", $train)){
    my $text = do { local $/; <$fh> }; # Read in the entire file as a string
    close $fh;
    chomp $text;

    # Get each instance out of the file
    my @instances = ($text =~ /(<instance.*?<\/instance>)/gs);
    
    for my $instance (@instances){
        my $sense = ($instance =~ /senseid=\"(.*)\"/)[0]; # Get its sense
        my @sentences = ($instance =~ /(<s>(.*?)<\/s>)/gs); # Get all of its sentences (ignoring paragraphs)
        
        for my $sentence (@sentences){
            $sentence =~ s/<s>|<\/s>|<@>|<p>|<\/p>//gs; # Remove the tags so we're left with those good good words
            $sentence =~ s/\b$stopwords\b//gs; # Remove stopwords
            @words = ($sentence =~ /\b\w+\b/gs); # Split sentence into words

            for my $word (@words){
                # Increment the number of times this word appears
                $features{$word}++;
                # Increment the number of times this word appears with this sense
                $senses{$sense}{$word}++;
            }
        }
    }

    # Change the %senses hash from recording frequencies of words appearing
    # with a sense to probabilities of a word given the sense
    for my $sense (keys %senses){
        for my $word (keys %{$senses{$sense}}){
            # P(sense|word) = freq(sense, word) / freq(word)
            $senses{$sense}{$word} /= %features{$word};
        }
    }
    
    # For each word, calculate the log ratio of the probabilities
    # of the word given each of the two senses
    # (At this point I'm assuming there are only two senses)
    my $sense1 = (keys %senses)[0];
    my $sense2 = (keys %senses)[1];
    for my $word (keys %features){
        # If the word wasn't seen with either sense, ignore it (this shouldn't even be possible)
        if(!(exists $senses{$sense1}{$word}) && !(exists $senses{$sense2}{$word})){
            continue;
        }
        # TODO: Maybe use smoothing for this part instead of this arbitrary max value
        # If the word was never seen with the first sense, set to max value for second sense
        if(!(exists $senses{$sense1}{$word})){
            $features{$word} = -1000000;
        }
        # If the word was never seen with the second sense, set to max value for first sense
        elsif(!(exists $senses{$sense2}{$word})){
            $features{$word} = 1000000;
        }
        # Else word was seen with both senses, so do the actual math
        else{
            my $probSense1 = $senses{$sense1}{$word};
            my $probSense2 = $senses{$sense2}{$word};
            $features{$word} = log($probSense1/$probSense2) / log(2);
            print $features{$word}."\n";
        }
    }
    print Dumper(@features);
} else{
    die "Error opening training file '$train'";
}