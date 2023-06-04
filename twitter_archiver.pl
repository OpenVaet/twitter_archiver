#!/usr/bin/perl
use strict;
use warnings;
use 5.26.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use Data::Printer;
use Encode;
use Data::Dumper;
use JSON;
use HTTP::Cookies;
use HTML::Tree;
use LWP::UserAgent;
use LWP::Simple;
use HTTP::Cookies qw();
use Selenium::Chrome;
use HTTP::Request::Common qw(POST OPTIONS);
use HTTP::Headers;
use Hash::Merge;
use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use Getopt::Long;

# This script requires:
# On Windows, you'll need a recent version of Strawberry Perl at https://strawberryperl.com/

# You'll need the libraries used, listed above.
# On Linux, run first apt-get install cpan-minus to install the light version of the lib manager
# It's installed by default with Strawberry.
# Then cpanm Selenium::Chrome for example to install the [Selenium::Chrome] module.

# Last but not least you'll need Google Chrome installed, and the chrome driver corresponding to your OS.
# Available at https://chromedriver.chromium.org/downloads

# Get command-line options
my $bulk  = 0;
my $login = 0;
GetOptions(
    "bulk"  => \$bulk,
    "login" => \$login
);

# Project's libraries.
my $windowsUserName   = 'User';
my $vidDownloaderUrl  = 'https://ssstwitter.com/';
my $twitterUrlBase    = 'https://twitter.com';
my $profilePicsFolder = "twitter_archive/profile_images";
my $mediaFolder       = "twitter_archive/media";
make_path($profilePicsFolder)
	unless (-d $profilePicsFolder);
make_path($mediaFolder)
	unless (-d $mediaFolder);

# Initiating automatized browser. Customize these parameters if you're not using the default Chrome path or if you're running on Linux.
my $dataDir           = "C:\\Users\\$windowsUserName\\AppData\\Local\\Google\\Chrome\\User Data";
my $profileDir        = "Profile 1";
my $fullPath          = "$dataDir\\$profileDir";
my $downloadDir       = "C:/Users/$windowsUserName/Downloads";
my $capabilities      = {};
$capabilities->{"goog:chromeOptions"} = {
	"args" => [
		"user-data-dir=$fullPath",
		"profile-directory=$profileDir"
	]
};
my $driver            = Selenium::Chrome->new('extra_capabilities' => $capabilities);

if ($login) {
	wait_login();
}

say "Enter the URL of the [last] tweet of the thread to archive and press [Enter] :";
my $threadToArchive   = <STDIN>;
chomp $threadToArchive;

# Verify that the URL has the expected format.
unless ($threadToArchive =~ /^https:\/\/twitter\.com\/.*\/status\/.*/) {
	$driver->shutdown_binary;
	die "format error in the URL you entered. Expected format is [https://twitter.com/{user_name}/status/{tweet_id}]";
}
my ($threadToArchiveId) = $threadToArchive =~ /\/status\/(\d+)/;

# Fetch page to archive.
say "Archiving [$threadToArchive] ...";
$driver->get($threadToArchive);
sleep 6;

# Fetch tweets in page.
my $formerFound       = 0;
my $tweetsFound       = 0;
my $tweetIncr         = 0;
my %tweetsSha         = ();
parse_tweets();
if (!$tweetsFound) {
    my $attempts = 0;
    while (($attempts < 3 && !$tweetsFound)) {
    	$attempts++;
		parse_tweets();
    	$tweetsFound = keys %tweetsSha;
    	sleep 2;
    }
}
scroll_top();
while ($formerFound != $tweetsFound) {
	$formerFound      = $tweetsFound;
	parse_tweets();

	# Scroll up using JavaScript
	scroll_top();
}
sleep 2;

# Rendering every tweet of the thread.
my %tweetsByInc       = ();
for my $sha256 (sort keys %tweetsSha) {
	my $tweetIncr     = $tweetsSha{$sha256}->{'tweetIncr'} // die;
	my $tweet         = $tweetsSha{$sha256}->{'tweet'}     // die;
	$tweetsByInc{$tweetIncr} = $tweet;
}

my %tweets            = ();
my $formerAlias;
open my $out, '>', "$threadToArchiveId.html";
say $out "<body style=\"margin:0;overflow-x:none;overflow-y:auto;height:100vh;\">";
say $out "<div style=\"width:100\%;height:auto;margin:0;\">";
say $out "\t<div style=\"width:30\%;max-width:700px;min-width:300px;height:100\%;margin:auto;\">";
for my $tweetIncr (sort{$b <=> $a} keys %tweetsByInc) {
	my $tweet         = $tweetsByInc{$tweetIncr} // die;
	# Identifying if we have an avatar for the user.
	my $tweetAvatar   = $tweet->look_down("data-testid"=>"Tweet-User-Avatar");
	if ($tweetAvatar) {
		my ($userAlias, $userPic)  = alias_and_picture_from_tweet($tweet);
		my ($userName, $tweetDate) = name_and_date_from_tweet($tweet);
		my $tweetText              = $tweet->look_down("data-testid"=>"tweetText");
		my @tweetMedia             = $tweet->look_down("data-testid"=>"tweetPhoto");

		# Fetching the tweet URL.
		(my $tweetUrl, $tweetDate) = parse_tweet_url($tweet, $tweetDate);
		die unless $tweetUrl && $tweetDate;

		# Initiates tweet object.
		$tweets{$tweetIncr}->{'userAlias'} = $userAlias;
		$tweets{$tweetIncr}->{'userPic'}   = $userPic;
		$tweets{$tweetIncr}->{'userName'}  = $userName;
		$tweets{$tweetIncr}->{'tweetDate'} = $tweetDate;
		$tweets{$tweetIncr}->{'tweetUrl'}  = $tweetUrl;
		# p$tweets{$tweetIncr};

		# Storing profile picture.
		my ($userLocalPic) = $userPic =~ /\/([^\/]+)$/;
		$userLocalPic      = $profilePicsFolder . "/$userLocalPic";
		unless (-f $userLocalPic) {
			getstore($userPic, $userLocalPic) or die "failed to store [$userLocalPic]";
		}
		$userAlias =~ s/\//\@/;
		if (!$formerAlias || ($formerAlias && ($formerAlias eq $userAlias))) {
			say $out "\t\t<div style=\"width:calc(100\% - 10px);margin-left:10px;margin-top:25px;height:50px;display:flex;flex-wrap:wrap;position:relative;font:inherit;\">";
		} else {
			say $out "\t\t<div style=\"width:calc(100\% - 10px);margin-left:10px;margin-top:25px;height:50px;display:flex;flex-wrap:wrap;position:relative;border-top:1px solid darkgrey;padding-bottom:10px;font:inherit;\">";
		}
		print_tweet_header($userName, $userAlias, $userLocalPic);

		# Process each text child node
		parse_tweet_text($tweetIncr, $tweetText);
		say $out "\t\t<\/div>";
		# say $out "userAlias    : $userAlias";
		# say $out "userPic      : $userPic";
		# say $out "userLocalPic : $userLocalPic";
		my ($hasMedia,
			$hasVideo)  = parse_tweet_media(@tweetMedia);

		# Prints tweet footer.
		if ($hasVideo) {
			say "Downloading Videos ...";
			my $videoFile = download_video($tweetUrl);
			$tweets{$tweetIncr}->{'videoFile'} = $videoFile;
			say $out "\t\t\t<div style=\"width:100\%;margin-top:10px;\">";
			say $out "\t\t\t\t<a href=\"$videoFile\" target=\"_blank\"><img src=\"video_preview.png\" style=\"width:100\%;\"></a>";
			say $out "\t\t<\/div>";
		}
		print_tweet_footer($tweetUrl, $tweetDate);
		$tweets{$tweetIncr}->{'hasMedia'}  = $hasMedia;
		$tweets{$tweetIncr}->{'hasVideo'}  = $hasVideo;
		$formerAlias = $userAlias;
	} else { # Content isn't accessible, either because the user is blocked or deleted his tweet.
		my @spans = $tweet->find('span');
		for my $span (@spans) {
			my $text = $span->as_trimmed_text;
			if ($text) {
				$tweets{$tweetIncr}->{'tweetText'} = $text;
				say $out "\t\t\t<div style=\"width:100\%;margin-top:10px;border-top:1px solid darkgrey;padding-bottom:10px;font:inherit;\"><span style=\"font:14px -apple-system,BlinkMacSystemFont,Roboto,Helvetica,Arial,sans-serif;font:Roboto,Helvetica,Arial,sans-serif;font-size:14px;\">$text</span></div>";
				last;
			}
		}
		$formerAlias = '**no_poster_known**';
	}
}
say $out "\t\t<div style=\"width:100\%;height:50px;\"></div>";
say $out "\t<\/div>";
say $out "<\/div>";
say $out "<\/body>";
close $out;

$driver->shutdown_binary;

sub parse_tweets {
    my $content = $driver->get_page_source;
    my $tree    = HTML::Tree->new();
    $tree->parse($content);
    my @tweets  = $tree->look_down("data-testid" => "cellInnerDiv");
    for my $i (reverse 0..$#tweets) {
        my $tweetData = $tweets[$i];
        my $tweet     = $tweetData->as_HTML('<>&', "\t");
        my $utf8Tweet = encode('UTF-8', $tweet);
        my $sha256    = sha256_hex($utf8Tweet);
        unless (exists $tweetsSha{$sha256}) {
            $tweetIncr++;
            $tweetsSha{$sha256}->{'tweetIncr'} = $tweetIncr;
            $tweetsSha{$sha256}->{'tweet'}     = $tweetData;
        }
    }
    $tweetsFound = keys %tweetsSha;
    say "Found [$tweetsFound] tweets ...";
}


sub scroll_top {
	$driver->execute_script('window.scrollTo(0, 0);');
	sleep 2;
}

sub wait_login {
	my $base_url = "https://twitter.com/";
	say "Getting [$base_url]";
	$driver->get($base_url);
	say "Confirm ([Enter]) once you're logged in ...";
	my $stdin    = <STDIN>;
	chomp $stdin;
}

sub alias_and_picture_from_tweet {
	my $tweet = shift;
	# Extracting the href
	my $link = $tweet->look_down(
	    _tag => 'a',
	    href => qr{^\/[0-9A-Za-z_]+$}
	);

	my $href = $link->attr('href') if $link;

	# Extracting the image source
	my $image;
	my @imgs = $tweet->look_down(
	    _tag => 'img',
	    sub {
	        my $class = shift->attr('class');
	        return $class && $class =~ /css-[0-9a-zA-Z]+/;
	    }
	);

	if (@imgs) {
	    $image = $imgs[0];
	}

	my $src = $image->attr('src') if $image;
	die unless $href && $src;
	return ($href, $src);
}

sub name_and_date_from_tweet {
	my $tweet = shift;
	my $timeData   = $tweet->look_down("data-testid"=>"User-Name");
	my @ltrs       = $timeData->look_down(dir=>"ltr");
	my $userName   = $ltrs[0]->as_trimmed_text;
	my $tweetDate;
	if ($ltrs[4]) {
		$tweetDate = $ltrs[4]->as_trimmed_text;
	}
	return ($userName, $tweetDate);
}

sub print_tweet_header {
	my ($userName, $userAlias, $userLocalPic) = @_;
	say $out "\t\t\t<div style=\"width:50px;height:100\%;position:absolute;z-index: -1;\">";
	say $out "\t\t\t\t<img style=\"width: 100\%; height: 100\%; object-fit: cover; border-radius: 50\%;\" src=\"$userLocalPic\">";
	say $out "\t\t\t<\/div>";
	say $out "\t\t\t<div style=\"width:50px;height:100\%;position:absolute;border:0 solid black;border-bottom-left-radius: 9999px;border-bottom-right-radius: 9999px;border-top-left-radius: 9999px;border-top-right-radius: 9999px;z-index: 0;\">";
	say $out "\t\t\t<\/div>";
	say $out "\t\t\t<div style=\"width:calc(100\% - 60px);height:100\%;position:absolute;margin-left:60px;\">";
	say $out "\t\t\t\t<div style=\"width:100\%;height:20px;margin-left:5px;margin-top:5px;\">";
	say $out "\t\t\t\t\t<b>$userName</b>";
	say $out "\t\t\t\t<\/div>";
	say $out "\t\t\t\t<div style=\"width:100\%;height:20px;margin-left:5px;margin-top:5px;\">";
	say $out "\t\t\t\t\t$userAlias";
	say $out "\t\t\t\t<\/div>";
	say $out "\t\t\t<\/div>";
	say $out "\t\t<\/div>";
	say $out "\t\t<div style=\"width:calc(100\% - 10px);margin-left:10px;margin-top:10px;height:auto;display:flex;flex-wrap:wrap;position:relative;\">";
}

sub parse_tweet_text {
	my ($tweetIncr, $tweetText) = @_;
	foreach my $child ($tweetText->content_list) {
	    if ($child->tag eq 'span') {
	        # Process text nodes
	        my $text = $child->as_trimmed_text;
	        my %o = ();
	        $o{'type'} = 'text';
	        $o{'text'} = $text;
			say $out "\t\t\t<div style=\"width:100\%;height:5px;\"></div><span style=\"font:14px -apple-system,BlinkMacSystemFont,Roboto,Helvetica,Arial,sans-serif;font:Roboto,Helvetica,Arial,sans-serif;font-size:14px;\">$text</span>";
	        push @{$tweets{$tweetIncr}->{'tweetText'}}, \%o;
	    } elsif ($child->tag eq 'img') {
	        # Process image nodes
	        my $src  = $child->attr('src');
	        my %o = ();
	        $o{'type'} = 'emoji';
	        $o{'src'}  = $src;
	        my ($localFile) = $src =~ /\/([^\/]+)$/;
	        $localFile = "$mediaFolder/$localFile";
			unless (-f $localFile) {
				getstore($src, $localFile) or die "failed to store [$localFile]";
			}
			say $out "\t\t\t<img style=\"width:20px;height:20px;\" src=\"$localFile\">";
	        push @{$tweets{$tweetIncr}->{'tweetText'}}, \%o;
	    } elsif ($child->tag eq 'a') {
	        # Process image nodes
	        my $href = $child->attr('href');
	        if ($href !~ /http/) {
	        	$href = $twitterUrlBase . $href;
	        } else {
	        	# Following redirection to fetch the real URL instead of the Twitter's one.
				$driver->get($href);
				sleep 2;
				$href = $driver->get_current_url();
	        }
	        my %o = ();
	        $o{'type'} = 'src';
	        $o{'href'} = $href;
			say $out "\t\t\t<div style=\"width:100\%;height:5px;\"></div><span style=\"font:14px -apple-system,BlinkMacSystemFont,Roboto,Helvetica,Arial,sans-serif;font:Roboto,Helvetica,Arial,sans-serif;font-size:14px;\"><a href=\"$href\" target=\"_blank\">$href</a></span>";
	        push @{$tweets{$tweetIncr}->{'tweetText'}}, \%o;
	    } elsif ($child->tag eq 'div') {
	        # Fetch account tagged
	        my $link  = $child->find('a');
	        my $href  = $link->attr_get_i('href');
	        $href     = $twitterUrlBase . $href;
	        my $name  = $link->as_trimmed_text;
	        my %o = ();
	        $o{'type'} = 'tag';
	        $o{'name'} = $name;
	        $o{'href'} = $href;
			say $out "\t\t\t<div style=\"width:100\%;height:5px;\"></div><span style=\"font:14px -apple-system,BlinkMacSystemFont,Roboto,Helvetica,Arial,sans-serif;font:Roboto,Helvetica,Arial,sans-serif;font-size:14px;\"><a href=\"$href\" target=\"_blank\">$name</a></span>";
	        push @{$tweets{$tweetIncr}->{'tweetText'}}, \%o;
	    } else {
	    	say "Something else : " . $child->tag;
	    	say $child->as_HTML('<>&', "\t");
	    }
	}
}

sub parse_tweet_url {
	my ($tweet, $tweetDate) = @_;
	my @divs = $tweet->find("div");
	my $tweetUrl;
	for my $div (@divs) {
		next unless $div->find('a');
		my $link = $div->find('a');
		next unless $link->attr_get_i('href');
		my $href = $link->attr_get_i('href');
		next unless $href =~ /analytics$/;
		$tweetUrl = $href;
	}
	unless ($tweetUrl) {
		die if $tweetDate;
		my @as = $tweet->find('a');
		for my $link (@as) {
			next unless $link->attr_get_i('href');
			my $href   = $link->attr_get_i('href');
			next unless $href =~ /\/status\/\d+$/;
			$tweetUrl  = $href;
			$tweetUrl  =~ s/ \? / \| /;
			$tweetDate = $link->as_trimmed_text;
		}
	}
	$tweetUrl =~ s/\/analytics$//;
	$tweetUrl = $twitterUrlBase . $tweetUrl;
	return ($tweetUrl, $tweetDate);
}

sub download_video {
	my $tweetUrl  = shift;
    my $videoUrl;
    my ($tweetId) = $tweetUrl =~ /\/status\/(\d+)/;
    my $localFile = "$mediaFolder/$tweetId.mp4";
	unless (-f $localFile) {
		$driver->get($vidDownloaderUrl);

		# Find the input field by its name attribute
		my $tweetField = $driver->find_element("(//input[\@id='main_page_text'])[1]");
		$tweetField->click();

		# Type the tweet url.
		$tweetField->send_keys($tweetUrl);

		# Clicks "Download"
		my $downloadBUtton = $driver->find_element("(//button[\@id='submit'])[1]");
		$downloadBUtton->click();

		# Fetching highest resolution.
	    while (!$videoUrl) {
			sleep 5;
		    my $content  = $driver->get_page_source;
		    my $tree     = HTML::Tree->new();
		    $tree->parse($content);
		    my $download = $tree->look_down(class=>"result_overlay");
		    if ($download) {
			    my @links    = $download->find('a');
			    for my $link (@links) {
			    	my $text = $link->as_trimmed_text;
			    	next unless $text =~ /Download/;
			    	$videoUrl = $link->attr_get_i('href');
			    	last;
			    }
		    }
	    }

		getstore($videoUrl, $localFile) or die "failed to store [$localFile]";
	}
	return $localFile;
}

sub parse_tweet_media {
	my (@tweetMedia) = @_;
	my $hasMedia     = 0;
	my $hasVideo     = 0;
	my %pictures     = ();
	if (scalar @tweetMedia) {
		$hasMedia    = 1;
		my $mediaNum = 0;
		for my $tweetMedia (@tweetMedia) {
			my $videoPlayer = $tweetMedia->look_down("data-testid"=>"videoPlayer");
			if ($videoPlayer) {
				$hasVideo   = 1;
			} else {
				# Fetching pictures.
				my ($img)  = $tweetMedia->look_down(_tag => 'img');
				my $src    = $img->attr('src');
		        my %o      = ();
		        $o{'type'} = 'pic';
		        $o{'src'}  = $src;
		        push @{$tweets{$tweetIncr}->{'media'}}, \%o;
		        my ($fileNameShort, $fileExt, $format) = $src =~ /media\/(.*)\?format=(.*)&name=(.*)/;
		        $src =~ s/$format$/large/;
		        my $localFile = "$mediaFolder/$fileNameShort.$fileExt";
				unless (-f $localFile) {
					getstore($src, $localFile) or die "failed to store [$localFile]";
				}
				say $out "\t\t\t<div style=\"width:100\%;margin-top:10px;\">";
				say $out "\t\t\t\t<a href=\"$localFile\" target=\"_blank\"><img src=\"$localFile\" style=\"width:100\%;\"></a>";
				say $out "\t\t<\/div>";
			}
		}
	}
	return ($hasMedia,
			$hasVideo);
}

sub print_tweet_footer {
	my ($tweetUrl, $tweetDate) = @_;
	say $out "\t\t\t<div style=\"width:100\%;height:5px;\"></div>";
	say $out "\t\t<div style=\"width:calc(100\% - 10px);margin-left:10px;margin-top:10px;height:auto;display:flex;flex-wrap:wrap;position:relative;\">";
	say $out "\t\t\t<div style=\"width:100\%;\"></div>$tweetDate&nbsp;-&nbsp;<a href=\"$tweetUrl\" target=\"_blank\">$tweetUrl</a>";
	say $out "\t\t<\/div>";
}