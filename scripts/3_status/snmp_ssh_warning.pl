#!/usr/bin/perl
use strict;
use warnings;

use DBI;
use DBD::mysql;
use Mail::Sender;
use Encode;
use URI::Escape;
use URI::URL;
use Crypt::CBC;
use MIME::Base64;

our $time_now_utc = time;
my($min,$hour,$mday,$mon,$year) = (localtime $time_now_utc)[1..5];
($min,$hour,$mday,$mon,$year) = (sprintf("%02d", $min),sprintf("%02d", $hour),sprintf("%02d", $mday),sprintf("%02d", $mon + 1),$year+1900);
our $time_now_str = "$year$mon$mday$hour$min"."00";
our $time_now_subject = "$year-$mon-$mday $hour:$min";

our($mysql_user,$mysql_passwd) = &get_local_mysql_config();
our $dbh=DBI->connect("DBI:mysql:database=audit_sec;host=localhost;mysql_connect_timeout=3600",$mysql_user,$mysql_passwd,{RaiseError=>1});
our $utf8 = $dbh->prepare("set names utf8");
$utf8->execute();
$utf8->finish();

&mail_alarm_process($dbh);
&sms_alarm_process($dbh);

sub mail_alarm_process
{
	my($dbh) = @_;

	my %device_errlog;
	my %email_errlog;
	my %device_status;

	my $mail = $dbh->prepare("select mailserver,account,password from alarm");
	$mail->execute();
	my $ref_mail = $mail->fetchrow_hashref();
	my $mailserver = $ref_mail->{"mailserver"};
	my $mailfrom = $ref_mail->{"account"};
	my $mailpwd = $ref_mail->{"password"};
	$mail->finish();

	my $sqr_select = $dbh->prepare("select device_ip,datetime,type,disk,context from snmp_status_warning_log where mail_status = -1");
	$sqr_select->execute();
	while(my $ref_select = $sqr_select->fetchrow_hashref())
	{
		my $device_ip = $ref_select->{"device_ip"};
		my $datetime = $ref_select->{"datetime"};
		my $type = $ref_select->{"type"};
		my $disk = $ref_select->{"disk"};
		my $context = $ref_select->{"context"};

		unless(exists $device_errlog{$device_ip})
		{
			$device_errlog{$device_ip} = "$device_ip $datetime 告警:\n$context\n";
		}
		else
		{
			$device_errlog{$device_ip} .= "$context\n";
		}

		unless(exists $device_status{$device_ip})
		{
			my @types;
			my @disks;

			if(defined $disk)
			{
				push @disks,$disk;
			}
			elsif(defined $type)
			{
				push @types,$type;
			}

			my @tmp_arr = (\@types,\@disks,1);
			$device_status{$device_ip} = \@tmp_arr;
		}
		else
		{
			if(defined $disk)
			{
				push @{$device_status{$device_ip}->[1]},$disk;
			}
			elsif(defined $type)
			{
				push @{$device_status{$device_ip}->[0]},$type;
			}
		}
	}
	$sqr_select->finish();

	foreach my $device_ip(keys %device_errlog)
	{
		my $is_exist = 0;
		$sqr_select = $dbh->prepare("select email from member where uid IN(select memberid from snmp_alert_user a left join snmp_alert b on a.snmp_alert_id=b.seq where (b.groupid=(select groupid from servers where device_ip='$device_ip') or b.groupid=0) and b.enable=1) and email != ''");
		$sqr_select->execute();
		while(my $ref_select = $sqr_select->fetchrow_hashref())
		{
			my $email = $ref_select->{"email"};
			unless(defined $email)
			{
				next;
			}

			$is_exist = 1;

			unless(exists $email_errlog{$email})
			{
				my @tmp_device = ($device_ip);
				my @tmp_arr = (\@tmp_device,undef);

				$email_errlog{$email} = \@tmp_arr;
				$email_errlog{$email}->[1] = $device_errlog{$device_ip};
			}
			else
			{
				push @{$email_errlog{$email}->[0]}, $device_ip;
				$email_errlog{$email}->[1] .= $device_errlog{$device_ip};
			}
		}
		$sqr_select->finish();

		if($is_exist == 0)
		{
			$device_status{$device_ip}->[2] = 2;
		}
	}

	foreach my $mailto(keys %email_errlog)
	{
		my $subject = "主机监控告警 $time_now_subject";
		my $status = &send_mail($mailto,$subject,$email_errlog{$mailto}->[1],$mailserver,$mailfrom,$mailpwd);
#	my $status = &send_mail('wxl890206@126.com',$subject,$email_errlog{$mailto}->[1],$mailserver,$mailfrom,$mailpwd);

		if($status == 2)
		{
			foreach my $device_ip(@{$email_errlog{$mailto}->[0]})
			{
				$device_status{$device_ip}->[2] = $status;
			}
		}
	}

	foreach my $device_ip(keys %device_status)
	{
		my @types = @{$device_status{$device_ip}->[0]};
		my @disks = @{$device_status{$device_ip}->[1]};
		my $status = $device_status{$device_ip}->[2];

		my $sqr_update = $dbh->prepare("update snmp_status_warning_log set mail_status = $status where device_ip = '$device_ip' and mail_status = -1");
		$sqr_update->execute();
		$sqr_update->finish();

		if($status == 1)
		{
			if(scalar @types == 0 && scalar @disks == 0)
			{
				my $sqr_update = $dbh->prepare("update snmp_status set mail_last_sendtime = '$time_now_str' where device_ip = '$device_ip'");
				$sqr_update->execute();
				$sqr_update->finish();
			}
			else
			{
				foreach my $type(@types)
				{
					my $sqr_update = $dbh->prepare("update snmp_status set mail_last_sendtime = '$time_now_str' where device_ip = '$device_ip' and type = '$type'");
					$sqr_update->execute();
					$sqr_update->finish();
				}

				foreach my $disk(@disks)
				{
					my $sqr_update = $dbh->prepare("update snmp_status set mail_last_sendtime = '$time_now_str' where device_ip = '$device_ip' and type = 'disk' and disk = '$disk'");
					$sqr_update->execute();
					$sqr_update->finish();
				}
			}
		}
	}
}

sub sms_alarm_process
{
	my($dbh) = @_;

	my %device_errlog;
	my %mobile_errlog;
	my %device_status;

	my $sqr_select = $dbh->prepare("select device_ip,datetime,type,disk,context from snmp_status_warning_log where sms_status = -1");
	$sqr_select->execute();
	while(my $ref_select = $sqr_select->fetchrow_hashref())
	{
		my $device_ip = $ref_select->{"device_ip"};
		my $datetime = $ref_select->{"datetime"};
		my $type = $ref_select->{"type"};
		my $disk = $ref_select->{"disk"};
		my $context = $ref_select->{"context"};

		unless(exists $device_errlog{$device_ip})
		{
			$device_errlog{$device_ip} = "$device_ip $datetime 告警:\n$context\n";
		}
		else
		{
			$device_errlog{$device_ip} .= "$context\n";
		}

		unless(exists $device_status{$device_ip})
		{
			my @types;
			my @disks;

			if(defined $disk)
			{
				push @disks,$disk;
			}
			elsif(defined $type)
			{
				push @types,$type;
			}

			my @tmp_arr = (\@types,\@disks,1);
			$device_status{$device_ip} = \@tmp_arr;
		}
		else
		{
			if(defined $disk)
			{
				push @{$device_status{$device_ip}->[1]},$disk;
			}
			elsif(defined $type)
			{
				push @{$device_status{$device_ip}->[0]},$type;
			}
		}
	}
	$sqr_select->finish();

	foreach my $device_ip(keys %device_errlog)
	{
		my $is_exist = 0;
		$sqr_select = $dbh->prepare("select mobilenum from member where uid IN(select memberid from snmp_alert_user a left join snmp_alert b on a.snmp_alert_id=b.seq where (b.groupid=(select groupid from servers where device_ip='$device_ip') or b.groupid=0) and b.enable= 1) and mobilenum != ''");
		$sqr_select->execute();
		while(my $ref_select = $sqr_select->fetchrow_hashref())
		{
			my $mobilenum = $ref_select->{"mobilenum"};
			unless(defined $mobilenum)
			{
				next;
			}

			$is_exist = 1;

			unless(exists $mobile_errlog{$mobilenum})
			{
				my @tmp_device = ($device_ip);
				my @tmp_arr = (\@tmp_device,undef);

				$mobile_errlog{$mobilenum} = \@tmp_arr;
				$mobile_errlog{$mobilenum}->[1] = $device_errlog{$device_ip};
			}
			else
			{
				push @{$mobile_errlog{$mobilenum}->[0]}, $device_ip;
				$mobile_errlog{$mobilenum}->[1] .= $device_errlog{$device_ip};
			}
		}
		$sqr_select->finish();

		if($is_exist == 0)
		{
			$device_status{$device_ip}->[2] = 2;
		}
	}

	foreach my $mobile(keys %mobile_errlog)
	{
		my $status = &send_msg($mobile,$mobile_errlog{$mobile}->[1]);

		if($status == 2)
		{
			foreach my $device_ip(@{$mobile_errlog{$mobile}->[0]})
			{
				$device_status{$device_ip}->[2] = $status;
			}
		}
	}

	foreach my $device_ip(keys %device_status)
	{
		my @types = @{$device_status{$device_ip}->[0]};
		my @disks = @{$device_status{$device_ip}->[1]};
		my $status = $device_status{$device_ip}->[2];

		my $sqr_update = $dbh->prepare("update snmp_status_warning_log set sms_status = $status where device_ip = '$device_ip' and sms_status = -1");
		$sqr_update->execute();
		$sqr_update->finish();

		if($status == 1)
		{
			if(scalar @types == 0 && scalar @disks == 0)
			{
				my $sqr_update = $dbh->prepare("update snmp_status set sms_last_sendtime = '$time_now_str' where device_ip = '$device_ip'");
				$sqr_update->execute();
				$sqr_update->finish();
			}
			else
			{
				foreach my $type(@types)
				{
					my $sqr_update = $dbh->prepare("update snmp_status set sms_last_sendtime = '$time_now_str' where device_ip = '$device_ip' and type = '$type'");
					$sqr_update->execute();
					$sqr_update->finish();
				}

				foreach my $disk(@disks)
				{
					my $sqr_update = $dbh->prepare("update snmp_status set sms_last_sendtime = '$time_now_str' where device_ip = '$device_ip' and type = 'disk' and disk = '$disk'");
					$sqr_update->execute();
					$sqr_update->finish();
				}
			}
		}
	}
}

sub send_mail
{
	my($mailto,$subject,$msg,$mailserver,$mailfrom,$mailpwd) = @_;

	my $sender = new Mail::Sender;
#   $subject = encode_mimewords($subject,'Charset','UTF-8');
	$subject =  encode("gb2312", decode("utf8", $subject));           #freesvr 专用
#   $msg = encode_mimewords($msg,'Charset','gb2312');
		$msg =  encode("gb2312", decode("utf8", $msg));              #freesvr 专用

		if ($sender->MailMsg({
					smtp => $mailserver,
					from => $mailfrom,
					to => $mailto,
					subject => $subject,
					msg => $msg,
					auth => 'LOGIN',
					authid => $mailfrom,
					authpwd => $mailpwd,
#               encoding => 'gb2312',
					})<0){
			return 2;
		}
		else
		{
			return 1;
		}
}

sub send_msg
{
	my ($mobile_tel,$msg) = @_;
	my $sp_no = "955589903";
	my $mobile_type = "1";
	$msg =  encode("gb2312", decode("utf8", $msg));
	$msg = uri_escape($msg); 

	my $url = "http://192.168.4.71:8080/smsServer/service.action?branch_no=10&password=010&depart_no=10001&message_type=1&batch_no=4324&priority=1&sp_no=$sp_no&mobile_type=$mobile_type&mobile_tel=$mobile_tel&message=$msg";

	$url = URI::URL->new($url); 

	if(system("wget -t 1 -T 3 '$url' -O - 1>/dev/null 2>&1") == 0)
	{
		return 1;
	}   
	else
	{
		return 2;
	}   
}

sub get_local_mysql_config
{
    my $tmp_mysql_user = "root";
    my $tmp_mysql_passwd = "";
    open(my $fd_fr, "</opt/freesvr/audit/etc/perl.cnf");
    while(my $line = <$fd_fr>)
    {
        $line =~ s/\s//g;
        my($name, $val) = split /:/, $line;
        if($name eq "mysql_user")
        {
            $tmp_mysql_user = $val;
        }
        elsif($name eq "mysql_passwd")
        {
            $tmp_mysql_passwd = $val;
        }
    }

    my $cipher = Crypt::CBC->new( -key => 'freesvr', -cipher => 'Blowfish', -iv => 'freesvr1', -header => 'none');
    $tmp_mysql_passwd = decode_base64($tmp_mysql_passwd);
    $tmp_mysql_passwd  = $cipher->decrypt($tmp_mysql_passwd);
    close $fd_fr;
    return ($tmp_mysql_user, $tmp_mysql_passwd);
}
