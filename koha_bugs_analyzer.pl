#!/usr/bin/env perl

use feature 'say';
use warnings;
use strict;

use BZ::Client::REST;
use Data::Dumper;
use FindBin qw($Bin);
use Getopt::Long::Descriptive;
use JSON;
use Text::CSV::Slurp;

my ( $opt, $usage ) = describe_options(
    'koha_bugs_analyzer.pl',
    [ "community-url=s",      "Community tracker URL",      { required => 1, default => $ENV{KOHA_URL} } ],
    [ "community-username=s", "Community tracker username", { required => 1, default => $ENV{KOHA_USER} } ],
    [ "community-password=s", "Community tracker password", { required => 1, default => $ENV{KOHA_PW} } ],
    [],
    [ "stop-version|stop|s=s", "Stop at version", { required => 1, default => $ENV{KOHA_STOP_VERSION} } ],
    [ "stop-title", "Stop at commit title", { required => 0, default => undef } ],
    [],
    [ 'verbose|v+', "Print extra stuff" ],
    [ 'help|h', "Print usage message and exit", { shortcircuit => 1 } ],
);

print( $usage->text ), exit if $opt->help;

my $stop_title = $opt->stop_title;

my $bz_koha_url  = $opt->community_url;
my $bz_koha_user = $opt->community_username;
my $bz_koha_pass = $opt->community_password;

my $bz_client = BZ::Client::REST->new(
    {
        user     => $bz_koha_user,
        password => $bz_koha_pass,
        url      => $bz_koha_url,
    }
);
$bz_client->login;

my $koha_repo_path = $ENV{SYNC_REPO};
say "SYNC_REPO: $koha_repo_path" if $opt->verbose;
chdir $koha_repo_path;

my @commits = qx{ git log --pretty=format:'%s' --no-patch | head -n 4000 };

my $current_koha_version;

my $seen = {};
my @bugs;
foreach my $c (@commits) {
    chomp($c);

    say "\nWorking on $c";

    if ( $c =~ m/^$stop_title/ ) {
        say "Found stop title, stopping!";
        last;
    }

    if ( $c =~ m/^Bug ([0-9]*).*/ ) {
        next unless $current_koha_version;
        my $bug_id = $1;
        
        if ( $seen->{$bug_id} ) {
            say "Skipping $bug_id, it has been seen.";
            next;
        }
        
        say "Found bug $bug_id";
        my $bug = $bz_client->get_bug($bug_id);
        my $data = {
            id => $bug_id,
            date_created => $bug->{creation_time},
            assignee => $bug->{assigned_to_detail}->{email},
            creator => $bug->{creator_detail}->{email},
            version => $current_koha_version,
        };
        push( @bugs, $data );
        warn Data::Dumper::Dumper( $data );
        $seen->{$bug_id} = $data;
    }
    else {
        if ( $c =~ m/^Increment version for (\d\d)\.(\d\d)\.(\d\d) release.*/ )
        {
            my $major = $1;
            my $minor = $2;
            my $rev   = $3;
            $current_koha_version = "$major.$minor.$rev";

            last if $current_koha_version && $current_koha_version eq $opt->stop_version;

            $rev--;
            $current_koha_version = "$major.$minor.$rev";
            say "Found version commit, now working on version $current_koha_version";

        }
        else {
            say "No bug number, skipping.";
        }
    }
}

chdir $Bin;

my $csv = Text::CSV::Slurp->create( input => \@bugs );
my $file = "bugs.csv";

open( FH, ">$file" ) || die "Couldn't open $file $!";
print FH $csv;
close FH;
