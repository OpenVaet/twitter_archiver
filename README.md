# Twitter Archiver
## Twitter Thread Archiver using Selenium
### Requirements

- This script works for now exclusively on Windows. Support for other OS will be added later.
- You'll need a recent version of Strawberry Perl at https://strawberryperl.com/
- You'll need the non-core libraries used, which you can install with the following commands:
* cpanm Selenium::Chrome
* cpanm autovivification
* cpanm Data::Printer
* cpanm JSON
* cpanm Encode
* cpanm HTTP::Request::Common
* cpanm HTTP::Headers
* cpanm Digest::SHA
* cpanm File::Path
- You'll need Google Chrome installed, and the Chrome Driver corresponding to your OS & version, available here: https://chromedriver.chromium.org/downloads, placed in your project root folder.
- Line 45 of the script, you'll need to configure your Windows Session username.

### Archiving a Twitter Thread
- From the project root folder, use _[perl twitter_archiver.pl]_ (no brackets) to run the script.
- Input the URL of the last Tweet of the thread you wish to archive.
- If you want to archive a thread including a locked account, you'll need a Twitter account following this user, and to login first, by using the --login argument

### Expected Result
- Once done archiving every asset & tweet, starting from the last Tweet you indicated as target, the script will input an HTML file allowing you access to every asset used in the thread (pictures, emojis, videos, external links, etc.)