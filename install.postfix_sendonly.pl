#!/usr/bin/perl
use strict;
use warnings;

#----------------------------------------
# THIS SCRIPT WILL OVERWRITE ANY EXISTING
# POSTFIX CONFIGURATION
#----------------------------------------

#----------------------------------------
# This script will perform a simple setup
# of the Postfix mail agent for use as
# a send-only mailer on the Raspberry Pi
# running Raspbian Wheezy.
# It has been tested as a setup for using
# a Google Mail account for sending email
# and using an ISP smart smtp relay.
# Read through the script to check what it
# does and then run using sudo as a user
# with sudo permissions.
#
# sudo perl setuppostfix.txt
#----------------------------------------

my $hostname = qx(/bin/hostname);
chomp($hostname);
$hostname =~ s/[\s\r\n]//g;

my $domain = qx(/bin/hostname -d);
chomp($domain);
$domain =~ s/[\s\r\n]//g;
#----------------------------------------
# Configuration
# Alter the 7 items below to suit
# your required configuration. The items
# are described in the following sections
#----------------------------------------

my $fromuser      = 'root@' . $hostname;
my $adminuser     = 'root@' . $domain;
my @adminmaps     = qw( root pi );
my $smtpserver    = 'SERVER';
my $smtpport      = 587;
my $loginname     = 'USER';
my $loginpassword = 'PASSWORD';

#----------------------------------------
# $fromuser
#----------------------------------------
# Provide an email address to be used for
# the from and reply-to addrssses in emails
# FROM local users on this raspberry Pi.
# When you send mail through your ISP's or
# your own smart smtp relay, there must be
# a valid return address where smtp servers
# between you and the final destination can
# return messages. That ought to be your
# Raspberry Pi but as it is unlikely that
# you have your Pi set up as a visible
# internet server, you must provide an email
# address to be used as the From and
# Reply-To address when local users on your
# Raspberry Pi ( e.g. root@raspberrypi or
# pi@raspberrypi ) send email. The reply
# addresses will be rewritten so that the
# $fromuser email address is used instead.
# This only applies to mail that carries
# a 'local' From address. If your programs
# specifiy a real email address in sent mail
# that won't be rewritten.
# This re-writing is implemented by the
# Postfix  smtp_generic_maps facility.
# If you are using a Google Mail account
# to send your email, it doesn't really
# matter what you put in here. The Google
# servers will re-write whatever you put
# with your Google Mail address.
# If you are using your ISP smtp smarthost
# a genuine email address is probably
# mandatory. 

#----------------------------------------
# $adminuser and @adminmaps
#----------------------------------------
# If you wish, you may send mail destined
# for local users to an external email
# address. That is mail TO local users
# originating on this Raspberry Pi.
# The $adminuser variable contains
# the email address that you want to send
# these mails to. @adminmaps is a space
# separated list of local users whose mail
# you want to forward on.
# This is implemented using the /etc/aliases
# file. For the initial setup this is kept
# to a minimal simple implementation, but
# you can edit the file at any time to
# modify the settings and then run
# sudo newaliases
# to load them into Postfix

#----------------------------------------
# $smtpserver
#----------------------------------------
# This is the the remote smtp relay or
# mail account server. The server for
# Google Mail is already in the script
# so if you are using that you can leave
# it unchanged. Put your smart smtp relay
# in here if you are using one.

#----------------------------------------
# $smtpport
#----------------------------------------
# The port that your smtp server listens
# on. If you are using Google Mail then the
# correct port, 587, is already in the script
# so you can leave that.
# If you are using a smart smtp relay then that
# also most likely listens on port 587.
# You might be using an internal service that
# still listens on port 25, but if you are
# you'll most probably know about that anyway.
#------------------------------------------
# NOTE:
# starttls port 587 Vs wrapped ssl port 465
#------------------------------------------
# Postfix doesn't support 'wrapped ssl'
# communication directly. Servers that require
# this normally listen on Port 465. It is
# possible to use Postfix with wrapped ssl
# but it is beyond the scope of this simple
# script. Google for 'smtp 465 ssl Postfix'.
# Wrapped ssl is quite an old method of
# encrypting the smtp conversation so hopefully
# few people will come across this issue.

#------------------------------------------
# $loginname & $loginpassword
#------------------------------------------
# If you are communicating with a secure
# mail server on port 587 you'll need to
# provide login credentials. For your
# Google Mail account that will be your
# Google Email address and your Google
# login password.
# This will be stored in
# /etc/postfix/smtp_auth and
# /etc/postfix/smtp_auth.db so it is
# essential that these files are readable
# only by root.

#------------------------------------------
# SCRIPT INNARDS START HERE - You don't
# need to edit anything from here on in
# but there's nothing to stop you if you
# wish.
#------------------------------------------

my $maincf   = '/etc/postfix/main.cf';
my $smtpauth = '/etc/postfix/smtp_auth';
my $generic  = '/etc/postfix/generic';
my $aliases  = '/etc/aliases';

my $mailname = qx(cat /etc/mailname);
chomp($mailname);
$mailname =~ s/[\s\r\n]//g;

my $servername = $smtpserver;
$servername =~ s/[\[\]]//g;
unless( $smtpport) {
    die 'You must provide an smtp port';
}
$servername = qq([$servername]:$smtpport);

#------------------------------------------
# Make sure we are running via sudo and
# have the necessary permissions.
#------------------------------------------

die 'run this script as root using sudo' if $<;

#------------------------------------------
# Install Postfix
#------------------------------------------

system('apt-get -y update')
    and die 'failed to update package directories';
system('apt-get -y install postfix')
    and die 'failed to install postfix';

#------------------------------------------
# write /etc/mailname file
#------------------------------------------
system('/bin/hostname > /etc/mailname')
    and die 'failed to write /etc/mailname';

#------------------------------------------
# write the main /etc/postfix/main.cf file
#------------------------------------------

my $maincftemplate;

{
    my $protocols = 'ipv4';
    my $networks = '127.0.0.0/8';
    
    # check for ipv6
    my $procmods = qx(cat /proc/modules);
    die qq(failed reading /proc/modules : $?) if $?;
    if($procmods =~ /ipv6/) {
        $protocols .= ', ipv6';
        $networks .= ' [::ffff:127.0.0.0]/104 [::1]/128';
    }
    
    $maincftemplate = main_cf_template();
    $maincftemplate =~ s/REPLACEHOSTNAME/$mailname/g;
    $maincftemplate =~ s/REPLACESERVERNAME/$servername/g;
    $maincftemplate =~ s/REPLACEPROTOCOLS/$protocols/g;
    $maincftemplate =~ s/REPLACENETWORKS/$networks/g;
    
    open my $fh, '>', $maincf
        or die qq(failed to open $maincf : $!);
    print $fh $maincftemplate;
    close( $fh );
    chmod( 0644, $maincf );
}

#-----------------------------------------
# Write the generics file
#-----------------------------------------
if($fromuser){
    open my $fh, '>', $generic
        or die qq(failed to open $generic : $!);
        
    my($host, @discards) = split(/\./, $mailname);
    
    print $fh qq(\@$mailname    $fromuser\n);
    if($host ne $mailname) {
        print $fh qq(\@$host    $fromuser\n);
    }
    print $fh qq(\@localhost.localdomain    $fromuser\n);
    print $fh qq(\@localhost    $fromuser\n);
    close($fh);
    system(qq(postmap $generic))
       and die qq(failed to map generics : $!);
}

#-----------------------------------------
# Write the smtpauth
#-----------------------------------------
if($loginname && $loginpassword) {
    open my $fh, '>', $smtpauth
        or die qq(failed to open $smtpauth : $!);
    
    print $fh qq($servername $loginname:$loginpassword\n);
    close($fh);
    chmod(0600, $smtpauth) or
        die qq(failed to set permissions on $smtpauth : $!);
    
    system(qq(postmap $smtpauth))
       and die qq(failed to map generics : $!);
}

#-----------------------------------------
# Write the aliases
#-----------------------------------------

if( $adminuser && @adminmaps ){
    open my $fh, '>', $aliases
        or die qq(failed to open $aliases : $!);
        
    # add default post address
    print $fh qq(postmaster:    root\n);
    # add maps
    for( @adminmaps ) {
        print $fh qq($_:    $adminuser\n);
    }
    close($fh);
    system('newaliases')
        and die qq(failed calling newaliases : $!);
}

#------------------------------------------
# Restart Postfix and end
#------------------------------------------

system('/etc/init.d/postfix restart')
    and die qq(problems restart Postfix : $!);
    
    
#------------------------------------------
# Send an email
#------------------------------------------

my $emailtext =
qq(From: root
To: root
Subject: Postfix Send-Only Mail Configuration
Content-type: text/plain

Your Send-Only Postfix is configured on $mailname
with the following configuration:

/etc/postfix/main.cf <<
$maincftemplate
);

{
    open my $fh, '|/usr/sbin/sendmail -t'
        or die 'could not open pipe to sendmail';
    print $fh $emailtext;
    close($fh);
}

print qq(Postfix configuration complete\n);

#-----------------------------------------
# Templates
#-----------------------------------------

sub main_cf_template {
    my $template = <<'MAINCFTEMPLATE'
# Basic Null ( send only ) Postfix

smtpd_banner = Raspberry Pi Mail
biff = no
append_dot_mydomain = no
readme_directory = no
myhostname = REPLACEHOSTNAME
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
mydestination = REPLACEHOSTNAME, localhost.localdomain, localhost
relayhost = REPLACESERVERNAME
inet_protocols = REPLACEPROTOCOLS
mynetworks = REPLACENETWORKS
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = loopback-only
smtp_generic_maps = hash:/etc/postfix/generic

# TLS

smtp_use_tls=yes
smtp_sasl_auth_enable=yes
smtp_sasl_password_maps=hash:/etc/postfix/smtp_auth
tls_random_source=dev:/dev/urandom
smtp_sasl_security_options=noanonymous
smtp_tls_security_level=may

MAINCFTEMPLATE
;
    return $template;
}

1;
