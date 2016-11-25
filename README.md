# Ec2 Console

## Synopsis

Starts a spot instance on Amazon Web Services (AWS) from your latest Amazon
Machine Image (AMI) snap shot rather more conveniently than using the AWS EC2
console to perform this task.

Offers a list of machine types of interest and their latest spot prices on
which to run the latest AMI from which an instance can be started, snap shot
and stopped.

## Installation

Download this single standalone Perl script to any convenient folder.

### Perl

Perl can be obtained at:

[http://www.perl.org](http://www.perl.org)

You might need to install the following Perl modules:

    cpan install Data::Dump Term::ANSIColor Carp JSON POSIX Wx Alien::wxWidgets

### AWS Command Line Interface

Prior to using this script you should download/install the AWS CLI from:

[http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html](http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html)

## Configuration

### AWS

Run:

    aws configure

to set up the AWS CLI used by this script. The last question asked by aws
configure:

    Default output format [json]:

must be answered **json**.

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

#### IAM users

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

### Perl

To configure this Perl script you should use the AWS EC2 console at:

[https://console.aws.amazon.com/ec2/v2/home](https://console.aws.amazon.com/ec2/v2/home)

to start and snap shot an instance, in the process creating the security group
and key pair whose details should be recorded below in this script in the
section marked **user configuration**. Snap shot the running instance to create
an Amazon Machine Image (AMI) which can then be restarted quickly and
conveniently using this script. This script automatically finds the latest
snapshot run so there is no need to update this script to account for each new
snapshot made.

Configure this script by filling in the values in the **user configuration**
area below in the code.

## Operation

Run:

    perl ec2ConsoleGui.pl

Please note that AWS can repossess the spot instance at any time, thus all
permanent data used by the spot instance should be held in AWS S3 and updated
frequently by calling the S3 backup command:

    aws s3 sync

New software configurations should be backed up by creating a new AMI - this
script will automatically start the latest such AMI created.

## Bugs

Please reports bugs as issues on this project at GitHub:

[https://github.com/philiprbrenan/Ec2Console](https://github.com/philiprbrenan/Ec2Console)

## Licence

Perl Artistic License 2.0

[http://www.perlfoundation.org/artistic\_license\_2\_0/](http://www.perlfoundation.org/artistic_license_2_0/)

This module is free software. It may be used, redistributed and/or modified
under the same terms as Perl itself.
