# Assignment 4 decision-list.pl
# CMSC 416
# Due: Mon Mar. 26, 2018
# Program Summary:
#   A word sense tagger that takes in pre-tagged training data
#   and untagged testing data, learns what instances get what senses 
#   from the training, and uses that to correctly tag the testing.
# Algorithm:
#   Reads through the training data, and for each instance goes through
#   all the words in it and builds a frequency count of the number of
#   times each word appears with each sense. Uses that to build a decision
#   list model based on how strongly a word is associated with a particular
#   sense, then applies that model to the test data.
# Usage Format:
#   perl decision-list.pl training.txt testing.txt
#       - Will train on the data in training.txt
#           and output a copy of testing.txt that
#           has been tagged.
# Results:
#   .---------+---------+-------.
#   |         | product | phone |
#   +---------+---------+-------+
#   | product | 46      | 8     |
#   | phone   | 3       | 69    |
#   '---------+---------+-------'
#   CORRECT: 115
#   TOTAL: 126
#   ACCURACY: 91.2698412698413%
# Results on Most Frequent Sense:
#   .---------+-------+---------.
#   |         | phone | product |
#   +---------+-------+---------+
#   | phone   | 0     | 72      |
#   | product | 0     | 54      |
#   '---------+-------+---------'
#   CORRECT: 54
#   TOTAL: 126
#   ACCURACY: 42.8571428571429%
use List::MoreUtils qw(uniq);
use Data::Dumper;

sub println { print "@_"."\n" }

if(0+@ARGV < 3){
    die "At least 3 arguments required";
}

my $train = shift @ARGV;
my $test = shift @ARGV;
my $log = shift @ARGV;
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
my %features; # Maps all features to how often they appear, later changes to map to log ratio

my @sortedKeys; # Keys of %features sorted by descending value, populated at end of training
my %senseAppearances; # Maps senses to how often they appear (for finding most common sense baseline)
my $mostCommonSense;

if(open(my $fh, "<:encoding(UTF-8)", $train)){
        my $text = do { local $/; <$fh> }; # Read in the entire file as a string
        close $fh;
        chomp $text;

        # Get each instance out of the file
        my @instances = ($text =~ /(<instance.*?<\/instance>)/gs);
        
        for my $instance (@instances){
            my $sense = ($instance =~ /senseid=\"(.*)\"/)[0]; # Get the instance's sense
            $senseAppearances{$sense}++;

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

        # Determine the most common sense for use as a baseline later
        $mostCommonSense = (keys %senseAppearances)[0];
        for my $sense (keys %senseAppearances){
            if($senseAppearances{$sense} > $senseAppearances{$mostCommonSense}){
                $mostCommonSense = $sense;
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
            $features{$word} = log($probSense1/$probSense2);
        }
        @sortedKeys = sort {abs($features{$b}) <=> abs($features{$a})} keys %features;
} else{
    die "Error opening training file '$train'";
}

if(open(my $testfh, "<:encoding(UTF-8)", $test)){
    if(open(my $logfh, ">:encoding(UTF-8)", $log)){
        my $text = do { local $/; <$testfh> }; # Read in the entire file as a string
        close $testfh;
        chomp $text;

        # Get each instance out of the file
        my @instances = ($text =~ /(<instance.*?<\/instance>)/gs);

        for my $instance (@instances){
            my $id = ($instance =~ /id="(.*?)"/)[0];
            my @sentencesArray = ($instance =~ /<s>(.*?)<\/s>/gs); # Get all of its sentences (ignoring paragraphs)
            my $sentences = join " ", @sentencesArray;
            $sentences =~ s/<s>|<\/s>|<@>|<p>|<\/p>//gs; # Remove the tags

            my $sense1 = (keys %senses)[0];
            my $sense2 = (keys %senses)[1];
            my $predictedSense = $mostCommonSense;
            for my $key (@sortedKeys){
                if($sentences =~ /\b$key\b/){
                    if($features{$key} > 0){
                        $predictedSense = $sense1;
                        last;
                    }
                    if($features{$key} < 0){
                        $predictedSense = $sense2;
                        last;
                    }
                }
            }
            my $answerTag = "<answer instance=\"$id\" senseid=\"$predictedSense\"\/>";
            print $logfh $answerTag."\n";
            $instance =~ s/(.*)/$1\n$answerTag/;
            println $instance;
        }
        close $logfh;
    } else{
        die "Error opening log file '$log'";
    }
} else{
    die "Error opening testing file '$test'";
}