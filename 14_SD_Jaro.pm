#######################################################################################################################################################
# $Id: 14_SD_JARO.pm 32 2019-02-05 12:00:00 v3.3.3-dev_05.12. $
#   
# The file is part of the SIGNALduino project.
# The purpose of this module is support for JAROLIFT devices.
# It is an attempt to implement the project "Bastelbudenbuben" in Perl without personal testing.
# For the sake of fairness to the manufacturer, I advise every user to perform extensions at their own risk.
# The user must purchase the keys themselves.
#
# KeeLoq is a registered trademark of Microchip Technology Inc.
#
#######################################################################################################################################################
# !!! ToDo´s !!!
#		- UI komplett durchtesten
#		- SD_JARO_Set -> lt. https://wiki.fhem.de/wiki/DevelopmentModuleIntro -> unknown argument [Parameter] choose one of [Liste möglicher Optionen]
#		- Statuswechsel nach 60-90sek. automatisch nach verfahren?
#######################################################################################################################################################

package main;

# Laden evtl. abhängiger Perl- bzw. FHEM-Hilfsmodule
use strict;
use warnings;
use POSIX;
use List::Util qw(any);				# for any function
use Data::Dumper qw (Dumper);

my %jaro_buttons = (
	# keys(model) => values
	"up"				=>	"1000",
	"stop"			=>	"0100",
	"down"			=>	"0010",
	"learn"			=>	"0001",
	"shade"			=>	"1010",
	"updown"		=>	"0101"
);

my %jaro_channels = (
	# keys(model) => values
	1			=>	"0000",
	2			=>	"0001",
	3			=>	"0010",
	4			=>	"0011",
	5			=>	"0100",
	6			=>	"0101",
	7			=>	"0110",
	8			=>	"0111",
	9			=>	"1000",
	10		=>	"1001",
	11		=>	"1010",
	12		=>	"1011",
	13		=>	"1100",
	14		=>	"1101",
	15		=>	"1110",
	16		=>	"1111"
);

my %roto_buttons = (
	# keys(model) => values
	"up"		=>	"0100",
	"down"	=>	"1001",
	"stop"	=>	"0001"
);

my @jaro_commands_standard = ("up","stop","down","shade","learn","updown");
my @jaro_addGroups;

my $KeeLoq_NLF;

#####################################
sub SD_JARO_Initialize() {
  my ($hash) = @_;
  $hash->{Match}				= "^P(?:87|88)#.*";
	$hash->{DefFn}				= "SD_JARO_Define";
  $hash->{UndefFn}			= "SD_JARO_Undef";
  $hash->{AttrFn}				= "SD_JARO_Attr";
  $hash->{SetFn}				= "SD_JARO_Set";
  $hash->{ParseFn}			= "SD_JARO_Parse";
  $hash->{AttrList}			= "IODev MasterMSB MasterLSB KeeLoq_NLF stateFormat Channels:0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16 ShowShade:0,1 ShowIcons:0,1 ShowLearn:0,1 ".
													"UI:aus,Einzeilig,Mehrzeilig ChannelFixed:ch1,ch2,ch3,ch4,ch5,ch6,ch7,ch8,ch9,ch10,ch11,ch12,ch13,ch14,ch15,ch16 ChannelNames Repeats:1,2,3,4,5,6,7,8,9 ".
													"addGroups Serial_send ".$readingFnAttributes;
  $hash->{FW_summaryFn}	= "SD_JARO_summaryFn";          # displays html instead of status icon in fhemweb room-view
}

#####################################
sub SD_JARO_Define() {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  # Argument            				   0	     1       2      3          4
	return " wrong syntax: define <name> SD_JARO <Serial> <Typ> <optional IODEV> " if(int(@a) < 4 || int(@a) > 5);
	return "ERROR: your <Typ> is wrong! Please use JaroLift or Roto." if not ($a[3] eq "JaroLift" || $a[3] eq "Roto");
	
	if ($a[3] eq "JaroLift" && not ($a[2] =~ /^[0-9]+$/s && ($a[2] <= 16777215 || $a[2] >= 0 ))) {
		return "ERROR: your JaroLift <Serial> is wrong! Please use only decimal numbres."					# JaroLift max
	}

	if ($a[3] eq "Roto" && not ($a[2] =~ /^[0-9]+$/s && ($a[2] <= 268435455 || $a[2] >= 0 ))) {
		return "ERROR: your Roto <Serial> is wrong! Please use only decimal numbres.";						# Roto max
	}

  $hash->{STATE} = "Defined";
  my $name = $hash->{NAME};
	my $typ = $a[3] if($a[3]);
	my $iodevice = $a[4] if($a[4]);

	$modules{SD_JARO}{defptr}{$hash->{DEF}} = $hash;
	my $ioname = $modules{SD_JARO}{defptr}{ioname} if (exists $modules{SD_JARO}{defptr}{ioname} && not $iodevice);
	$iodevice = $ioname if not $iodevice;

	AssignIoPort($hash, $iodevice);
	return undef;
}

#####################################
sub SD_JARO_Attr(@) {
	my ($cmd, $name, $attrName, $attrValue) = @_;
	my $hash = $defs{$name};
	my $addGroups = AttrVal($name, "addGroups", "");
	my $MasterMSB = AttrVal($name, "MasterMSB", "");
	my $MasterLSB = AttrVal($name, "MasterLSB", "");
	my $Serial_send = AttrVal($name, "Serial_send", "");
	my $typ = ReadingsVal($name, "typ", "");
	
	if ($init_done == 1) {
		if ($cmd eq "set") {
			if (($attrName eq "MasterLSB" && $MasterMSB ne "") || ($attrName eq "MasterMSB" && $MasterLSB ne "")) {
					if ($Serial_send eq "") {
						readingsSingleUpdate($hash, "user_info", "messages can be received!", 1);
						readingsSingleUpdate($hash, "user_modus", "limited_functions", 1);
					} else {
						readingsSingleUpdate($hash, "user_info", "messages can be received and send!", 1);
						readingsSingleUpdate($hash, "user_modus", "all_functions", 1);
					}
			}
			
			if ($typ eq "JaroLift") {
				if ($attrName eq "addGroups") {
					return "ERROR: wrong $attrName syntax!\nexample: South:1,3,5 North:2,4" if not ($attrValue =~ /^[a-zA-Z0-9_\-äÄüÜöÖ:,\s]+[^,.:\D]$/s);
					SD_JARO_translate($attrValue);
					$attr{$name}{addGroups} = $attrValue;
				}
				
				if ($attrName eq "ChannelNames") {
					return "ERROR: wrong $attrName syntax! [only a-z | umlauts | numbers | , | _ | - | ]\nexample: South,North" if not ($attrValue =~ /\A[a-zA-Z\d,_-äÄüÜöÖ\s]+\Z/s);
					SD_JARO_translate($attrValue);
					$attr{$name}{ChannelNames} = $attrValue;
				}
				
				if ($attrName eq "Channels" && $attrValue == 0 && $addGroups eq "") {
					return "ERROR: you can use Channels = $attrValue only with defined attribut addGroups!";
				}
			}

			if ($typ eq "Roto") {
				if ($attrName eq "addGroups" || $attrName eq "Channels" || $attrName eq "ChannelNames" || $attrName eq "ChannelFixed" || $attrName eq "ShowIcons" || $attrName eq "ShowLearn" || $attrName eq "ShowShade") {
					return "ERROR: the attributes $attrName are not support on typ $typ";
				}
				
				if ($attrName eq "UI" && $attrValue ne "aus") {
					return "ERROR: the attributes $attrName with the value $attrValue are not support at this moment on typ $typ";
				}
			}
			
			if ($attrName eq "MasterLSB" || $attrName eq "MasterMSB" || $attrName eq "KeeLoq_NLF") {
				return "ERROR: wrong $attrName key format! [only in hex format | example: 0x23ac34de]" if not ($attrValue =~ /^0x[a-fA-F0-9]{8}+$/s);
			}
			
			if ($attrName eq "Serial_send") {
				return "ERROR: wrong JaroLift $attrName! allowed from 0 to 16777215." if ($typ eq "JaroLift" && not ($attrValue =~ /^[0-9]+$/s && $attrValue <= 16777215 && $attrValue >= 0 ));
				return "ERROR: wrong Roto $attrName! allowed from 0 to 268435455." if ($typ eq "Roto" && not ($attrValue =~ /^[0-9]+$/s && $attrValue <= 268435455 && $attrValue >= 0 ));
				
				if (ReadingsVal($name, "serial_receive", 0) eq $attrValue) {
					return "ERROR: your value must be different from the reading serial_receive!";
				}
				
				if ($MasterMSB ne "" && $MasterLSB ne "" && $attrValue ne "") {
					readingsSingleUpdate($hash, "user_info", "messages can be received and send!", 1);
					readingsSingleUpdate($hash, "user_modus", "all_functions", 1);
				}
			}

			if ($attrName eq "IODev") {
			### Check, eingegebener Sender als Device definiert?
				my @sender = ();
				foreach my $d (sort keys %defs) {
					if(defined($defs{$d}) && $defs{$d}{TYPE} eq "SIGNALduino" && $defs{$d}{DeviceName} ne "none" && $defs{$d}{DevState} eq "initialized") {
						push(@sender,$d);
					}
				}
				return "ERROR: Your $attrName is wrong!\n\nDevices to use: \n- ".join("\n- ",@sender) if (not grep /^$attrValue$/, @sender);
			}
		}
		
		if ($cmd eq "del") {
			if ($attrName eq "MasterLSB" || $attrName eq "MasterMSB") {
				readingsSingleUpdate($hash, "user_info", "Please input MasterMSB and MasterLSB Key!", 1);
				readingsSingleUpdate($hash, "user_modus", "only_limited_received", 1);
			}

			if ($attrName eq "Serial_send") {
				readingsSingleUpdate($hash, "user_info", "messages can be received!", 1);
				readingsSingleUpdate($hash, "user_modus", "limited_functions", 1);
			}
		}

		Log3 $name, 3, "SD_JARO: $cmd attr $attrName to $attrValue" if (defined $attrValue);
		Log3 $name, 3, "SD_JARO: $cmd attr $attrName" if (not defined $attrValue);
	}

	return undef;
}

#####################################
sub SD_JARO_Set($$$@) {
	my ( $hash, $name, @a ) = @_;
	my $ioname = $hash->{IODev}{NAME};
	my $addGroups = AttrVal($name, "addGroups", "");
	my $Channels = AttrVal($name, "Channels", 1);
	my $ChannelFixed = AttrVal($name, "ChannelFixed", "none");
	my $MasterMSB = AttrVal($name, "MasterMSB", "");
	my $MasterLSB = AttrVal($name, "MasterLSB", "");
	$KeeLoq_NLF = AttrVal($name, "KeeLoq_NLF", "");
	my $Serial_send = AttrVal($name, "Serial_send", "");
	my $Repeats = AttrVal($name, "Repeats", "3");
	my $ret;

	my $cmd = $a[0];
	my $cmd2 = $a[1];
	my $channel;				# JaroLift only
	my $bit0to7;
	my $bit64to71;			# JaroLift only
	my $DeviceKey;			# needed for KeeLoq
	my $buttonbits;			#	Buttonbits
	my $button;					#	Buttontext
	
	### Einzeilig mit Auswahlfeld ###
	if ($a[0] eq "OptionValue") {
		$a[0] = $hash->{READINGS}{DDSelected}{VAL};
	}

	### only with Serial_send create setlist for user
	if ($Serial_send ne "" && $MasterMSB ne "" && $MasterLSB ne "" && $KeeLoq_NLF ne "") {
		### all channels without ChannelFixed ###
		if ($ChannelFixed eq "none") {
			foreach my $rownr (1..$Channels) {
				$ret.=" ch".$rownr.":up,stop,down,shade,learn,updown";
			}

			## for addGroups if no Channels
			if ($addGroups ne "") {
				@jaro_addGroups = split / /, $addGroups;
				foreach (@jaro_addGroups){
					$_ =~ s/:\d.*//g;
					$ret.=" $_:up,stop,down";
				}
			}
		} else {
			$ret.=" $ChannelFixed:up,stop,down,shade,learn,updown";
		}

		### only all options without ChannelFixed ###
		if ($ChannelFixed eq "none") {
			my $ret_part2;
			foreach my $rownr (1..$Channels) {
				$ret_part2.= "$rownr,";
			}

			## for addGroups if no Channels
			if ($addGroups ne "") {
				foreach (@jaro_addGroups){
					$_ =~ s/:\d.*//g;
					$ret_part2.= "$_,";
				}
			}

			#Log3 $name, 4, "$ioname: SD_JARO_Set - returnlist part2  = $ret_part2" if ($cmd ne "?");

			$ret_part2 = substr($ret_part2,0,-1);		# cut last ,
			$ret.=" up:multiple,".$ret_part2;
			$ret.=" stop:multiple,".$ret_part2;
			$ret.=" down:multiple,".$ret_part2;
			$ret.=" shade:multiple,".$ret_part2;
			$ret.=" learn:multiple,".$ret_part2;
			$ret.=" updown:multiple,".$ret_part2;
		}

		#Log3 $name, 4, "$ioname: SD_JARO_Set - returnlist finish = $ret" if ($cmd ne "?");
	}
	
  return $ret if ( $a[0] eq "?");
	return "ERROR: no set value specified!" if(int(@a) <= 1);
	return "ERROR: too much set value specified!" if(int(@a) > 2);

	return "ERROR: no value, set Attributes MasterMSB please!" if ($MasterMSB eq "");
	return "ERROR: no value, set Attributes MasterLSB please!" if ($MasterLSB eq "");
	return "ERROR: no value, set Attributes KeeLoq_NLF please!" if ($KeeLoq_NLF eq "");
	return "ERROR: no value, set Attributes Serial_send please!" if($Serial_send eq "");

	return "ERROR: your command $cmd is not support! (no decimal)" if ($ret =~ /^\d/);
	return "ERROR: your command $cmd is not support! (not in list)" if ($ret !~ /$cmd/ && $addGroups eq "");
	return "ERROR: your command $cmd2 is not support! (not in list)" if ($ret !~ /$cmd2/ && $addGroups ne "");

	if ($cmd ne "?") {
		Log3 $name, 4, "######## DEBUG SET - START ########";
		Log3 $name, 4, "$ioname: SD_JARO_Set - cmd=$cmd cmd2=$cmd2" if (defined $cmd2);
		
		my @channels;
		### ONE channel set | solo -> ch1 up
		if ($cmd =~ /^ch\d+$/) {
			$channel = substr($cmd, 2, (length $cmd)-2);
			return "ERROR: channel $channel is not support! (check1 failed)" if($channel < 1 || $channel > 16);		# check channel support or not

			push(@channels,$channel);
			$button = $cmd2;
			$buttonbits = $jaro_buttons{$cmd2};
			Log3 $name, 4, "$ioname: SD_JARO_Set - v1 -> one channel via setlist | button=$button buttonbits=$buttonbits channel=$channel";
		### MULTI channel set | multi -> up 1,3
		} elsif ("@jaro_commands_standard" =~ /$cmd/) {
			$button = $cmd;
			$buttonbits = $jaro_buttons{$a[0]};

			if ( grep( /[$cmd2]:/, $addGroups ) ) {
				Log3 $name, 4, "$ioname: SD_JARO_Set - v2 -> group on setlist (not modified) | button=$button buttonbits=$buttonbits channel=$cmd2";
				my @channel_from_addGroups = split(" ", $addGroups);
				foreach my $found (@channel_from_addGroups){
					if ($found =~ /^$cmd2:/) {
						Log3 $name, 4, "$ioname: SD_JARO_Set - v2 -> group on setlist (not modified) | found $cmd in $found";
						$found =~ s/$cmd2\://g;
						@channels = split(",", $found);
						$channel = $channels[0];
						last;
					}
				}
				Log3 $name, 4, "$ioname: SD_JARO_Set - v2 -> group on setlist (modified)     | button=$button buttonbits=$buttonbits channel=$channel";
			} else {
				@channels = split /,/, $cmd2;			
				$channel = $channels[0];
				Log3 $name, 4, "$ioname: SD_JARO_Set - v2 -> multi channel via setlist | button=$button buttonbits=$buttonbits channel=$channel";
			}

			### check channel support or not
			foreach (@channels){
				return "ERROR: channel $_ is not support! (check2 failed)" if($_ < 1 || $_ > 16);
			}
		### addgroup set | multi -> kitchen 1,3 via setlist or UI
		} else {
			$button = $cmd2;
			$buttonbits = $jaro_buttons{$cmd2};

			@channels = split /,/, $cmd;
			$channel = $channels[0];

			## cmd=Bad cmd2=up
			if ( grep( /[$channel]:/, $addGroups ) ) {
				Log3 $name, 4, "$ioname: SD_JARO_Set - v3 -> group on setlist (not modified) | button=$button buttonbits=$buttonbits channel=$channel";
				my @channel_from_addGroups = split(" ", $addGroups);
				foreach my $found (@channel_from_addGroups){
					if ($found =~ /^$cmd:/) {
						Log3 $name, 4, "$ioname: SD_JARO_Set - v3 -> group on setlist (not modified) | found $cmd in $found";
						$found =~ s/$cmd\://g;
						@channels = split(",", $found);
						$channel = $channels[0];
						last;
					}
				} 
				Log3 $name, 4, "$ioname: SD_JARO_Set - v3 -> group on setlist (modified)     | button=$button buttonbits=$buttonbits channel=$channel";
			## cmd=2,4 cmd2=stop
			} else {
				Log3 $name, 4, "$ioname: SD_JARO_Set - v4 -> group on UI icon | button=$button buttonbits=$buttonbits channel=$channel";
			}
		}

		return "ERROR: No channel given!" if (scalar @channels == 0);

		### create channelpart1
		foreach my $nr (1..8) {
			if ( grep( /^$nr$/, @channels ) ) {
				$bit0to7.="1";
			} else {
				$bit0to7.="0";
			}
		}

		### create channelpart2
		foreach my $nr (9..16) {
			if ( grep( /^$nr$/, @channels ) ) {
				$bit64to71.="1";
			} else {
				$bit64to71.="0";
			}
		}

		$bit0to7 = reverse $bit0to7;
		$bit64to71 = reverse $bit64to71;		# JaroLift only

		### DeviceKey (die ersten Stellen aus der Vorage, der Rest vom Sendenen Kanal)
		$Serial_send = sprintf ("%24b", $Serial_send);																					# verified
		
		$DeviceKey = $Serial_send.$jaro_channels{$channel};																			# verified
		$DeviceKey = oct("0b".$DeviceKey);																											# verified

		######## KEYGEN #############
		my $counter_send = ReadingsVal($name, "counter_send", 0);
		$counter_send++;
		my $keylow = $DeviceKey | 0x20000000;
		my $device_key_lsb = SD_JARO_decrypt($keylow, hex($MasterMSB), hex($MasterLSB),$name);	# verified
		$keylow = $DeviceKey | 0x60000000;
		my $device_key_msb = SD_JARO_decrypt($keylow, hex($MasterMSB), hex($MasterLSB),$name);	# verified

		### KEELOQ
		my $disc = $bit0to7."0000".$jaro_channels{$channel};	# Hopcode													# verified
	
		my $result = (SD_JARO_bin2dec($disc) << 16) | $counter_send;														# verified
		my $encoded = SD_JARO_encrypt($result, $device_key_msb, $device_key_lsb,$name);					# verified

		### Zusammenführen
		my $bits = reverse (sprintf("%032b", $encoded)).reverse($jaro_channels{$channel}).reverse($Serial_send).reverse($buttonbits).reverse($bit64to71);
		my $msg = "P87#$bits"."P#R".$Repeats;

		Log3 $name, 5, "$ioname: SD_JARO_Set - Channel                   = $channel";
		Log3 $name, 5, "$ioname: SD_JARO_Set - channelpart1 (Group 0-7)  = $bit0to7";
		Log3 $name, 5, "$ioname: SD_JARO_Set - channelpart2 (Group 8-15) = $bit64to71";
		Log3 $name, 5, "$ioname: SD_JARO_Set - Button                    = $button";
		Log3 $name, 5, "$ioname: SD_JARO_Set - Button_bits               = $buttonbits";
		Log3 $name, 5, "$ioname: SD_JARO_Set - DeviceKey                 = $DeviceKey";
		Log3 $name, 5, "$ioname: SD_JARO_Set - Device_key_lsb            = $device_key_lsb";
		Log3 $name, 5, "$ioname: SD_JARO_Set - Device_key_msb            = $device_key_msb";
		Log3 $name, 5, "$ioname: SD_JARO_Set - disc                      = $disc";
		Log3 $name, 5, "$ioname: SD_JARO_Set - result (decode)           = $result";
		Log3 $name, 5, "$ioname: SD_JARO_Set - Counter                   = $counter_send";
		Log3 $name, 5, "$ioname: SD_JARO_Set - encoded (encrypt)         = ".sprintf("%032b", $encoded)."\n";

		my $binsplit = SD_JARO_binsplit_JaroLift($bits);

		Log3 $name, 5, "$ioname: SD_JARO_Set                                                   encoded     <- | ->     decrypts";
		Log3 $name, 5, "$ioname: SD_JARO_Set                               Grp 0-7 |digitS/N|      counter    | ch |          serial        | bt |Grp 8-15";
		Log3 $name, 5, "$ioname: SD_JARO_Set - bits (send split)         = $binsplit";
		Log3 $name, 5, "$ioname: SD_JARO_Set - bits (send)               = $bits";
		Log3 $name, 4, "$ioname: SD_JARO_Set - sendMSG                   = $msg";
		Log3 $name, 4, "######## DEBUG SET - END ########";

		IOWrite($hash, 'sendMsg', $msg);
		Log3 $name, 3, "$ioname: $name set $cmd $cmd2";

		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "button", $button, 1);
		readingsBulkUpdate($hash, "channel", $channel, 1);
		readingsBulkUpdate($hash, "counter_send", $counter_send, 1);
		readingsBulkUpdate($hash, "state", "send $button", 1);

		my $group_value;
		foreach (@channels) {
			readingsBulkUpdate($hash, "LastAction_Channel_".sprintf ("%02s",$_), $button);
			$group_value.= $_.",";
		}

		$group_value = substr($group_value,0,length($group_value)-1);
		$group_value = "no" if (scalar @channels == 1);

		readingsBulkUpdate($hash, "channel_control", $group_value);
		readingsEndUpdate($hash, 1); 		# Notify is done by Dispatch
		#return $cmd." ".$cmd2;		# to display cmd is running	
	}

	#return $ret;
}

###################################
sub SD_JARO_bin2dec($) {
	my $bin = shift;
	my $dec = oct("0b" . $bin);
	return $dec;
}

###################################
sub SD_JARO_dec2bin($) {
	my $bin = unpack("B32", pack("N", shift));
	return $bin;
}

###################################
sub SD_JARO_translate($) {
	my $text = shift;
	my %translate = ("ä" => "&auml;", "Ä" => "&Auml;", "ü" => "&uuml;", "Ü" => "&Uuml;", "ö" => "&ouml;", "Ö" => "&Ouml;", "ß" => "&szlig;" );
	my $keys = join ("|", keys(%translate));
	$text =~ s/($keys)/$translate{$1}/g;
	return $text;
}

###################################
sub SD_JARO_encrypt($$$$){
	my $x = shift;
	my $_keyHigh = shift;
	my $_keyLow = shift;
	my $name = shift;
	$KeeLoq_NLF = AttrVal($name, "KeeLoq_NLF", "");
	$KeeLoq_NLF = oct($KeeLoq_NLF);
	
	my $r = 0;
	my $index = 0;
	my $keyBitVal = 0;
	my $bitVal = 0;

	while ($r < 528){
		my $keyBitNo = $r & 63;
		if ($keyBitNo < 32){
			$keyBitVal = SD_JARO_bitRead($_keyLow, $keyBitNo);
		} else {
			$keyBitVal = SD_JARO_bitRead($_keyHigh, $keyBitNo - 32);
		}		
		$index = 1 * SD_JARO_bitRead($x,1) + 2 * SD_JARO_bitRead($x,9) + 4 * SD_JARO_bitRead($x,20) + 8 * SD_JARO_bitRead($x,26) + 16 * SD_JARO_bitRead($x,31);
		$bitVal = SD_JARO_bitRead($x,0) ^ SD_JARO_bitRead($x, 16) ^ SD_JARO_bitRead($KeeLoq_NLF,$index) ^ $keyBitVal;
		$x = ($x >> 1 & 0xffffffff) ^ $bitVal <<31;
		$r = $r + 1;
	}
	return $x;
}

###################################
sub SD_JARO_decrypt($$$$){
	my $x = shift;
	my $_keyHigh = shift;
	my $_keyLow = shift;
	my $name = shift;
	$KeeLoq_NLF = AttrVal($name, "KeeLoq_NLF", "");
	$KeeLoq_NLF = oct($KeeLoq_NLF);
	
	my $r = 0;
	my $index = 0;
	my $keyBitVal = 0;
	my $bitVal = 0;

	while ($r < 528){
		my $keyBitNo = (15-$r) & 63;

		if ($keyBitNo < 32){
			$keyBitVal = SD_JARO_bitRead($_keyLow, $keyBitNo);
		} else {
			$keyBitVal = SD_JARO_bitRead($_keyHigh, $keyBitNo -32);
		}

		$index = 1 * SD_JARO_bitRead($x,0) + 2 * SD_JARO_bitRead($x,8) + 4 * SD_JARO_bitRead($x,19) + 8 * SD_JARO_bitRead($x,25) + 16 * SD_JARO_bitRead($x,30);
		$bitVal = SD_JARO_bitRead($x,31) ^ SD_JARO_bitRead($x, 15) ^ SD_JARO_bitRead($KeeLoq_NLF,$index) ^ $keyBitVal;
		$x = ($x << 1 & 0xffffffff) ^ $bitVal;
		#if ($r == 5){
		#exit 1;
		#}
		#$x = ctypes.c_ulong((x>>1) ^ bitVal<<31).value
		$r = $r + 1;
	}
	return $x;
}

###################################
sub SD_JARO_bitRead($$) {
	my $wert = shift;
	my $bit = shift;

	return ($wert >> $bit) & 0x01;
}

###################################
sub SD_JARO_Parse($$) {
	my ($iohash, $msg) = @_;
	my $ioname = $iohash->{NAME};
	my ($protocol,$rawData) = split("#",$msg);
	$protocol=~ s/^P(\d+)/$1/; 										# extract protocol
	my $hlen = length($rawData);
	my $blen = $hlen * 4;
	my $bitData = unpack("B$blen", pack("H$hlen", $rawData));
	
	my $encrypted = 1;
	my $info = "Please input KeeLoq_NLF, MasterMSB and MasterLSB Key!";
	my $state;

	## JAROLIFT ##
	## CD287247200065F100 ##
	## 110011010010100001110010010001110010000000000000011001011111000100000000 ##
	#
	# 8 bit grouping channel 0-7
	# 8 bit two last digits of S/N transmitted
	# 16 bit countervalue
	####################### 32bit encrypted
	# 28 bit serial
	# 4 bit button
	# 8 bit for grouping 8-16
	####################### 40bit

  # Kanal  S/N           DiscGroup_8-16             DiscGroup_1-8     SN(last two digits)
  # 0       0            0000 0000                   0000 0001           0000 0000
  # 1       1            0000 0000                   0000 0010           0000 0001
  # 2       2            0000 0000                   0000 0100           0000 0010
  # 3       3            0000 0000                   0000 1000           0000 0011
  # 4       4            0000 0000                   0001 0000           0000 0100
  # 5       5            0000 0000                   0010 0000           0000 0101
  # 6       6            0000 0000                   0100 0000           0000 0110
  # 7       7            0000 0000                   1000 0000           0000 0111
  # 8       8            0000 0001                   0000 0000           0000 0111
  # 9       9            0000 0010                   0000 0000           0000 0111
  # 10      10           0000 0100                   0000 0000           0000 0111
  # 11      11           0000 1000                   0000 0000           0000 0111
  # 12      12           0001 0000                   0000 0000           0000 0111
  # 13      13           0010 0000                   0000 0000           0000 0111
  # 14      14           0100 0000                   0000 0000           0000 0111
  # 15      15           1000 0000                   0000 0000           0000 0111
	
	# button = 0x0; // 1000=0x8 up, 0100=0x4 stop, 0010=0x2 down, 0001=0x1 learning
	# !!! There are supposedly 2 versions of the protocol? old and new !!!
	
	# http://www.bastelbudenbuben.de/2017/04/25/protokollanalyse-von-jarolift-tdef-motoren/
	# https://github.com/madmartin/Jarolift_MQTT/wiki/About-Serials
	
	################################################################################################
	
	## Roto ##
	## D13E68A890EAFEF20 ##
	## 11010001001111100110100010101000100100001110101011111110111100100000 ##
	#
	# 16 bit Sync Counter
	# 12 bit Discrimination
	# 4 bit Button
	####################### 32bit encrypted
	# 28 bit serial
	# 4 bit button
	# 1 bit VLOW: Voltage LOW indicator
	# 1 bit RPT: Repeat indicator
	# 2 bit Padding
	####################### 34bit

	my $serialWithoutCh;
	my $typ;
	
	if ($hlen == 17) {
		$typ = "Roto";
		$serialWithoutCh = reverse (substr ($bitData , 32 , 28));						# 28bit serial
	} elsif ($hlen == 18) {
		$typ = "JaroLift";	
		$serialWithoutCh = reverse (substr ($bitData , 36 , 24));						# 24bit serial without last 4 bit
	}

	$serialWithoutCh = oct( "0b$serialWithoutCh" );
	my $devicedef = $serialWithoutCh;																			### Serial without last nibble, fix at device at every channel
	$modules{SD_JARO}{defptr}{ioname} = $ioname;
  my $def = $modules{SD_JARO}{defptr}{$devicedef." ".$typ};
  
	if(!$def) {
    Log3 $iohash, 2, "SD_JARO_Parse Unknown device $typ with Code $devicedef detected, please define (rawdate=$rawData)";
    return "UNDEFINED SD_JARO_".$devicedef." SD_JARO ".$devicedef." ".$typ;
  }

	my $hash = $def;
	my $name = $hash->{NAME};
	my $MasterMSB = AttrVal($name, "MasterMSB", "");
	my $MasterLSB = AttrVal($name, "MasterLSB", "");
	$KeeLoq_NLF = AttrVal($name, "KeeLoq_NLF", "");
	my $UI = AttrVal($name, "UI", "Mehrzeilig");
	
	$hash->{lastMSG} = $rawData;
	$hash->{bitMSG} = $bitData;
	
	if ($MasterMSB ne "" && $MasterLSB ne "" && $KeeLoq_NLF ne "") {
		$encrypted = 0;
		$info = "none";
	}

	Log3 $name, 4, "$ioname: SD_JARO_Parse device $typ with rawData=$rawData, hlen=$hlen";

	### JaroLift only ###
	my $bit0to7;
	my $bit8to15;
	my $bit64to71;
	my $group_value;
	my $group_value8_15;
	my $channel;
	my $channel_bin;

	### Roto only ###
	my $bit0to15;
	my $bit16to27;
	my $bit28to31;
	my $VLOW;
	my $RPT;
	
	## together ##
	my $buttonbits;
	my $binsplit;
	my ($counter) = @_ = ( reverse (substr ($bitData , 16 , 16)) , "encrypted" )[$encrypted];		# without MasterMSB | MasterLSB encrypted
	my ($modus) = @_ = ( "all_functions" , "only_limited" )[$encrypted];												# modus read for user
	
	my $serial = reverse (substr ($bitData , 32 , 28));																					# 28bit serial
	my $button = reverse (substr ($bitData , 60 , 4));																					# 4bit button same JaroLift & Roto
	
	Log3 $name, 5, "######## DEBUG PARSE - START ########";

	if (AttrVal($name, "verbose", "5") == 5) {
		if (defined $hash->{LASTInputDev}) {
			my $LASTInputDev = $hash->{LASTInputDev};
			my $RAWMSG_Internal = $LASTInputDev."_RAWMSG";
			Log3 $name, 5, "$ioname: SD_JARO_Parse - RAWMSG = ".$hash->{$RAWMSG_Internal};
		}
		Log3 $name, 5, "$ioname: SD_JARO_Parse - bitData = $bitData\n";
	}
	
	if($typ eq "JaroLift") {	## for JaroLift Debug
		($bit0to7) = @_ = ( reverse (substr ($bitData , 0 , 8)) , "encrypted" )[$encrypted];			# without MasterMSB | MasterLSB encrypted
		($bit8to15) = @_ = ( reverse (substr ($bitData , 8 , 8)) , "encrypted" )[$encrypted];			# without MasterMSB | MasterLSB encrypted
		$bit64to71 = reverse (substr ($bitData , 64 , 8));
		
		$binsplit = SD_JARO_binsplit_JaroLift($bitData);

		Log3 $name, 5, "$ioname: SD_JARO_Parse - typ = $typ";
		Log3 $name, 5, "$ioname: SD_JARO_Parse                                 encoded     <- | ->     decrypts";
		Log3 $name, 5, "$ioname: SD_JARO_Parse             Grp 0-7 |digitS/N|      counter    | ch |          serial        | bt |Grp 8-15";
		Log3 $name, 5, "$ioname: SD_JARO_Parse - bitData = $binsplit";
		Log3 $name, 5, "$ioname: SD_JARO_Parse - bitData = |->     must be calculated!     <-| ".reverse (substr ($bitData , 32 , 4)) ." ". reverse (substr ($bitData , 36 , 24)) ." ".$button ." ". $bit64to71;
		
		my @groups8_15 = split //, reverse $bit64to71;
		foreach my $i (0..7) {																						# group - ch8-ch15
			if ($groups8_15[$i] eq 1) {
				$group_value.= ($i+9).",";
			}
		}
	
		$group_value8_15 = ($bit64to71 =~ s/(0)/$1/g);										# count 0
		if ($group_value8_15 == 8) {
			$group_value = "< 9";
		}
		$group_value = substr($group_value,0,-1) if ($group_value =~ /,$/);		# cut last ,
		Log3 $name, 5, "$ioname: SD_JARO_Parse - group_value_text 8-15 (1)            = $group_value\n";
	
		($button) = grep { $jaro_buttons{$_} eq $button } keys %jaro_buttons;						# search buttontext --> buttons
		$channel = reverse (substr ($bitData , 32 , 4));
		($channel) = grep { $jaro_channels{$_} eq $channel } keys %jaro_channels;				# search channeltext --> channels
	
		foreach my $keys (keys %jaro_channels) {																				# search channel bits --> channels
			$channel_bin = $jaro_channels{$keys} if ($keys eq $channel);
		}
	
	} elsif ($typ eq "Roto") {	## for Roto Debug
		$VLOW = reverse (substr ($bitData , 64 , 1));
		$RPT = reverse (substr ($bitData , 65 , 1));	
	
		my $binsplit = SD_JARO_binsplit_Roto($bitData);
		
		Log3 $name, 5, "$ioname: SD_JARO_Parse - typ = $typ";
		Log3 $name, 5, "$ioname: SD_JARO_Parse                                encoded     <- | ->     decrypts";
		Log3 $name, 5, "$ioname: SD_JARO_Parse                sync counter |discriminat.| bt |           serial           | bt |V|R|padding";
		Log3 $name, 5, "$ioname: SD_JARO_Parse - bitData = $binsplit";
		Log3 $name, 5, "$ioname: SD_JARO_Parse - bitData = |->     must be calculated!    <-| ". $serial ." ".$button ." ". $VLOW ." ". $RPT."\n";
		
		$buttonbits = $button;
		($button) = grep { $roto_buttons{$_} eq $button } keys %roto_buttons;					# search buttontext --> buttons
		$bit0to15 = reverse (substr ($bitData , 0 , 16));
		$bit16to27 = reverse (substr ($bitData , 16 , 12));
		$bit28to31 = reverse (substr ($bitData , 28 , 4));
	}

	$serial = oct( "0b$serial" );

	my $counter_decr;
	my $channel_decr;
	my $bit0to7_decr;
	my $Decoded;
	
	###### DECODE ######	
	if ($encrypted == 0) {
		Log3 $name, 5, "######## DEBUG PARSE - for LSB & MSB Keys ########";
		
		### Hopcode
		my $Hopcode;
		if ($typ eq "JaroLift") {
			$Hopcode = $bit0to7.$bit8to15.$counter;		
		} elsif ($typ eq "Roto") {
			$Hopcode = $bit0to15.$bit16to27.$bit28to31;		
		}

		$Hopcode = reverse $Hopcode;																									# invert
		Log3 $name, 5, "$ioname: SD_JARO_Parse - input to decode                      = $Hopcode";
		my $Hopcode_decr = SD_JARO_bin2dec($Hopcode);
		Log3 $name, 5, "$ioname: SD_JARO_Parse - HopCode - decrypts                   = $Hopcode_decr";
	
		my $keylow = $serial | 0x20000000;
		Log3 $name, 5, "$ioname: SD_JARO_Parse - decrypts (1)                         = $keylow";
	
		my $rx_device_key_lsb = SD_JARO_decrypt($keylow, hex($MasterMSB), hex($MasterLSB), $name);
		$keylow =  $serial | 0x60000000;
		Log3 $name, 5, "$ioname: SD_JARO_Parse - decrypts (2)                         = $keylow";
	
		my $rx_device_key_msb = SD_JARO_decrypt($keylow, hex($MasterMSB), hex($MasterLSB),$name);
		Log3 $name, 5, "$ioname: SD_JARO_Parse - rx_device_key_lsb                    = $rx_device_key_lsb";
		Log3 $name, 5, "$ioname: SD_JARO_Parse - rx_device_key_msb                    = $rx_device_key_msb";
	
		$Decoded = SD_JARO_decrypt($Hopcode_decr, $rx_device_key_msb, $rx_device_key_lsb,$name);
		Log3 $name, 5, "$ioname: SD_JARO_Parse - Decoded (HopCode,MSB,LSB)            = $Decoded";
		$Decoded = SD_JARO_dec2bin($Decoded);
		Log3 $name, 5, "$ioname: SD_JARO_Parse - Decoded (bin)                        = $Decoded\n";
		
		if ($typ eq "JaroLift") {
			my $Decoded_split;
			for my $i(0..31){
				$Decoded_split.= substr($Decoded,$i,1);
				if (($i+1) % 8 == 0 && $i < 17) {
					$Decoded_split.= " ";
				}
			}
		
			### Disc Group 1-8
			$bit0to7_decr = substr($Decoded, 0, 8);
			$bit0to7 = $bit0to7_decr;
		
			### Counter
			$counter = substr($Decoded, 16, 16);
			$counter_decr = SD_JARO_bin2dec($counter);
	
			my $group_value0_7 = "";
			my @groups0_7 = split //, reverse $bit0to7;
			foreach my $i (0..7) {																																										# group - ch0-ch7
				if ($groups0_7[$i] eq 1) {
					$group_value0_7.= ($i+1).",";
				}
			}
		
			$group_value = "" if($group_value8_15 == 8 && $group_value0_7 ne "");																			# group reset text " < 9"
			$group_value = "16" if($group_value8_15 == 8 && $group_value0_7 eq "");																		# group text "16"
			$group_value0_7 = substr($group_value0_7,0,-1) if ($group_value0_7 =~ /,$/ && $group_value0_7 ne "");			# cut last ,

			$group_value = $group_value0_7.",".$group_value;																													# put together part1 with part2
			$group_value = substr($group_value,1,length($group_value)-1) if ($group_value =~ /^,/);										# cut first ,
			$group_value = substr($group_value,0,-1) if ($group_value =~ /,$/);																				# cut last ,
			$group_value = "no" if ($group_value =~ /^\d+$/);																													# no group, only one channel
	
			### ChannelDecrypted
			$channel_decr = substr($Decoded, 12, 4);
			($channel_decr) = grep { $jaro_channels{$_} eq $channel_decr } keys %jaro_channels;													# search channels
			$bit8to15 = $channel_decr;		

			Log3 $name, 5, "$ioname: SD_JARO_Parse                                          Grp 0-7 |digitS/N|    counter";
			Log3 $name, 5, "$ioname: SD_JARO_Parse - Decoded (bin split)                  = $Decoded_split\n";
			Log3 $name, 5, "######## DEBUG only with LSB & MSB Keys ########";
			Log3 $name, 5, "$ioname: SD_JARO_Parse - channelpart1 (group 0-7)             = $bit0to7";
			Log3 $name, 5, "$ioname: SD_JARO_Parse - group_value_text 0-7  (2)            = $group_value0_7";
			Log3 $name, 5, "$ioname: SD_JARO_Parse - group_value_text 0-15 (3)            = $group_value";
			Log3 $name, 5, "$ioname: SD_JARO_Parse - last_digits (bin)                    = ".substr($Decoded, 8, 8)." (only 4 bits ".substr($Decoded, 12, 4)." = decrypts ch reversed ".reverse (substr ($bitData , 32 , 4)).")";
			Log3 $name, 5, "$ioname: SD_JARO_Parse - last_digits (channel from encoding)  = $bit8to15";
			Log3 $name, 5, "$ioname: SD_JARO_Parse - countervalue (receive)               = $counter_decr\n";
		
			if ($group_value eq "no") {
				$state = "receive $button on single control"
			} elsif ($group_value eq "< 9") {
				$state = "receive $button on single control or group control"
			} else {
				$state = "receive $button group control"
			}
		}
		
		if ($typ eq "Roto") {
			my $Decoded_split;
			for my $i(0..31){
				$Decoded_split.= substr($Decoded,$i,1);
				if ($i == 15 || $i == 27) {
					$Decoded_split.= " ";
				}
			}
			
			my $bit0to15_decr = substr($Decoded, 0, 16);
			my $bit16to27_decr = substr($Decoded, 16, 12);
			my $bit28to31_decr = substr($Decoded, 28, 4);
			$counter_decr = SD_JARO_bin2dec($bit0to15_decr);

			Log3 $name, 5, "$ioname: SD_JARO_Parse                                             sync counter |discriminat.| bt";
			Log3 $name, 5, "$ioname: SD_JARO_Parse - Decoded (bin split)                  = $Decoded_split\n";
			Log3 $name, 5, "######## DEBUG only with LSB & MSB Keys ########";
			Log3 $name, 5, "$ioname: SD_JARO_Parse - sync counter (bits)	          = $bit0to15_decr";
			Log3 $name, 5, "$ioname: SD_JARO_Parse - sync counter (dez) 	          = $counter_decr";
			Log3 $name, 5, "$ioname: SD_JARO_Parse - discrimination                       = $bit16to27";
			Log3 $name, 5, "$ioname: SD_JARO_Parse - button (in encoded part)             = $bit28to31_decr = $buttonbits ???";
			
			$state = "receive $button"
		}
	}
	###### DECODE END ######
	
	Log3 $name, 5, "######## DEBUG without LSB & MSB Keys ########";
	Log3 $name, 5, "$ioname: SD_JARO_Parse - decrypts button                      = $button";

	Log3 $name, 5, "$ioname: SD_JARO_Parse - decrypts ch + serial                 = $serial (at each channel changes)" if ($typ eq "JaroLift");
	Log3 $name, 5, "$ioname: SD_JARO_Parse - decrypts ch + serial (bin)           = ".sprintf("%028b", $serial) if ($typ eq "JaroLift");
	
	Log3 $name, 5, "$ioname: SD_JARO_Parse - decrypts serial                      = $serialWithoutCh (for each channel)";
	Log3 $name, 5, "$ioname: SD_JARO_Parse - decrypts serial (bin)                = ".sprintf("%024b", $serialWithoutCh)." (for each channel)";
	Log3 $name, 5, "$ioname: SD_JARO_Parse - decrypts channel (from serial | bin) = $channel_bin" if (defined $channel_bin);
	Log3 $name, 5, "$ioname: SD_JARO_Parse - decrypts channel (from serial)       = $channel" if (defined $channel);
	
	Log3 $name, 5, "$ioname: SD_JARO_Parse - decrypts channelpart2 (group 8-15)   = $bit64to71" if (defined $bit64to71);
	Log3 $name, 5, "$ioname: SD_JARO_Parse - decrypts channel_control             = $group_value" if (defined $group_value);
	
	Log3 $name, 5, "$ioname: SD_JARO_Parse - decrypts Voltage LOW indicator       = $VLOW" if (defined $VLOW);
	Log3 $name, 5, "$ioname: SD_JARO_Parse - decrypts Repeat indicator            = $RPT" if (defined $RPT);
	
	Log3 $name, 5, "$ioname: SD_JARO_Parse - user_modus                           = $modus";
	Log3 $name, 5, "$ioname: SD_JARO_Parse - user_info                            = $info";
	Log3 $name, 5, "######## DEBUG END ########\n";
	

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "button", $button);
	readingsBulkUpdate($hash, "channel", $channel);
	readingsBulkUpdate($hash, "DDSelected", "ch".$channel) if ($UI eq "Einzeilig");		# to jump receive value in combobox if a other value select before receive
	readingsBulkUpdate($hash, "channel_control", $group_value) if (defined $group_value);
	readingsBulkUpdate($hash, "counter_receive", $counter_decr) if (defined $counter_decr);
	readingsBulkUpdate($hash, "last_digits", $bit8to15) if (defined $bit8to15);
	readingsBulkUpdate($hash, "repeat_indicator", $RPT) if (defined $RPT);
	readingsBulkUpdate($hash, "voltage_LOW_indicator", $VLOW) if (defined $VLOW);
	readingsBulkUpdate($hash, "serial_receive", $serialWithoutCh, 0);
	readingsBulkUpdate($hash, "state", $state);
	readingsBulkUpdate($hash, "typ", $typ, 0);
	readingsBulkUpdate($hash, "user_modus", $modus);
	readingsBulkUpdate($hash, "user_info", $info);
	
	if ($typ eq "JaroLift") {
		readingsBulkUpdate($hash, "LastAction_Channel_".sprintf ("%02s",$channel), $button) if ($group_value eq "no");
		if ($group_value ne "no" && $group_value ne "< 9") {
			my @group_value = split /,/, $group_value;
			foreach (@group_value) {
				readingsBulkUpdate($hash, "LastAction_Channel_".sprintf ("%02s",$_), $button);
			}
		}
	}
	
	readingsEndUpdate($hash, 1); 		# Notify is done by Dispatch
	
	return $name;
}

#####################################
sub SD_JARO_Undef($$) {
	my ($hash, $name) = @_;
	delete($modules{SD_JARO}{defptr}{$hash->{DEF}}) if(defined($hash->{DEF}) && defined($modules{SD_JARO}{defptr}{$hash->{DEF}}));
	delete($modules{SD_JARO}{defptr}{ioname}) if (exists $modules{SD_JARO}{defptr}{ioname});
	return undef;
}

#####################################
sub SD_JARO_binsplit_JaroLift($) {
	my $bits = shift;
	my $binsplit;

	for my $i(0..71){
		$binsplit.= substr($bits,$i,1);
		if (($i+1) % 8 == 0 && $i < 32) {
			$binsplit.= " ";
		}
		if ($i == 35 || $i == 59 || $i == 63) {
			$binsplit.= " ";
		}
	}
	return $binsplit;
}

#####################################
sub SD_JARO_binsplit_Roto($) {
	my $bits = shift;
	my $binsplit;

	for my $i(0..65){
		$binsplit.= substr($bits,$i,1);
		if (($i+1) % 16 == 0 && $i < 27) {
			$binsplit.= " ";
		}
		if ($i == 27 || $i == 31 || $i == 59 || $i == 63 || $i == 64 || $i == 65) {
			$binsplit.= " ";
		}
	}
	return $binsplit;
}

#####################################
sub SD_JARO_summaryFn($$$$) {
	my ($FW_wname, $d, $room, $pageHash) = @_;										# pageHash is set for summaryFn.
	my $hash   = $defs{$d};
	my $name = $hash->{NAME};
	
	return SD_JARO_attr2html($name, $hash);
}

#####################################
# Create HTML-Code
sub SD_JARO_attr2html($@) {
  my ($name, $hash) = @_;
	my $addGroups = AttrVal($name, "addGroups", "");							# groups with channels
	my $Channels = AttrVal($name, "Channels", 1);
	my $ChannelFixed = AttrVal($name, "ChannelFixed", "ch1");  
	my $ChannelNames = AttrVal($name, "ChannelNames", "");
  my $DDSelected = ReadingsVal($name, "DDSelected", "");
	my $ShowShade = AttrVal($name, "ShowShade", 1);
  my $ShowIcons = AttrVal($name, "ShowIcons", 1);
  my $ShowLearn = AttrVal($name, "ShowLearn", 1);
  my $UI = AttrVal($name, "UI", "aus");
	my $Serial_send = AttrVal($name, "Serial_send", "");
	
	my @groups = split / /, $addGroups;														# split define groupnames
	my @grpInfo;																									# array of name and channels of group | name:channels
	my $grpName;																									# name of group
	my $html;


	### without UI
  if ($UI eq "aus" || $Serial_send eq "") {
		return;
  }
  
  ### ChannelNames festlegen
  my @ChName = ();																												# name standard
	my @ChName_alias = ();																									# alias name from attrib ChannelNames
	@ChName_alias = split /,/, $ChannelNames if ($ChannelNames ne "");			# overwrite array with values
  for my $rownr (1..16) {
		if ( scalar(@ChName_alias) > 0 && scalar(@ChName_alias) >= $rownr) {
			push(@ChName,"Kanal $rownr") if ($ChName_alias[$rownr-1] eq "");
			push(@ChName,$ChName_alias[$rownr-1]) if ($ChName_alias[$rownr-1] ne "");
		} else {
			push(@ChName,"Kanal $rownr");
		}
  }

  ### Mehrzeilig ###
  if ($UI eq "Mehrzeilig") {
		if (not exists $attr{$name}{ChannelFixed}) {
			$html = "<div><table class=\"block wide\">"; 
			foreach my $rownr (1..$Channels) {
				$html.= "<tr><td>";
				$html.= $ChName[$rownr-1]."</td>";
				$html.= SD_JARO_attr2htmlButtons("ch$rownr", $name, $ShowIcons, $ShowShade, $ShowLearn);
				$html.= "</tr>";
			}
		} else {
				$html = "<div><table class=\"block wide\">";
				$html.= "<tr><td>";
				my $ChannelNum = $ChannelFixed =~ s/ch//r;
				$html.= $ChName[$ChannelNum-1]."</td>";
				$html.= SD_JARO_attr2htmlButtons("ch$ChannelNum", $name, $ShowIcons, $ShowShade, $ShowLearn);
				$html.= "</tr>";
		}

		### Gruppen hinzu
		foreach my $grp (@groups) {
			my @grpInfo = split /:/, $grp;
			my $grpName = $grpInfo[0];
			$html.= "<tr><td>";
			$html.= $grpName."</td>";
			$html.= SD_JARO_attr2htmlButtons($grpInfo[1], $name, $ShowIcons, 0, 0);
			$html.= "</tr>";
		}
		
		$html.= "</table></div>";
		return $html;
  }

  ### Einzeilig ###
  if ($UI eq "Einzeilig") {
		if (not exists $attr{$name}{ChannelFixed}) {
			$html = "<div><table class=\"block wide\"><tr><td>"; 
			my $changecmd = "cmd.$name=setreading $name DDSelected ";
			$html.= "<select name=\"val.$name\" onchange=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$changecmd ' + this.options[this.selectedIndex].value)\">";
			foreach my $rownr (1..$Channels) {
				if ($DDSelected eq "ch$rownr"){
					$html.= "<option selected value=ch".($rownr).">".($ChName[$rownr-1])."</option>";
				} else {
					$html.= "<option value=ch".($rownr).">".($ChName[$rownr-1])."</option>";
				}
			}

			### Gruppen hinzu
			foreach my $grp (@groups) { 
				my @grpInfo = split /:/, $grp;
				my $grpName = $grpInfo[0];
				if ($DDSelected eq $grpInfo[1]) {
					$html.= "<option selected value=".$grpInfo[1].">".$grpName."</option>";
				} else {
					$html.= "<option value=".$grpInfo[1].">".$grpName."</option>";
				}
			}

			$html.= "</select></td>";
			$html.= SD_JARO_attr2htmlButtons("OptionValue", $name, $ShowIcons, $ShowShade, $ShowLearn);
			$html.= "</table></div>";
		}

		### Einzeilig with attrib ChannelFixed ###
		if (exists $attr{$name}{ChannelFixed}) {
			my $ChannelNum = $ChannelFixed =~ s/ch//r;
			$html = "<div><table class=\"block wide\"><tr><td>$ChName[$ChannelNum-1]</td>";
			$html.= SD_JARO_attr2htmlButtons($ChannelFixed, $name, $ShowIcons, $ShowShade, $ShowLearn);
			$html.= "</tr></table></div>";
		}

		return $html;
	}

  return;
}

#####################################
sub SD_JARO_attr2htmlButtons($$$$$) {
	my ($channel, $name, $ShowIcons, $ShowShade, $ShowLearn) = @_;
	my $html = "";
	
	# $name    = name of device
	# $channel = ch1 ... ch16 or channelgroup example 2,4
	
	### UP
	my $cmd = "cmd.$name=set $name $channel up";
	$html.="<td><a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmd')\">Hoch</a></td>" if (!$ShowIcons);
	if ($ShowIcons == 1){
		my $img = FW_makeImage("fts_shutter_up");
		$html.= "<td><a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmd')\">$img</a></td>";
	}

	### STOP
	$cmd = "cmd.$name=set $name $channel stop";
	$html.= "<td><a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmd')\">Stop</a></td>" if (!$ShowIcons);
	if ($ShowIcons == 1){
		my $img = FW_makeImage("rc_STOP");
		$html.= "<td><a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmd')\">$img</a></td>";
	}

	### DOWN
	$cmd = "cmd.$name=set $name $channel down";
	$html.= "<td><a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmd')\">Runter</a></td>" if (!$ShowIcons);
	if ($ShowIcons == 1){
		my $img = FW_makeImage("fts_shutter_down");
		$html.= "<td><a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmd')\">$img</a></td>";
	}

	### SHADE
	$cmd = "cmd.$name=set $name $channel shade";
	$html.= "<td><a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmd')\">Beschattung</a></td>" if (($ShowShade) && (!$ShowIcons));
	if ($ShowIcons == 1 && $ShowShade == 1){
		my $img = FW_makeImage("fts_shutter_shadding_run");
		$html.= "<td><a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmd')\">$img</a></td>";
	}

	### LEARN
	$cmd = "cmd.$name=set $name $channel learn";
	$html.= "<td><a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmd')\">Lernen</a></td>" if (($ShowLearn) && (!$ShowIcons));
	if ($ShowIcons == 1 && $ShowLearn == 1){
		my $img = FW_makeImage("fts_shutter_manual");
		$html.= "<td><a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmd')\">$img</a></td>";
	}
	return $html;
}

# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;


# Beginn der Commandref

=pod
=item [helper|device|command]
=item summary Kurzbeschreibung in Englisch was MYMODULE steuert/unterstützt
=item summary_DE Kurzbeschreibung in Deutsch was MYMODULE steuert/unterstützt

=begin html

<a name="SD_JARO"></a>
<h3>SD_JARO</h3>
<ul>The module SD_JARO is a <br>

	<b>Define</b><br>
	<ul><code>define &lt;NAME&gt; SD_JARO &lt;Device-ID&gt;</code><br><br>
	<u>examples:</u>
		<ul>
		define &lt;NAME&gt; SD_JARO 12345678<br>
		</ul>	</ul><br><br>

	<b>Set</b><br>
	<ul>N/A</ul><br><br>

	<b>Get</b><br>
	<ul>N/A</ul><br><br>

	<b>Attribute</b><br>
	<ul>N/A</ul>
	<br>
	
</ul>

</ul>
=end html
=begin html_DE

<a name="SD_JARO"></a>
<h3>SD_JARO</h3>
<ul>Das SD_JARO Modul simuliert eine Fernbedienung zur Steuerung anlernbarer Jarolift oder Roto TDEF-Funk-Motoren für Rollläden und Markisen. Dieses Modul wurde nach Vorlage des Bastelbudenbuben Projektes gefertigt. 
	Zur De- und Encodierung des Signals werden Keys benötigt welche via Attribut gesetzt werden müssen! Ohne Schl&uuml;ssel kann man das Modul zum empfangen der unverschl&uuml;sselten Daten nutzen.<br><br>
	Bei der Bedienung eines Motors mit einer anderen Fernbedienung wird der Status an das fhem-Device &uuml;bergeben.<br>
	Das angelegte Device wird mit der Serial der Fernbedienung angelegt. In dem Device wird der Zustand angezeigt und erst nach setzen des Attributes Serial_send kann man Motoren steuern nach erneutem anlernen.<br><br><br>

	<b>Define</b><br>
	<ul><code>define &lt;NAME&gt; SD_JARO &lt;Serial&gt; &lt;Typ&gt;</code><br><br>
	Beispiele: <ul><li>define SD_JARO_Device1 SD_JARO 12345678 JaroLift</li>
	<li>define SD_JARO_Device2 SD_JARO 123456 Roto</li></ul>
	</ul><br><br>

	<b>Set</b><br>
	<ul><code>set &lt;NAME&gt; &lt;command&gt;</code><br><br>
	<b>NAME:</b> ch1-16<br><br>
	<b>command:</b><br>
		<ul>
			<li><b>learn</b><br>
			Anlernen eines Motors. Motor dazu nach Herstellerangeben in den Anlernmodus versetzen.<br>
			<li><b>down</b><br>
			Motor nach unten<br>
			<li><b>up</b><br>
			Motor nach oben<br>
			<li><b>stop</b><br>
			Motor Motor stop<br>
			<li><b>updown</b><br>
			Gleichzeitges Drücken der Auf- und Abtaste zu Programmierzwecken.<br>
			<li><b>shade</b><br>
			Rolladen in Beschattungsposition bringen. wird nicht von allen Empfängern unterst&uuml;tzt.<br>
			<br>
		</ul>
	Beispiel: set ch3 down
	</ul><br><br>
	
	<b>Get</b><br>
	<ul>N/A</ul><br><br>

	<b>Attribute</b><br><br>
	<ul>
		<li><a name="addGroups"><b>addGroups</b></a><br>
		Gruppen in der Anzeige hinzufügen. &lt;Gruppenname&gt;:&lt;ch1&gt;,&lt;ch2&gt;<br>
		<i>Beispiel:</i> Nordseite:1,2,3 Südseite:4,5,6</li>
		<br>
		<li><a name="ChannelFixed"><b>ChannelFixed</b></a><br>
		Auswahl des fest eingestellten Kanals. Diese Option greift nur, wenn <code>UI = Einzeilig</code>
		</li>
		<br>
		<li><a name="ChannelNames"><b>ChannelNames</b></a><br>
		Beschriftung der einzelnen Kanäle anpassen. Kommagetrennte Werte.<br>
		<i>Beispiel:</i> Küche,Wohnen,Schlafen,Kinderzimmer
		</li>
		<br>
		<li><a name="Channels"><b>Channels</b></a><br>
		Auswahl, wie viele Kan&auml;le in der UI angezeigt werden sollen. (Standard 1)<br>
		Um nur Gruppen anzuzeigen, Channels:0 und addGroups setzen. Der Wert Channels:0 wird nur akzeptiert wenn addGroups definiert sind.
		</li>
		<br>
		<li><a name="KeeLoq_NLF"><b>KeeLoq_NLF</b></a><br>
		Key zur De- und Encodierung. Die Angabe erfolgt hexadezimal, 8 stellig + f&uuml;hrend mit 0x.<br>
		<i>Beispiel:</i> 0xaaaaaaaa
		</li>
		<br>
		<li><a name="MasterLSB"><b>MasterLSB</b></a><br>
		Key zur De- und Encodierung des Keeloq Rolling Codes. Die Angabe erfolgt hexadezimal, 8 stellig + f&uuml;hrend mit 0x.<br>
		<i>Beispiel:</i> 0xbbbbbbbb
		</li>
		<br>
		<li><a name="MasterMSB"><b>MasterMSB</b></a><br>
		Key zur De- und Encodierung des Keeloq Rolling Codes. Die Angabe erfolgt hexadezimal, 8 stellig + f&uuml;hrend mit 0x.<br>
		<i>Beispiel:</i> 0xcccccccc
		</li>
		<br>
		<li><a name="Repeats"><b>Repeats</b></a><br>
		Mit diesem Attribut kann angepasst werden, wie viele Wiederholungen sendet werden. (Standard 3)
		</li>
		<br>
		<li><a name="Serial_send"><b>Serial_send</b></a><br>
		Eine Serialnummer zum Senden. Sie MUSS eindeutig im ganzen System sein. OHNE Attribut Serial_send erh&auml;lt der User keine Setlist --> nur Empfang m&ouml;glich!<br>
		<i>Beispiel:</i> 12345678
		</li>
		<br>
		<li><a name="ShowIcons"><b>ShowIcons</b></a><br>
		Anstelle der Beschriftung Icons anzeigen. (Standard 0)<br>
		</li>
		<br>
		<li><a name="ShowLearn"><b>ShowLearn</b></a><br>
		Beschriftung, bzw. Button, für das Anlernen des Rollos anzeigen. (Standard 1)
		</li>
		<br>
		<li><a name="ShowShade"><b>ShowShade</b></a><br>
		Nicht von allen Empfängern unterstützt. Button zum fahren in Beschattungsposition ausblenden. (Standard 1)
		</li>
		<br>
		<li><a name="UI"><b>UI</b></a><br>
		Anzeigeart (UserInterface) in FHEM (Standard:aus)
		<br>
		<ul><li>Mehrzeilig:<br>
		Ausgewählte Anzahl an Kanälen wird Tabellarisch statt des STATE-Icons angezeigt</li>
		<li>Einzeilig:<br>
		Es wird nur eine Zeile mit einem Auswahlfeld für den Kanal angezeigt.</li>
		<li>aus:<br>
		Es wird nichts angezeigt. (Nur über SET-Befehle steuerbar).
		</li></ul>
	</ul>
	<br><br>
	<b>Generierte gemeinsamgenutzte Readings | JaroLift & Roto</b><br><br>
	<ul>
	<li>button<br>
	Gedrückter Knopf an der Fernbedienung oder im FHEM Device.</li>
	<li>serial_receive<br>
	Seriennummer des empfangen Ger&auml;tes.</li>
	<li>typ<br>
	Name des Ger&auml;teherstellers.</li>
	<li>user_info<br>
	Informationstext für den Benutzer. Es werden Tips und Handlungen ausgegeben.</li>
	<li>user_modus<br>
	Information über den Devicestatus (all_functions: es kann mit dem Device empfangen und gesendet werden | limited_functions: es kann nur empfangen werden)</li><br>
	</ul>
	<b>Generierte Readings JaroLift spezifisch</b><br><br>
	<ul>
	<li>_LastAction_Channel_xx<br>
	Zuletzt ausgef&uuml;hrte Aktion des Kanals.</li>
	<li>last_digits<br>
	Kanal aus dem verschl&uuml;sseltem Teil der empfangenem Nachricht.</li>
	<li>channel<br>
	Zu steuernder Kanal.</li>
	<li>channel_control<br>
	Bei mehreren angesteuerten Kan&auml;len, entnehmbare Kan&auml;le, sonst "no".</li>
	<li>counter_receive<br>
	Zähler des Empfangsbefehles.</li>
	<li>counter_send<br>
	Zähler des Sendebefehles.</li>
	</ul>
</ul>

=end html_DE
=cut