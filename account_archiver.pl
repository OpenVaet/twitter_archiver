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
my $windows_user_name   = 'Utilisateur';
my $vid_downloader_url  = 'https://ssstwitter.com/';
my $twitter_url_base    = 'https://twitter.com';
my $profile_pics_folder = "twitter_archive/profile_images";
my $media_folder        = "twitter_archive/media";
make_path($profile_pics_folder)
	unless (-d $profile_pics_folder);
make_path($media_folder)
	unless (-d $media_folder);

# Initiating automatized browser. Customize these parameters if you're not using the default Chrome path or if you're running on Linux.
my $data_dir            = "C:\\Users\\$windows_user_name\\AppData\\Local\\Google\\Chrome\\User Data";
my $profile_dir         = "Profile 1";
my $full_path           = "$data_dir\\$profile_dir";
my $capabilities        = {};
$capabilities->{"goog:chromeOptions"} = {
	"args" => [
		"user-data-dir=$full_path",
		"profile-directory=$profile_dir"
	]
};
my $driver              = Selenium::Chrome->new('extra_capabilities' => $capabilities);

if ($login) {
	wait_login();
}

say "Enter the alias of the twitter profile to archive and press [Enter] :";
my $profile_to_archive  = <STDIN>;
chomp $profile_to_archive;

# Fetch page to archive.
say "Archiving [$profile_to_archive] ...";
my $url_search = "https://twitter.com/search?q=from\%3A$profile_to_archive&src=typed_query&f=live";
$driver->get($url_search);
sleep 6;

# RobinetteGoneWY
# Fetch tweets in page.
my $former_found       = 0;
my $tweets_found       = 0;
my $tweet_incr         = 0;
my %tweet_sha          = ();
parse_tweets();
if (!$tweets_found) {
    my $attempts = 0;
    while (($attempts < 3 && !$tweets_found)) {
    	$attempts++;
		parse_tweets();
    	$tweets_found = keys %tweet_sha;
    	sleep 2;
    }
}
scroll_down();
while ($former_found != $tweets_found) {
	$former_found      = $tweets_found;
	parse_tweets();

	# Scroll up using JavaScript
	scroll_down();
}
sleep 2;

# Rendering every tweet of the thread.
my %tweets_by_inc       = ();
for my $sha256 (sort keys %tweet_sha) {
	my $tweet_incr     = $tweet_sha{$sha256}->{'tweet_incr'} // die;
	my $tweet         = $tweet_sha{$sha256}->{'tweet'}     // die;
	$tweets_by_inc{$tweet_incr} = $tweet;
}

my %tweets            = ();
my $former_alias;
open my $out, '>', "$profile_to_archive.html";
say $out "<body style=\"margin:0;overflow-x:none;overflow-y:auto;height:100vh;\">";
say $out "<div style=\"width:100\%;height:auto;margin:0;\">";
say $out "\t<div style=\"width:30\%;max-width:700px;min-width:300px;height:100\%;margin:auto;\">";
for my $tweet_incr (sort{$b <=> $a} keys %tweets_by_inc) {
	my $tweet         = $tweets_by_inc{$tweet_incr} // die;
	# Identifying if we have an avatar for the user.
	my $tweet_avatar   = $tweet->look_down("data-testid"=>"Tweet-User-Avatar");
	if ($tweet_avatar) {
		my ($user_alias, $user_pic) = alias_and_picture_from_tweet($tweet);
		my ($userName, $tweet_date) = name_and_date_from_tweet($tweet);
		my $tweet_text              = $tweet->look_down("data-testid"=>"tweetText");
		my @tweet_media             = $tweet->look_down("data-testid"=>"tweetPhoto");

		# Fetching the tweet URL.
		(my $tweet_url, $tweet_date) = parse_tweet_url($tweet, $tweet_date);
		die unless $tweet_url && $tweet_date;

		# Initiates tweet object.
		$tweets{$tweet_incr}->{'user_alias'} = $user_alias;
		$tweets{$tweet_incr}->{'user_pic'}   = $user_pic;
		$tweets{$tweet_incr}->{'user_name'}  = $user_name;
		$tweets{$tweet_incr}->{'tweet_date'} = $tweet_date;
		$tweets{$tweet_incr}->{'tweet_url'}  = $tweet_url;
		# p$tweets{$tweet_incr};

		# Storing profile picture.
		my ($user_local_pic) = $user_pic =~ /\/([^\/]+)$/;
		$user_local_pic      = $profile_pics_folder . "/$user_local_pic";
		unless (-f $user_local_pic) {
			getstore($user_pic, $user_local_pic) or die "failed to store [$user_local_pic]";
		}
		$user_alias =~ s/\//\@/;
		if (!$former_alias || ($former_alias && ($former_alias eq $user_alias))) {
			say $out "\t\t<div style=\"width:calc(100\% - 10px);margin-left:10px;margin-top:25px;height:50px;display:flex;flex-wrap:wrap;position:relative;font:inherit;\">";
		} else {
			say $out "\t\t<div style=\"width:calc(100\% - 10px);margin-left:10px;margin-top:25px;height:50px;display:flex;flex-wrap:wrap;position:relative;border-top:1px solid darkgrey;padding-bottom:10px;font:inherit;\">";
		}
		print_tweet_header($user_name, $user_alias, $user_local_pic);

		# Process each text child node
		if ($tweet_text) {
			parse_tweet_text($tweet_incr, $tweet_text);
		}
		say $out "\t\t<\/div>";
		# say $out "user_alias    : $user_alias";
		# say $out "user_pic      : $user_pic";
		# say $out "user_local_pic : $user_local_pic";
		my ($has_media,
			$has_video)  = parse_tweet_media(@tweet_media);

		# Prints tweet footer.
		if ($has_video) {
			say "Downloading Videos ...";
			my $video_file = download_video($tweet_url);
			$tweets{$tweet_incr}->{'video_file'} = $video_file;
			say $out "\t\t\t<div style=\"width:100\%;margin-top:10px;\">";
			say $out "\t\t\t\t<a href=\"$video_file\" target=\"_blank\"><img src=\"video_preview.png\" style=\"width:100\%;\"></a>";
			say $out "\t\t<\/div>";
		}
		print_tweet_footer($tweet_url, $tweet_date);
		$tweets{$tweet_incr}->{'has_media'}  = $has_media;
		$tweets{$tweet_incr}->{'has_video'}  = $has_video;
		$former_alias = $user_alias;
	} else { # Content isn't accessible, either because the user is blocked or deleted his tweet.
		my @spans = $tweet->find('span');
		for my $span (@spans) {
			my $text = $span->as_trimmed_text;
			if ($text) {
				$tweets{$tweet_incr}->{'tweet_text'} = $text;
				say $out "\t\t\t<div style=\"width:100\%;margin-top:10px;border-top:1px solid darkgrey;padding-bottom:10px;font:inherit;\"><span style=\"font:14px -apple-system,BlinkMacSystemFont,Roboto,Helvetica,Arial,sans-serif;font:Roboto,Helvetica,Arial,sans-serif;font-size:14px;\">$text</span></div>";
				last;
			}
		}
		$former_alias = '**no_poster_known**';
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
        my $tweet_data = $tweets[$i];

		# Fetching the tweet URL.
		my ($tweet_url) = parse_tweet_url($tweet_data);
        unless (exists $tweet_sha{$tweet_url}) {
            $tweet_incr++;
            $tweet_sha{$tweet_url}->{'tweet_incr'} = $tweet_incr;
            $tweet_sha{$tweet_url}->{'tweet'}     = $tweet_data;
        }
    }
    $tweets_found = keys %tweet_sha;
    say "Found [$tweets_found] tweets ...";
}


sub scroll_down {
	$driver->execute_script('window.scrollTo(0, document.body.scrollHeight);');
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
	my $user_name   = $ltrs[0]->as_trimmed_text;
	my $tweet_date;
	if ($ltrs[4]) {
		$tweet_date = $ltrs[4]->as_trimmed_text;
	}
	return ($user_name, $tweet_date);
}

sub print_tweet_header {
	my ($user_name, $user_alias, $user_local_pic) = @_;
	say $out "\t\t\t<div style=\"width:50px;height:100\%;position:absolute;z-index: -1;\">";
	say $out "\t\t\t\t<img style=\"width: 100\%; height: 100\%; object-fit: cover; border-radius: 50\%;\" src=\"$user_local_pic\">";
	say $out "\t\t\t<\/div>";
	say $out "\t\t\t<div style=\"width:50px;height:100\%;position:absolute;border:0 solid black;border-bottom-left-radius: 9999px;border-bottom-right-radius: 9999px;border-top-left-radius: 9999px;border-top-right-radius: 9999px;z-index: 0;\">";
	say $out "\t\t\t<\/div>";
	say $out "\t\t\t<div style=\"width:calc(100\% - 60px);height:100\%;position:absolute;margin-left:60px;\">";
	say $out "\t\t\t\t<div style=\"width:100\%;height:20px;margin-left:5px;margin-top:5px;\">";
	say $out "\t\t\t\t\t<b>$user_name</b>";
	say $out "\t\t\t\t<\/div>";
	say $out "\t\t\t\t<div style=\"width:100\%;height:20px;margin-left:5px;margin-top:5px;\">";
	say $out "\t\t\t\t\t$user_alias";
	say $out "\t\t\t\t<\/div>";
	say $out "\t\t\t<\/div>";
	say $out "\t\t<\/div>";
	say $out "\t\t<div style=\"width:calc(100\% - 10px);margin-left:10px;margin-top:10px;height:auto;display:flex;flex-wrap:wrap;position:relative;\">";
}

sub parse_tweet_text {
	my ($tweet_incr, $tweet_text) = @_;
	foreach my $child ($tweet_text->content_list) {
	    if ($child->tag eq 'span') {
	        # Process text nodes
	        my $text = $child->as_trimmed_text;
	        my %o = ();
	        $o{'type'} = 'text';
	        $o{'text'} = $text;
			say $out "\t\t\t<div style=\"width:100\%;height:5px;\"></div><span style=\"font:14px -apple-system,BlinkMacSystemFont,Roboto,Helvetica,Arial,sans-serif;font:Roboto,Helvetica,Arial,sans-serif;font-size:14px;\">$text</span>";
	        push @{$tweets{$tweet_incr}->{'tweet_text'}}, \%o;
	    } elsif ($child->tag eq 'img') {
	        # Process image nodes
	        my $src  = $child->attr('src');
	        my %o = ();
	        $o{'type'} = 'emoji';
	        $o{'src'}  = $src;
	        my ($localFile) = $src =~ /\/([^\/]+)$/;
	        $localFile = "$media_folder/$localFile";
			unless (-f $localFile) {
				getstore($src, $localFile) or die "failed to store [$localFile]";
			}
			say $out "\t\t\t<img style=\"width:20px;height:20px;\" src=\"$localFile\">";
	        push @{$tweets{$tweet_incr}->{'tweet_text'}}, \%o;
	    } elsif ($child->tag eq 'a') {
	        # Process image nodes
	        my $href = $child->attr('href');
	        if ($href !~ /http/) {
	        	$href = $twitter_url_base . $href;
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
	        push @{$tweets{$tweet_incr}->{'tweet_text'}}, \%o;
	    } elsif ($child->tag eq 'div') {
	        # Fetch account tagged
	        my $link  = $child->find('a');
	        my $href  = $link->attr_get_i('href');
	        $href     = $twitter_url_base . $href;
	        my $name  = $link->as_trimmed_text;
	        my %o = ();
	        $o{'type'} = 'tag';
	        $o{'name'} = $name;
	        $o{'href'} = $href;
			say $out "\t\t\t<div style=\"width:100\%;height:5px;\"></div><span style=\"font:14px -apple-system,BlinkMacSystemFont,Roboto,Helvetica,Arial,sans-serif;font:Roboto,Helvetica,Arial,sans-serif;font-size:14px;\"><a href=\"$href\" target=\"_blank\">$name</a></span>";
	        push @{$tweets{$tweet_incr}->{'tweet_text'}}, \%o;
	    } else {
	    	say "Something else : " . $child->tag;
	    	say $child->as_HTML('<>&', "\t");
	    }
	}
}

sub parse_tweet_url {
	my ($tweet, $tweet_date) = @_;
	my @divs = $tweet->find("div");
	my $tweet_url;
	for my $div (@divs) {
		next unless $div->find('a');
		my $link = $div->find('a');
		next unless $link->attr_get_i('href');
		my $href = $link->attr_get_i('href');
		next unless $href =~ /analytics$/;
		$tweet_url = $href;
	}
	unless ($tweet_url) {
		die if $tweet_date;
		my @as = $tweet->find('a');
		for my $link (@as) {
			next unless $link->attr_get_i('href');
			my $href   = $link->attr_get_i('href');
			next unless $href =~ /\/status\/\d+$/;
			$tweet_url  = $href;
			$tweet_url  =~ s/ \? / \| /;
			$tweet_date = $link->as_trimmed_text;
		}
	}
	$tweet_url =~ s/\/analytics$//;
	$tweet_url = $twitter_url_base . $tweet_url;
	return ($tweet_url, $tweet_date);
}

sub download_video {
	my $tweet_url  = shift;
    my $videoUrl;
    my ($tweetId) = $tweet_url =~ /\/status\/(\d+)/;
    my $localFile = "$media_folder/$tweetId.mp4";
	unless (-f $localFile) {
		$driver->get($vid_downloader_url);

		# Find the input field by its name attribute
		my $tweetField = $driver->find_element("(//input[\@id='main_page_text'])[1]");
		$tweetField->click();

		# Type the tweet url.
		$tweetField->send_keys($tweet_url);

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
	my (@tweet_media) = @_;
	my $has_media     = 0;
	my $has_video     = 0;
	my %pictures     = ();
	if (scalar @tweet_media) {
		$has_media    = 1;
		my $mediaNum = 0;
		for my $tweet_media (@tweet_media) {
			my $videoPlayer = $tweet_media->look_down("data-testid"=>"videoPlayer");
			if ($videoPlayer) {
				$has_video   = 1;
			} else {
				# Fetching pictures.
				my ($img)  = $tweet_media->look_down(_tag => 'img');
				my $src    = $img->attr('src');
		        my %o      = ();
		        $o{'type'} = 'pic';
		        $o{'src'}  = $src;
		        push @{$tweets{$tweet_incr}->{'media'}}, \%o;
		        my ($fileNameShort, $fileExt, $format) = $src =~ /media\/(.*)\?format=(.*)&name=(.*)/;
		        $src =~ s/$format$/large/;
		        my $localFile = "$media_folder/$fileNameShort.$fileExt";
				unless (-f $localFile) {
					getstore($src, $localFile) or die "failed to store [$localFile]";
				}
				say $out "\t\t\t<div style=\"width:100\%;margin-top:10px;\">";
				say $out "\t\t\t\t<a href=\"$localFile\" target=\"_blank\"><img src=\"$localFile\" style=\"width:100\%;\"></a>";
				say $out "\t\t<\/div>";
			}
		}
	}
	return ($has_media,
			$has_video);
}

sub print_tweet_footer {
	my ($tweet_url, $tweet_date) = @_;
	say $out "\t\t\t<div style=\"width:100\%;height:5px;\"></div>";
	say $out "\t\t<div style=\"width:calc(100\% - 10px);margin-left:10px;margin-top:10px;height:auto;display:flex;flex-wrap:wrap;position:relative;\">";
	say $out "\t\t\t<div style=\"width:100\%;\"></div>$tweet_date&nbsp;-&nbsp;<a href=\"$tweet_url\" target=\"_blank\">$tweet_url</a>";
	say $out "\t\t<\/div>";
}