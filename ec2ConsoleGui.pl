#!/usr/bin/perl
#-------------------------------------------------------------------------------
# Start/snapshot/stop and instance in EC2 via wx Test wx::Perl
# Philip R Brenan at gmail dot com, Appa Apps Ltd, 2016
#-------------------------------------------------------------------------------

use warnings FATAL => qw(all);
use strict;
use Data::Dump qw(dump);
use Carp;
use JSON;
use POSIX qw(strftime);                                                         # http://www.cplusplus.com/reference/ctime/strftime/
use Wx qw(:everything);
use Wx::Html;

=pod

=head1 Ec2 Console

=head2 Synopsis

Starts a spot instance on Amazon Web Services (AWS) from your latest Amazon
Machine Image (AMI) snap shot rather more conveniently than using the AWS EC2
console to perform this task.

Offers a list of machine types of interest and their latest spot prices on
which to run the latest AMI from which an instance can be started, snap shot
and stopped.

=head2 Installation

Download this single standalone Perl script to any convenient folder.

=head3 Perl

Perl can be obtained at:

L<http://www.perl.org>

You might need to install the following Perl modules:

 cpan install Data::Dump Term::ANSIColor Carp JSON POSIX Wx Alien::wxWidgets

=head3 AWS Command Line Interface

Prior to using this script you should download/install the AWS CLI from:

L<http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html>

=head2 Configuration

=head3 AWS

Run:

 aws configure

to set up the AWS CLI used by this script. The last question asked by aws
configure:

 Default output format [json]:

must be answered B<json>.

You can confirm that aws cli is correctly installed by executing:

 aws ec2 describe-availability-zones

which should produce something like:

 {   "AvailabilityZones": [
         {   "ZoneName": "us-east-1a",
             "RegionName": "us-east-1",
             "Messages": [],
             "State": "available"
         },
     ]
 }

=head4 IAM users

If you are configuring an IAM userid please make sure that this userid is permitted
to execute the following commands:

 aws ec2 cancel-spot-instance-requests
 aws ec2 create-image
 aws ec2 describe-images
 aws ec2 describe-instances
 aws ec2 describe-key-pairs
 aws ec2 describe-security-groups
 aws ec2 describe-spot-instance-requests
 aws ec2 describe-spot-price-history
 aws ec2 request-spot-instances
 aws ec2 terminate-instances

=head3 Perl

To configure this Perl script you should use the AWS EC2 console at:

L<https://console.aws.amazon.com/ec2/v2/home>

to start and snap shot an instance, in the process creating the security group
and key pair whose details should be recorded below in this script in the
section marked B<user configuration>. Snap shot the running instance to create
an Amazon Machine Image (AMI) which can then be restarted quickly and
conveniently using this script. This script automatically finds the latest
snapshot run so there is no need to update this script to account for each new
snapshot made.

Configure this script by filling in the values in the B<user configuration>
area below in the code.

=head2 Operation

Run:

 perl ec2ConsoleGui.pl

Please note that AWS can repossess the spot instance at any time, thus all
permanent data used by the spot instance should be held in AWS S3 and updated
frequently by calling the S3 backup command:

 aws s3 sync

New software configurations should be backed up by creating a new AMI - this
script will automatically start the latest such AMI created.

=head2 Bugs

Please reports bugs as issues on this project at GitHub:

L<https://github.com/philiprbrenan/StartSpotInstanceFromLatestAMI>

=head2 Licence

Perl Artistic License 2.0

L<http://www.perlfoundation.org/artistic_license_2_0/>

This module is free software. It may be used, redistributed and/or modified
under the same terms as Perl itself.

=cut

#-------------------------------------------------------------------------------
# User configuration
#-------------------------------------------------------------------------------

my $keyPair              = qr(AmazonKeyPair);                                   # Choose the keypair via a regular expression which matches your key pair name created on the AWS EC2 console just before launching an instance
my $security             = qr(open);                                            # Choose the security group via a regular expression which matches the description or the name of your security group on the AWS EC2 console
my $instanceTypes        = qr(\A[mt]\d\.);                                      # Choose the instance types to consider via a regular expression. The latest spot instance prices will be retrieved and presented to the user allowing a manual selection on price to be made.
my $bidPriceMultiplier   = 1.04;                                                # Multiply the spot price by this value to get the bid price for the spot instance
my $instanceTitle        = 'Test';                                              # Title to be used for AMI snap shots
my $productDescription   = "Linux/UNIX";                                        # General type of OS to be run on the instance - Windows is 4x Linux in price.

my $debugging            = 0;                                                   # 0 - for real, 1 - debugging
my $testing              = 0;                                                   # 0 - for real, not testing, 1 - Use previous test results rather than executing commands
my $useTestPrice         = 0;                                                   # 0 - use a bid price computed from the current spot price that is likely to work, 1 - use the following price for the requested spot request for testing purposes
my $testSpotRequestPrice = 0.001;                                               # A price (in US dollars) low enough to be rejected for any spot request yet still be accepted as syntactically correct
my $updateFrequency      = 120e3;                                               # Update the display this frequently (ms) - the display changes color when we are busy
my $busyColor            = 'ffcccc';                                            # Background colour when we are busy
my $saveSoftware         = 1;                                                   # 1 - upload to S3 after successful run
my $displaySizeX         = 1600;                                                # Width of display
my $displaySizeY         =  800;                                                # Height of display
my $displayFont          = 'DejaVu';                                            # Font to use on display
my $displayFontFixed     = 'Mono';                                              # Fixed font to use on display
my $displayFontSizes     = [16, 18, 20, 24, 28, 32, 36];                        # The seven font sizes of HTML
my $displayTitle         = 'EC2 Console';                                       # Title of the display

#-------------------------------------------------------------------------------
# Wx
#-------------------------------------------------------------------------------

my $app = Wx::SimpleApp->new;
my $frame = Wx::Frame->new( undef, -1, $displayTitle, [-1, -1], [$displaySizeX, $displaySizeY]);
   $frame->Centre();

my $html = Wx::HtmlWindow->new($frame, -1);                                     # Create html window
   $html->SetFonts($displayFont, $displayFontFixed, $displayFontSizes);
   $html->SetPage (<<END);
<body bgcolor=#$busyColor>
<h1>EC2 Console</h1>
<p>Fetching current status from EC2 which will take a moment or two.
</body>
END

Wx::Event::EVT_HTML_LINK_CLICKED($html, -1, sub                                 # User clicked a link
 {my ($htmlWindow, $event) = @_;
  my $href = $event->GetLinkInfo->GetHref;
  my @w = split /\s+/, $href;

  my $c = {killSpotRequest=>\&killSpotRequest, startSpot   =>\&startSpot,
           createImage    =>\&createImage,     killInstance=>\&killInstance};

  if (@w and my $C = $c->{$w[0]})
   {shift @w;
    $C->(@w)
   }
  else {confess "Unable to process command =$href="}
 });

my $resultsCache;                                                               # Results cache so that we do not continually refresh slow requests
my $refreshes;                                                                  # Number of refreshes for a request
my $lastHtml;                                                                   # Last html displayed
my $lastSub;                                                                    # Last action saved

my $timerDisplayRefresh = Wx::Timer->new($html);                                # Timer that kicks off the refresh cycle
   $timerDisplayRefresh->Start(1000, 1);

my $timerChangeColor = Wx::Timer->new($html);                                   # Timer to change colour while we are busy

Wx::Event::EVT_TIMER($html, -1, sub                                             # Starts the display update cycle
 {my ($htmlWindow, $event) = @_;
  my $timer = $event->GetTimer;                                                 # The timer that caused the event
  if ($timer == $timerDisplayRefresh)                                           # Refresh periodically
   {&::updateDisplay(undef,                                                     # No action required before refreshing data
     qw(describeInstances describeSpotInstanceRequests));                       # Refresh spot requests, instances
   }
  else                                                                          # Refresh with no special actions
   {&::updateDisplayAfterColorChange($lastSub);
    $lastSub = undef;                                                           # Action has been dispatched
   }
 });

sub updateDisplay($@)                                                           # Update display after first executing an optional sub and removing entries from the cache
 {my ($sub, @cache) = @_;                                                       # Action before refreshing, cache entries to remove
  $resultsCache->{$_}{delay} = $refreshes->{$_} for @cache;                     # Remove this data from the cache
  $lastSub = $sub;                                                              # Save the action so that it can be called after updating the display with the background colour
  if ($lastHtml)                                                                # Show last display with colored background while long running data refresh occurs
   {$timerChangeColor->Start(1000, 1);                                          # Start collection of data after screen has been updated
    my $s = "<body bgcolor=#$busyColor>$lastHtml</body>";                       # Change color of background
    $html->SetPage($s);                                                         # Show page
   }
  else {&updateDisplayAfterColorChange($sub)}                                   # No old display continue with what ever is already being displayed
 }

sub updateDisplayAfterColorChange($)                                            # Fetch information and update display
 {my ($sub, @cache) = @_;                                                       # Sub to call to perform additional actions while the display is marked as busy

  Log "Start";                                                                  # Long section start time
  $lastHtml = ($sub ? &$sub : '').                                              # Action before data is refreshed if supplied
    &describeInstances.&describeSpotInstanceRequests.&requestSpotInstance;      # Refresh data
  Log "Stop";                                                                   # Finished long section

  $html->SetPage($lastHtml);                                                    # Show without busy colour
  $timerDisplayRefresh->Start($updateFrequency, 1);                             # Continue the display refresh cycle
 }

$frame->Show;                                                                   # Show the html window
$app->MainLoop;                                                                 # Run the application

if ($saveSoftware)                                                              # Save file to S3 - this will not work unless you are me.
 {print for qx(zip $0.zip $0 && aws s3 cp $0.zip s3://AppaAppsSourceVersions/$0.zip && rm $0.zip);
 }

#-------------------------------------------------------------------------------
# Aws
#-------------------------------------------------------------------------------

sub dateTimeStamp() {strftime('%Y-%m-%d at %H:%M:%S', localtime)}               # Time stamps
sub timeStamp()     {strftime('%H:%M:%S', localtime)}
sub Log(@) {say STDERR &timeStamp, ' ', join '', @_}                            # Log a message

sub awsEc2($$$$$)                                                               # Execute an Ec2 command and return the error code and Json converted to a Perl data structure
 {my ($command, $testResults, $cacheName, $cacheTime, $refresh) = @_;           # Command, test data, cache entry name, cache time in seconds, cache refreshes
  $refreshes->{$cacheName} = $refresh;                                          # Record refresh rate

  my $c = $command; my $t = $testResults;
  $c =~ s/\n/ /g; $c = "aws ec2 $c";                                            # Put command on one line
  Log "awsEc2 1111 $c" if $debugging;

  my ($r, $j) = sub                                                             # Test or execute - r == 0 means success
   {return (0, $t) if $testing;
    my $C = $resultsCache->{$cacheName} //= {};
    if (!$C->{time} or $C->{time} < time() - $cacheTime or $C->{delay}--)       # Execute unless we have a cached result
     {my $p = qx($c);
      my $r = $?;
      unless($r)                                                                # Cache a good result
       {$C->{time}   = time();
        $C->{result} = $p;
       }
      return ($r, $p);
     }
    (0, $C->{result})                                                           # Return cached result
   }->();

  return (1, $j) if $r;
  Log 'awsEc2 2222 ', dump({r=>$r, j=>$j}) if $debugging;
  my $p = decode_json($j);
  (0, $p)
 }

sub describeSpotInstanceRequests                                                # Open instances
 {my ($r, $p) = awsEc2('describe-spot-instance-requests',
                   &testDescribeSpotInstanceRequests,
                        describeSpotInstanceRequests=>30, 2);
  return "Unable to get spot requests: $p" if $r;
  my @p = grep {$_->{State} =~ /open|fulfilled/i} @{$p->{SpotInstanceRequests}};
  my $s = '';
  if (@p)
   {$s .= <<END;
<h2>Open spot requests</h2>
<table cellspacing=10 border=1>
<tr><th>Type</th><th>price/cents</th><th>State</th><th>id</th></tr>
END
    for(@p)
     {my ($id, $price, $state, $launch, $status) = @$_{qw(SpotInstanceRequestId SpotPrice State LaunchSpecification Status)};
      my ($type) = @$launch{qw(InstanceType)};
      my ($message) = @$status{qw(Message)};
      $price *= 100;
      $s .= "<tr><td><a href='killSpotRequest $id $type'>$type</a></td><td align=right>$price</td><td>$id</td><td>$state</td><td>$message</td></tr>";
     }
    $s .= <<END;
</table>
<p>Click on the <b>type</b> to <b>kill</b> the spot instance request.
END
   }
  $s
 }

sub killSpotRequest                                                             # Kill specified spot instance request
 {my ($id, $type) = @_;
  my ($answer) = Wx::MessageBox("Kill request for $type instance $id?", 'Kill Spot Instance Request', Wx::wxYES_NO(), undef);
  return unless $answer == Wx::wxYES();
  my $action = sub
   {my ($r, $p) = awsEc2(<<END, &testCancelSpotInstanceRequests, killSpotRequest=>0, 0);
cancel-spot-instance-requests --spot-instance-request-ids $id
END
    return  "killSpotRequest: $p" if $r;

    my $s = <<END;
<p>Killed the following spot instance requests:
<p><table cellspacing=10 border=1>
END
    for(@{$p->{CancelledSpotInstanceRequests}})
     {my ($id, $state) = @$_{qw(SpotInstanceRequestId State)};
      $s .= "<tr><td>$id</td><td>$state</td></tr>";
     }
    $s.<<END
</table>
END
   };
  &updateDisplay($action, qw(describeSpotInstanceRequests));                    # Need to get spot requests again
 }

sub describeImages                                                              # Images
 {awsEc2(<<END, &testDescribeImages, describeImages=>3600, 60)
describe-images --owners self
END
 }

sub describeKeyPairs                                                            # Keypairs
 {awsEc2(<<END, &testDescribeKeyPairs, describeKeyPairs=>5e3, 0)
describe-key-pairs
END
 }

sub describeSecurityGroups                                                      # Security groups
 {awsEc2(<<END, &testDescribeSecurityGroups, describeSecurityGroups=>10e3, 0)
describe-security-groups
END
 }

sub describeSpotPriceHistory(@)
 {my @types = @_;                                                               # Instance types which match the re for which spot history is required
  my $types = join ' ', @types;
  my $time  = time(); my $timeStart = $time-3600;                               # Last hour of spot pricing history
  awsEc2(<<END, &testDescribeSpotPriceHistory, describeSpotPriceHistory=>3600, 0)
describe-spot-price-history --instance-types $types --start-time $timeStart --end-time $time --product-description "$productDescription"
END
 }

sub latestImage                                                                 # Details of latest image
 {my ($r, $p) = describeImages;
  unless($r)
   {my @i;
    for(@{$p->{Images}})
     {my ($c, $d, $i) = @$_{qw(CreationDate Description ImageId)}; $d //= '';
      push @i, [$i, $c, $d];
     }
    Log 'latestImage ', dump(\@i) if $debugging;
    my @I = sort {$b->[1] cmp $a->[1]} @i;                                      # Images, with most recent first
    return (1, $I[0]);                                                          # Latest image name
   }
  (0, "No images available, please logon to AWS and create one")
 }

sub checkedKeyPair                                                              # Key pair that matches the keyPair global
 {my ($r, $p) = describeKeyPairs;
  unless($r)
   {my @k;
    for(@{$p->{KeyPairs}})
     {my ($n, $f) = @$_{qw(KeyName KeyFingerprint)};
      push @k, $n if $n =~ m/$keyPair/i;
     }
    Log 'checkedKeyPair ', dump(@k) if $debugging;
    return (1, $k[0]) if @k == 1;                                               # Found the matching key pair
    return (0, "No unique match for key pair $keyPair, please choose one from the list above and use it to set the keyPair global variable at the top of this script");
   }
  (0,  "No key pairs available, please logon to AWS and create one");
 }

sub checkedSecurityGroup                                                        # Choose the security group that matches the securityGroup global
 {my ($r, $p) = describeSecurityGroups;
  unless($r)
   {my @g;
    for(@{$p->{SecurityGroups}})
     {my ($d, $g) = @$_{qw(Description GroupId)}; $d //= '' ;                   # Ensure description is not null
      push @g, [$g, $d]  if $d =~ m/$security/i or $g =~ m/$security/i;
     }
    Log 'checkedSecurityGroup ', dump(\@g) if $debugging;
    return (1, $g[0]) if @g == 1;                                               # Found the matching key pair
    return (0,  "No unique match for key pair $security, please choose one from the list above and use it to set the security global variable at the top of this script");
   }
  (0,  "No security groups available, please logon to AWS and create one");
 }

sub checkedInstanceTypes                                                        # Choose the instance types of interest
 {my @I = &instanceTypes;
  my @i = grep {/$instanceTypes/i} @I;
  Log 'checkedInstanceTypes ', dump(\@i) if $debugging;
  return (1, @i) if @i;                                                         # Found the matching key pair
  (0,  "Please choose from: ". join(' ', @I). " using the instanceType global at the top of this script");
 }

sub spotPriceHistory(@)                                                         # Get spot prices for instances of interest
 {my @instanceTypes = @_;
  my ($r, $p) = describeSpotPriceHistory(@instanceTypes);
  unless($r)
   {my %p;
    for(@{$p->{SpotPriceHistory}})
     {my ($t, $z, $p) = @$_{qw(InstanceType AvailabilityZone SpotPrice)};
      push @{$p{$t}{$z}}, $p;
     }
    Log 'spotPriceHistory 1111 ', dump(\%p) if $debugging;
    for   my $t(keys %p)                                                        # Average price for each zone
     {for my $z(keys %{$p{$t}})
       {my @p = @{$p{$t}{$z}};
        my $a = 0; $a += $_ for @p; $a /= @p; $a = int(1e4*$a)/1e4;             # Round average price
        $p{$t}{$z} = $a;
       }
     }
    Log 'spotPriceHistory 2222 ', dump(\%p) if $debugging;
    for   my $t(keys %p)                                                        # Cheapest zone for each type
     {my $Z;
      for my $z(keys %{$p{$t}})
       {$Z = $z if !$Z or $p{$t}{$z} < $p{$t}{$Z};
       }
      $p{$t} = [$t, $Z, $p{$t}{$Z}];
     }
    Log 'spotPriceHistory 3333 ', dump(\%p) if $debugging;
    return (1, map {$p{$_}} sort {$p{$a}[2] <=> $p{$b}[2]} keys %p);            # Cheapest zone and price for each type in price order
   }
  (0,  "No spot history available");
 }

sub requestSpotInstance
 {my ($r1, $latestImage)   = &latestImage;                                      # Image details
  return "<p>$latestImage</p>" unless $r1;

  my ($r2, $keyPair)       = &checkedKeyPair;                                   # Key pair
  return "<p>$keyPair</p>" unless $r2;

  my ($r3, $securityGroup) = &checkedSecurityGroup;                             # Security group
  return "<p>$securityGroup</p>" unless $r3;

  my ($r4, @instanceTypes)    = checkedInstanceTypes;                           # Instance types of interest
  return "<p>@instanceTypes</p>" unless $r4;

  my ($r5, @spotPriceHistory) = spotPriceHistory(@instanceTypes);               # Get spot prices for instances of interest
  return "<p>@spotPriceHistory</p>" unless $r5;

  my ($imageId, $imageDescription, $imageDate) = @$latestImage;
  my ($securityGroupName, $securityGroupDesc) = @$securityGroup;

  my $html = '<h2>Start a spot instance</h2>';

  $html .= <<END;
<p>Click instance type to start</p>
<p><table cellspacing=10 border=1>
<tr><th>Type</th><th>Price</th><th>Zone</th></tr>
END

  for(1..@spotPriceHistory)
   {my ($spotType, $spotZone, $spotPrice) = @{$spotPriceHistory[$_-1]};
    $html .= "<tr><td><a href='startSpot $spotType $spotPrice $spotZone $imageId $keyPair $securityGroupName'>$spotType</a></td><td>$spotPrice</td><td>$spotZone</td></tr>";
   }
  $html .= <<END;
</table>
END

  $html .= <<END;                                                               # Image/key pair/security
<p>Instance parameters:</p>

<p><table cellspacing=10 border=1>
<tr align=left><th>Image</th><td>$imageId</td><td> created at $imageDate - $imageDescription</td></tr>
<tr align=left><th>Key pair</th><td>$keyPair</td></tr>
<tr align=left><th>Security</th><td>$securityGroupName</td><td>$securityGroupDesc</td></tr>
</table>
END

  $html
 }

sub startSpot
 {my ($spotType, $spotPrice, $spotZone, $imageId, $keyPair, $securityGroupName) = @_;

  my $spotPriceInCents = $spotPrice * 100;
  my ($answer) = Wx::MessageBox("Start $spotType instance\nat $spotPriceInCents cents per hour?", 'Start Spot Instance', Wx::wxYES_NO(), undef);
  return unless $answer == Wx::wxYES();

  my $action = sub
   {my $spec = <<END =~ s/\n/ /gr;                                              # Instance specification
 {"ImageId": "$imageId",
  "KeyName": "$keyPair",
  "SecurityGroupIds": ["$securityGroupName"],
  "InstanceType": "$spotType",
  "Placement": {"AvailabilityZone": "$spotZone"}
 }
END

    if ($^O !~ /mswin32/i)  {$spec = "'$spec'"}                                 # windows quoting problem
    else
     {$spec =~ s/"/\\"/g;
      $spec = "\"$spec\""
     }

    my $bidPrice = $useTestPrice ? $testSpotRequestPrice : $bidPriceMultiplier * $spotPrice; # Bid price

    my $cmd = <<END;                                                            # Command to request spot instance
request-spot-instances --spot-price $bidPrice --type "one-time" --launch-specification $spec
END

    my ($r, $p) = awsEc2($cmd, &testRequestSpotInstance, startSpot=>0, 0);

    return "startSpot: $p" if $r;

    my $t = $p->{SpotInstanceRequests}[0]{Status}{Message};
    <<END;
<p>Requested spot instance: $t
END
   };
  &updateDisplay($action, qw(describeSpotInstanceRequests));                    # Need to get spot requests again
 } # startSpot


sub describeInstances                                                           # Instances
 {my ($r, $p) = awsEc2(<<END, &testDescribeInstances, describeInstances=>60, 5);
describe-instances
END

  return "Unable to get instances: $p" if $r;

  my @html;
  for   my $r(@{$p->{Reservations}})
   {for my $i(@{$r->{Instances}})
     {my $state      = $i->{State}{Name};
      next unless $state =~ /running/i;
      my $ip         = $i->{PublicIpAddress};
      my $instanceId = $i->{InstanceId};
      my $type       = $i->{InstanceType};
      my $launchTime = $i->{LaunchTime};

      push @html, <<END;
<tr><td><a href='createImage $instanceId $type $ip'>$instanceId</a></td><td>$type</td><td>$ip</td><td>$state</td><td><a href='killInstance $instanceId $type $ip'>$launchTime</a></td></tr>
END
     }
   }
  if (@html)
   {my $s = join "\n", @html;
    return <<END;
<h2>Instances</h2>
<p><table cellspacing=10 border=1>
<tr><th>Id</th><th>Type</th><td>IP address</td><td>State</td><td>Launch Time</td></tr>
$s
</table>
<p>Click on the <b>Id</b> to <b>snap shot</b> the instance.
<p>Click on the <b>Launch Time</b> to <b>kill</b> the instance.
END
   }
  ''
 }

sub killInstance                                                                # Kill specified instance
 {my ($id, $type, $ip) = @_;
  my ($answer) = Wx::MessageBox("Kill $type instance $id at $ip?", 'Kill Instance', Wx::wxYES_NO(), undef);
  return unless $answer == Wx::wxYES();
  my $action = sub
   {my ($r, $p) = awsEc2(<<END, &testTerminateInstance, killInstance=>0, 0);
terminate-instances --instance-ids $id
END
    return  "killInstance: $p" if $r;

    my $s = <<END;
<p>Killed the following spot instances:
<p><table cellspacing=10 border=1>
END
    for(@{$p->{TerminatingInstances}})
     {my ($id, $currentState) = @$_{qw(InstanceId CurrentState)};
      my ($state)             = @$currentState{qw(Name)};
      $s .= "<tr><td>$id</td><td>$state</td></tr>";
     }
    $s.<<END
</table>
END
    };
  &updateDisplay($action, qw(describeInstances));                               # Need to get instances again
 }

sub createImage
 {my ($id, $type, $ip) = @_;
  my ($answer) = Wx::MessageBox("Snapshot  $type instance $id at $ip?", 'Kill Spot Instance', Wx::wxYES_NO(), undef);
  return unless $answer == Wx::wxYES();
  my $action = sub
   {my $description = $instanceTitle.' at '.&dateTimeStamp;
    my $name = $description =~ s/[^a-z0-9]/_/gri;
    my ($r, $p) = awsEc2(<<END, &testCreateImage, createImage=>0, 0);
create-image --instance-id $id --name "$name" --description "$description" --no-reboot
END
    return  "createImage: $p" if $r;
    my $s = <<END;
<p>Creating image from $type instance at $ip
END
   };
  &updateDisplay($action, qw(describeImages));                                  # Need to get images again
 }

sub checkVersion
 {my @w = split /\s+/, qx(aws --version 2>&1);
  my @v = $w[0] =~ m/(\d+)/g;
  return 1 if $v[0] >   1;
  return 1 if $v[1] >= 10;
  (0,  "Version  of aws cli too low - please reinstall from: http://docs.aws.amazon.com/cli/latest/userguide/installing.html");
 }

#-------------------------------------------------------------------------------
# Test data
#-------------------------------------------------------------------------------
#pod2markdown < $0 > README.md

sub testCancelSpotInstanceRequests{<<END}
{
    "CancelledSpotInstanceRequests": [
        {
            "State": "cancelled",
            "SpotInstanceRequestId": "sir-08b93456"
        }
    ]
}
END

sub instanceTypes{split /\n/, <<END}
t1.micro
t2.nano
t2.micro
t2.small
t2.medium
t2.large
m1.small
m1.medium
m1.large
m1.xlarge
m3.medium
m3.large
m3.xlarge
m3.2xlarge
m4.large
m4.xlarge
m4.2xlarge
m4.4xlarge
m4.10xlarge
m4.16xlarge
m2.xlarge
m2.2xlarge
m2.4xlarge
cr1.8xlarge
r3.large
r3.xlarge
r3.2xlarge
r3.4xlarge
r3.8xlarge
x1.16xlarge
x1.32xlarge
i2.xlarge
i2.2xlarge
i2.4xlarge
i2.8xlarge
hi1.4xlarge
hs1.8xlarge
c1.medium
c1.xlarge
c3.large
c3.xlarge
c3.2xlarge
c3.4xlarge
c3.8xlarge
c4.large
c4.xlarge
c4.2xlarge
c4.4xlarge
c4.8xlarge
cc1.4xlarge
cc2.8xlarge
g2.2xlarge
g2.8xlarge
cg1.4xlarge
p2.xlarge
p2.8xlarge
p2.16xlarge
d2.xlarge
d2.2xlarge
d2.4xlarge
d2.8xlarge
END

sub testRequestSpotInstance{<<END}
{
    "SpotInstanceRequests": [
        {
            "Type": "one-time",
            "Status": {
                "UpdateTime": "2016-11-14T19:20:12.000Z",
                "Message": "Your Spot request has been submitted for review, and is pending evaluation.",
                "Code": "pending-evaluation"
            },
            "SpotPrice": "0.002000",
            "ProductDescription": "Linux/UNIX",
            "LaunchSpecification": {
                "Monitoring": {
                    "Enabled": false
                },
                "InstanceType": "t1.micro",
                "ImageId": "ami-f0a6bd98",
                "Placement": {
                    "AvailabilityZone": "us-east-1b"
                },
                "SecurityGroups": [
                    {
                        "GroupId": "sg-915543f9",
                        "GroupName": "open"
                    }
                ],
                "KeyName": "AmazonKeyPair"
            },
            "CreateTime": "2016-11-14T19:20:12.000Z",
            "SpotInstanceRequestId": "sir-6rgg45ij",
            "State": "open"
        }
    ]
}
END

sub testDescribeSpotPriceHistory {<<END}
{
    "SpotPriceHistory": [
        {
            "InstanceType": "m1.xlarge",
            "AvailabilityZone": "us-east-1b",
            "SpotPrice": "0.033200",
            "Timestamp": "2016-11-12T19:22:24.000Z",
            "ProductDescription": "Linux/UNIX"
        },
        {
            "InstanceType": "m1.xlarge",
            "AvailabilityZone": "us-east-1b",
            "SpotPrice": "0.033100",
            "Timestamp": "2016-11-12T19:15:57.000Z",
            "ProductDescription": "Linux/UNIX"
        },
        {
            "InstanceType": "m1.xlarge",
            "AvailabilityZone": "us-east-1b",
            "SpotPrice": "0.033000",
            "Timestamp": "2016-11-12T19:12:16.000Z",
            "ProductDescription": "Linux/UNIX"
        }
    ]
}
END

sub testDescribeKeyPairs {<<END}                                                # Test key pairs
 {
    "KeyPairs": [
        {
            "KeyName": "AmazonKeyPair",
            "KeyFingerprint": "b5:b6:f2:06:f3:13:76:5d:37:46:72:cf:2a:6b:cd:f2:0f:71:6a:2c"
        }
    ]
}
END

sub testDescribeImages {<<END}                                                  # Test describe images
 {   "Images": [
        {
            "Public": false,
            "Description": "Ubuntu 2015-05-22",
            "Hypervisor": "xen",
            "KernelId": "aki-919dcaf8",
            "Tags": [
                {
                    "Value": "Ubuntu 2015-05-22",
                    "Key": "Name"
                }
            ],
            "Architecture": "x86_64",
            "OwnerId": "123456789012",
            "ImageLocation": "123456789012/Ubuntu 2015-05-22",
            "Name": "Ubuntu 2015-05-22",
            "ImageType": "machine",
            "RootDeviceName": "/dev/sda1",
            "BlockDeviceMappings": [
                {
                    "DeviceName": "/dev/sda1",
                    "Ebs": {
                        "SnapshotId": "snap-1cde1d53",
                        "DeleteOnTermination": true,
                        "Encrypted": false,
                        "VolumeSize": 8,
                        "VolumeType": "standard"
                    }
                }
            ],
            "CreationDate": "2015-05-22T08:11:43.000Z",
            "VirtualizationType": "paravirtual",
            "State": "available",
            "ImageId": "ami-f0a6bd98",
            "RootDeviceType": "ebs"
        },
        {
            "Public": false,
            "Description": "Ubuntu 2015-05-21",
            "Hypervisor": "xen",
            "KernelId": "aki-919dcaf8",
            "Tags": [
                {
                    "Value": "Ubuntu 2015-05-21",
                    "Key": "Name"
                }
            ],
            "Architecture": "x86_64",
            "OwnerId": "123456789012",
            "ImageLocation": "123456789012/Ubuntu 2015-05-21",
            "Name": "Ubuntu 2015-05-21",
            "ImageType": "machine",
            "RootDeviceName": "/dev/sda1",
            "BlockDeviceMappings": [
                {
                    "DeviceName": "/dev/sda1",
                    "Ebs": {
                        "SnapshotId": "snap-1cde1d53",
                        "DeleteOnTermination": true,
                        "Encrypted": false,
                        "VolumeSize": 8,
                        "VolumeType": "standard"
                    }
                }
            ],
            "CreationDate": "2015-05-21T08:11:43.000Z",
            "VirtualizationType": "paravirtual",
            "State": "available",
            "ImageId": "ami-f0a6bd97",
            "RootDeviceType": "ebs"
        }
    ]
}
END

sub testDescribeSecurityGroups {<<END}                                          # Test describe SecurityGroups
{
    "SecurityGroups": [
        {
            "Description": "AWS OpsWorks blank server - do not change or delete",
            "IpPermissions": [
                {
                    "PrefixListIds": [],
                    "IpProtocol": "tcp",
                    "UserIdGroupPairs": [],
                    "IpRanges": [
                        {
                            "CidrIp": "0.0.0.0/0"
                        }
                    ],
                    "FromPort": 22,
                    "ToPort": 22
                }
            ],
            "IpPermissionsEgress": [],
            "GroupId": "sg-67d7cb0f",
            "OwnerId": "123456789012",
            "GroupName": "AWS-OpsWorks-Blank-Server"
        },
        {
            "Description": "open access",
            "IpPermissions": [
                {
                    "PrefixListIds": [],
                    "IpProtocol": "tcp",
                    "UserIdGroupPairs": [],
                    "IpRanges": [
                        {
                            "CidrIp": "0.0.0.0/0"
                        }
                    ],
                    "FromPort": 0,
                    "ToPort": 65535
                },
                {
                    "PrefixListIds": [],
                    "IpProtocol": "udp",
                    "UserIdGroupPairs": [],
                    "IpRanges": [
                        {
                            "CidrIp": "0.0.0.0/0"
                        }
                    ],
                    "FromPort": 0,
                    "ToPort": 65535
                },
                {
                    "PrefixListIds": [],
                    "IpProtocol": "icmp",
                    "UserIdGroupPairs": [],
                    "IpRanges": [
                        {
                            "CidrIp": "0.0.0.0/0"
                        }
                    ],
                    "FromPort": -1,
                    "ToPort": -1
                }
            ],
            "IpPermissionsEgress": [],
            "GroupId": "sg-915543f9",
            "Tags": [
                {
                    "Key": "Name",
                    "Value": "Open"
                }
            ],
            "OwnerId": "123456789012",
            "GroupName": "open"
        }
    ]
}
END

sub testDescribeSpotInstanceRequests{<<END}
{
    "SpotInstanceRequests": [
        {
            "SpotPrice": "0.001000",
            "State": "cancelled",
            "ProductDescription": "Linux/UNIX",
            "LaunchSpecification": {
                "SecurityGroups": [
                    {
                        "GroupName": "open",
                        "GroupId": "sg-915543f9"
                    }
                ],
                "ImageId": "ami-f0a6bd98",
                "Placement": {
                    "AvailabilityZone": "us-east-1b"
                },
                "KeyName": "AmazonKeyPair",
                "InstanceType": "t1.micro",
                "Monitoring": {
                    "Enabled": false
                }
            },
            "CreateTime": "2016-11-17T02:52:12.000Z",
            "Status": {
                "Message": "Your Spot request is canceled before it was fulfilled.",
                "UpdateTime": "2016-11-22T18:57:14.000Z",
                "Code": "canceled-before-fulfillment"
            },
            "SpotInstanceRequestId": "sir-75sr7ysj",
            "Type": "one-time"
        },
        {
            "SpotPrice": "0.001000",
            "State": "open",
            "ProductDescription": "Linux/UNIX",
            "LaunchSpecification": {
                "SecurityGroups": [
                    {
                        "GroupName": "open",
                        "GroupId": "sg-915543f9"
                    }
                ],
                "EbsOptimized": false,
                "ImageId": "ami-f0a6bd98",
                "InstanceType": "m3.medium",
                "KeyName": "AmazonKeyPair",
                "Monitoring": {
                    "Enabled": false
                },
                "BlockDeviceMappings": [
                    {
                        "Ebs": {
                            "DeleteOnTermination": true,
                            "VolumeSize": 8,
                            "VolumeType": "standard"
                        },
                        "DeviceName": "/dev/sda1"
                    }
                ]
            },
            "CreateTime": "2016-11-22T18:45:33.000Z",
            "Tags": [
                {
                    "Value": "",
                    "Key": "Name"
                }
            ],
            "Status": {
                "Message": "Your Spot request price of 0.001 is lower than the minimum required Spot request fulfillment price of 0.0102.",
                "UpdateTime": "2016-11-22T18:45:49.000Z",
                "Code": "price-too-low"
            },
            "SpotInstanceRequestId": "sir-wdmg682g",
            "Type": "one-time"
        }
    ]
}
END

sub testDescribeInstances{<<END}
{
    "Reservations": [
        {
            "Groups": [
                {
                    "GroupName": "launch-wizard-1",
                    "GroupId": "sg-1d34950b"
                }
            ],
            "ReservationId": "r-0d51f2bb",
            "OwnerId": "231377230216",
            "Instances": [
                {
                    "AmiLaunchIndex": 0,
                    "InstanceLifecycle": "spot",
                    "ImageId": "ami-f0a6bd98",
                    "Monitoring": {
                        "State": "disabled"
                    },
                    "KernelId": "aki-919dcaf8",
                    "RootDeviceType": "ebs",
                    "Architecture": "x86_64",
                    "ClientToken": "b442d8e4-3962-4832-89ea-6bb3e397a960",
                    "LaunchTime": "2016-11-24T19:47:34.000Z",
                    "State": {
                        "Code": 16,
                        "Name": "running"
                    },
                    "Placement": {
                        "GroupName": "",
                        "AvailabilityZone": "us-east-1b",
                        "Tenancy": "default"
                    },
                    "PublicIpAddress": "54.91.93.237",
                    "KeyName": "AmazonKeyPair",
                    "PublicDnsName": "ec2-54-91-93-237.compute-1.amazonaws.com",
                    "Hypervisor": "xen",
                    "EbsOptimized": false,
                    "StateTransitionReason": "",
                    "PrivateIpAddress": "10.51.223.7",
                    "BlockDeviceMappings": [
                        {
                            "DeviceName": "/dev/sda1",
                            "Ebs": {
                                "Status": "attached",
                                "VolumeId": "vol-cf556d53",
                                "AttachTime": "2016-11-24T19:47:35.000Z",
                                "DeleteOnTermination": true
                            }
                        }
                    ],
                    "InstanceType": "t1.micro",
                    "SecurityGroups": [
                        {
                            "GroupName": "launch-wizard-1",
                            "GroupId": "sg-1d34950b"
                        }
                    ],
                    "InstanceId": "i-c72aec5f",
                    "SpotInstanceRequestId": "sir-w2h86mth",
                    "VirtualizationType": "paravirtual",
                    "NetworkInterfaces": [],
                    "RootDeviceName": "/dev/sda1",
                    "ProductCodes": [],
                    "PrivateDnsName": "ip-10-51-223-7.ec2.internal"
                }
            ],
            "RequesterId": "AIDAIWXPAEZCS5O3AMDAW"
        }
    ]
}
END
sub testTerminateInstance{<<END}
{
    "TerminatingInstances": [
        {
            "InstanceId": "i-1234567890abcdef0",
            "CurrentState": {
                "Code": 32,
                "Name": "shutting-down"
            },
            "PreviousState": {
                "Code": 16,
                "Name": "running"
            }
        }
    ]
}
END
sub testCreateImage{<<END}
END
