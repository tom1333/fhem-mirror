# $Id$
##############################################################################
#
#     70_ONKYO_AVR_ZONE.pm
#     An FHEM Perl module for controlling ONKYO A/V receivers
#     via network connection.
#
#     Copyright by Julian Pawlowski
#     e-mail: julian.pawlowski at gmail.com
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package main;

use strict;
use warnings;
use ONKYOdb;
use Time::HiRes qw(usleep);
use Symbol qw<qualify_to_ref>;
use File::Path;
use File::stat;
use File::Temp;
use File::Copy;
use Data::Dumper;

$Data::Dumper::Sortkeys = 1;

no if $] >= 5.017011, warnings => 'experimental::smartmatch';
no if $] >= 5.017011, warnings => 'experimental::lexical_topic';

sub ONKYO_AVR_ZONE_Set($$$);
sub ONKYO_AVR_ZONE_Get($$$);
sub ONKYO_AVR_ZONE_Define($$$);
sub ONKYO_AVR_ZONE_Undefine($$);

#########################
# Forward declaration for remotecontrol module
sub ONKYO_AVR_ZONE_RClayout_TV();
sub ONKYO_AVR_ZONE_RCmakenotify($$);

###################################
sub ONKYO_AVR_ZONE_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "ONKYO_AVR_ZONE_Initialize: Entering";

    eval 'use XML::Simple qw(:strict); 1';
    return "Please install XML::Simple to use this module."
      if ($@);

    $hash->{Match} = ".+";

    $hash->{DefFn}   = "ONKYO_AVR_ZONE_Define";
    $hash->{UndefFn} = "ONKYO_AVR_ZONE_Undefine";

    #    $hash->{DeleteFn} = "ONKYO_AVR_ZONE_Delete";
    $hash->{SetFn} = "ONKYO_AVR_ZONE_Set";
    $hash->{GetFn} = "ONKYO_AVR_ZONE_Get";

    #    $hash->{AttrFn}   = "ONKYO_AVR_ZONE_Attr";
    #    $hash->{NotifyFn} = "ONKYO_AVR_ZONE_Notify";
    $hash->{ParseFn} = "ONKYO_AVR_ZONE_Parse";

    $hash->{AttrList} =
        "IODev do_not_notify:1,0 "
      . "volumeSteps:1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20 inputs disable:0,1 model wakeupCmd:textField "
      . $readingFnAttributes;

    #    $data{RC_layout}{ONKYO_AVR_ZONE_SVG} = "ONKYO_AVR_ZONE_RClayout_SVG";
    #    $data{RC_layout}{ONKYO_AVR_ZONE}     = "ONKYO_AVR_ZONE_RClayout";
    $data{RC_makenotify}{ONKYO_AVR_ZONE} = "ONKYO_AVR_RCmakenotify";

    $hash->{parseParams} = 1;
}

###################################
sub ONKYO_AVR_ZONE_Define($$$) {
    my ( $hash, $a, $h ) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 5,
      "ONKYO_AVR_ZONE $name: called function ONKYO_AVR_ZONE_Define()";

    if ( int(@$a) < 2 ) {
        my $msg = "Wrong syntax: define <name> ONKYO_AVR_ZONE [<zone>]";
        Log3 $name, 4, $msg;
        return $msg;
    }

    AssignIoPort($hash);

    my $IOhash = $hash->{IODev};
    my $IOname = $IOhash->{NAME};
    my $zone   = @$a[2] || "2";

    if ( defined( $modules{ONKYO_AVR_ZONE}{defptr}{$IOname}{$zone} ) ) {
        return "Zone already defined in "
          . $modules{ONKYO_AVR_ZONE}{defptr}{$IOname}{$zone}{NAME};
    }
    elsif ( !defined($IOhash) ) {
        return "No matching I/O device found";
    }
    elsif ( !defined( $IOhash->{TYPE} ) || !defined( $IOhash->{NAME} ) ) {
        return "IODev does not seem to be existing";
    }
    elsif ( $IOhash->{TYPE} ne "ONKYO_AVR" ) {
        return "IODev is not of type ONKYO_AVR";
    }
    else {
        $hash->{ZONE} = $zone;
    }

    $hash->{INPUT} = "";
    $modules{ONKYO_AVR_ZONE}{defptr}{$IOname}{$zone} = $hash;

    # set default settings on first define
    if ($init_done) {
        fhem 'attr ' . $name . ' stateFormat stateAV';
        fhem 'attr ' . $name
          . ' cmdIcon muteT:rc_MUTE previous:rc_PREVIOUS next:rc_NEXT play:rc_PLAY pause:rc_PAUSE stop:rc_STOP shuffleT:rc_SHUFFLE repeatT:rc_REPEAT';
        fhem 'attr ' . $name . ' webCmd volume:muteT:input:previous:next';
        fhem 'attr ' . $name
          . ' devStateIcon on:rc_GREEN@green:off off:rc_STOP:on absent:rc_RED playing:rc_PLAY@green:pause paused:rc_PAUSE@green:play muted:rc_MUTE@green:muteT fast-rewind:rc_REW@green:play fast-forward:rc_FF@green:play interrupted:rc_PAUSE@yellow:play';
        fhem 'attr ' . $name . ' inputs ' . AttrVal( $IOname, "inputs", "" )
          if ( AttrVal( $IOname, "inputs", "" ) ne "" );
        fhem 'attr ' . $name . ' room ' . AttrVal( $IOname, "room", "" )
          if ( AttrVal( $IOname, "room", "" ) ne "" );
    }

    ONKYO_AVR_ZONE_SendCommand( $hash, "power",  "query" );
    ONKYO_AVR_ZONE_SendCommand( $hash, "input",  "query" );
    ONKYO_AVR_ZONE_SendCommand( $hash, "mute",   "query" );
    ONKYO_AVR_ZONE_SendCommand( $hash, "volume", "query" );

    return;
}

###################################
sub ONKYO_AVR_ZONE_Undefine($$) {
    my ( $hash, $name ) = @_;
    my $zone   = $hash->{ZONE};
    my $IOhash = $hash->{IODev};
    my $IOname = $IOhash->{NAME};

    Log3 $name, 5,
      "ONKYO_AVR_ZONE $name: called function ONKYO_AVR_ZONE_Undefine()";

    delete $modules{ONKYO_AVR_ZONE}{defptr}{$IOname}{$zone}
      if ( defined( $modules{ONKYO_AVR_ZONE}{defptr}{$IOname}{$zone} ) );

    # Disconnect from device
    DevIo_CloseDev($hash);

    # Stop the internal GetStatus-Loop and exit
    RemoveInternalTimer($hash);

    return undef;
}

#############################
sub ONKYO_AVR_ZONE_Parse($$) {
    my ( $IOhash, $msg ) = @_;
    my @matches;
    my $IOname = $IOhash->{NAME};
    my $zone = $msg->{zone} || "";

    delete $msg->{zone} if ( defined( $msg->{zone} ) );

    Log3 $IOname, 5,
      "ONKYO_AVR $IOname: called function ONKYO_AVR_ZONE_Parse()";

    foreach my $d ( keys %defs ) {
        my $hash  = $defs{$d};
        my $name  = $hash->{NAME};
        my $state = ReadingsVal( $name, "power", "off" );

        if (   $hash->{TYPE} eq "ONKYO_AVR_ZONE"
            && $hash->{IODev} eq $IOhash
            && ( $zone eq "" || $hash->{ZONE} eq $zone ) )
        {
            push @matches, $d;

            # Update readings
            readingsBeginUpdate($hash);

            foreach my $cmd ( keys %{$msg} ) {
                my $value = $msg->{$cmd};

                $hash->{INPUT}   = $value and next if ( $cmd eq "INPUT_RAW" );
                $hash->{CHANNEL} = $value and next if ( $cmd eq "CHANNEL_RAW" );

                Log3 $name, 4, "ONKYO_AVR_ZONE $name: rcv $cmd = $value";

                # presence
                if ( $cmd eq "presence" && $value eq "present" ) {
                    ONKYO_AVR_ZONE_SendCommand( $hash, "power",  "query" );
                    ONKYO_AVR_ZONE_SendCommand( $hash, "input",  "query" );
                    ONKYO_AVR_ZONE_SendCommand( $hash, "mute",   "query" );
                    ONKYO_AVR_ZONE_SendCommand( $hash, "volume", "query" );
                }

                # input
                if ( $cmd eq "input" ) {

                    # Input alias handling
                    if (
                        defined(
                            $hash->{helper}{receiver}{input_aliases}{$value}
                        )
                      )
                    {
                        Log3 $name, 4,
                            "ONKYO_AVR $name: Input aliasing '$value' to '"
                          . $hash->{helper}{receiver}{input_aliases}{$value}
                          . "'";
                        $value =
                          $hash->{helper}{receiver}{input_aliases}{$value};
                    }
                }

                if ( $cmd eq "power" ) {
                    readingsBulkUpdate( $hash, "presence", "present" )
                      if ( ReadingsVal( $name, "presence", "-" ) ne "present" );
                }

                readingsBulkUpdate( $hash, $cmd, $value )
                  if ( ReadingsVal( $name, $cmd, "-" ) ne $value );

                # stateAV
                my $stateAV = ONKYO_AVR_ZONE_GetStateAV($hash);
                readingsBulkUpdate( $hash, "stateAV", $stateAV )
                  if ( ReadingsVal( $name, "stateAV", "-" ) ne $stateAV );

            }

            readingsEndUpdate( $hash, 1 );
            last;
        }
    }
    return @matches if (@matches);
    return "UNDEFINED ONKYO_AVR_ZONE";
}

###################################
sub ONKYO_AVR_ZONE_Get($$$) {
    my ( $hash, $a, $h ) = @_;
    my $name             = $hash->{NAME};
    my $zone             = $hash->{ZONE};
    my $state            = ReadingsVal( $name, "power", "off" );
    my $presence         = ReadingsVal( $name, "presence", "absent" );
    my $commands         = ONKYOdb::ONKYO_GetRemotecontrolCommand($zone);
    my $commands_details = ONKYOdb::ONKYO_GetRemotecontrolCommandDetails($zone);
    my $return;

    Log3 $name, 5, "ONKYO_AVR_ZONE $name: called function ONKYO_AVR_ZONE_Get()";

    return "Argument is missing" if ( int(@$a) < 1 );

    # remoteControl
    if ( lc( @$a[1] ) eq "remotecontrol" ) {

        # Output help for commands
        if ( !defined( @$a[2] ) || @$a[2] eq "help" || @$a[2] eq "?" ) {

            my $valid_commands =
                "Usage: <command> <value>\n\nValid commands in zone$zone:\n\n\n"
              . "COMMAND\t\t\tDESCRIPTION\n\n";

            # For each valid command
            foreach my $command ( sort keys %{$commands} ) {
                my $command_raw = $commands->{$command};

                # add command including description if found
                if ( defined( $commands_details->{$command_raw}{description} ) )
                {
                    $valid_commands .=
                        $command
                      . "\t\t\t"
                      . $commands_details->{$command_raw}{description} . "\n";
                }

                # add command only
                else {
                    $valid_commands .= $command . "\n";
                }
            }

            $valid_commands .=
"\nTry '&lt;command&gt; help' to find out well known values.\n\n\n";

            $return = $valid_commands;
        }
        else {
            # Reading values for command from HASH table
            my $values =
              ONKYOdb::ONKYO_GetRemotecontrolValue( $zone,
                $commands->{ @$a[2] } );

            @$a[3] = "query"
              if ( !defined( @$a[3] ) && defined( $values->{query} ) );

            # Output help for values
            if ( !defined( @$a[3] ) || @$a[3] eq "help" || @$a[3] eq "?" ) {

                # Get all details for command
                my $command_details =
                  ONKYOdb::ONKYO_GetRemotecontrolCommandDetails( $zone,
                    $commands->{ @$a[2] } );

                my $valid_values =
                    "Usage: "
                  . @$a[2]
                  . " <value>\n\nWell known values:\n\n\n"
                  . "VALUE\t\t\tDESCRIPTION\n\n";

                # For each valid value
                foreach my $value ( sort keys %{$values} ) {

                    # add value including description if found
                    if ( defined( $command_details->{description} ) ) {
                        $valid_values .=
                            $value
                          . "\t\t\t"
                          . $command_details->{description} . "\n";
                    }

                    # add value only
                    else {
                        $valid_values .= $value . "\n";
                    }
                }

                $valid_values .= "\n\n\n";

                $return = $valid_values;
            }

            # normal processing
            else {
                Log3 $name, 3,
                    "ONKYO_AVR_ZONE get $name "
                  . @$a[1] . " "
                  . @$a[2] . " "
                  . @$a[3];

                if ( $presence ne "absent" ) {
                    ONKYO_AVR_ZONE_SendCommand( $hash, @$a[2], @$a[3] );
                    $return = "Sent command: " . @$a[2] . " " . @$a[3];
                }
                else {
                    $return =
                      "Device needs to be reachable to be controlled remotely.";
                }
            }
        }
    }

    # readings
    elsif ( defined( $hash->{READINGS}{ @$a[1] } ) ) {
        $return = $hash->{READINGS}{ @$a[1] }{VAL};
    }
    else {
        $return = "Unknown argument " . @$a[1] . ", choose one of";

        # remoteControl
        $return .= " remoteControl:";
        foreach my $command ( sort keys %{$commands} ) {
            $return .= "," . $command;
        }
    }

    return $return;
}

###################################
sub ONKYO_AVR_ZONE_Set($$$) {
    my ( $hash, $a, $h ) = @_;
    my $IOhash   = $hash->{IODev};
    my $name     = $hash->{NAME};
    my $zone     = $hash->{ZONE};
    my $state    = ReadingsVal( $name, "power", "off" );
    my $presence = ReadingsVal( $name, "presence", "absent" );
    my $return;
    my $reading;
    my $inputs_txt   = "";
    my $channels_txt = "";
    my @implicit_cmds;
    my $implicit_txt = "";

    Log3 $name, 5, "ONKYO_AVR_ZONE $name: called function ONKYO_AVR_ZONE_Set()";

    return "Argument is missing" if ( int(@$a) < 1 );

    # Input alias handling
    if ( defined( $attr{$name}{inputs} ) && $attr{$name}{inputs} ne "" ) {
        my @inputs = split( ':', $attr{$name}{inputs} );

        if (@inputs) {
            foreach (@inputs) {
                if (m/[^,\s]+(,[^,\s]+)+/) {
                    my @input_names = split( ',', $_ );
                    $inputs_txt .= $input_names[1] . ",";
                    $input_names[1] =~ s/\s/_/g;
                    $hash->{helper}{receiver}{input_aliases}{ $input_names[0] }
                      = $input_names[1];
                    $hash->{helper}{receiver}{input_names}{ $input_names[1] } =
                      $input_names[0];
                }
                else {
                    $inputs_txt .= $_ . ",";
                }
            }
        }

        $inputs_txt =~ s/\s/_/g;
        $inputs_txt = substr( $inputs_txt, 0, -1 );
    }

    # if we could read the actual available inputs from the receiver, use them
    elsif (defined( $IOhash->{helper}{receiver} )
        && ref( $IOhash->{helper}{receiver} ) eq "HASH"
        && defined( $IOhash->{helper}{receiver}{device}{selectorlist}{count} )
        && $IOhash->{helper}{receiver}{device}{selectorlist}{count} > 0 )
    {

        foreach my $input (
            @{ $IOhash->{helper}{receiver}{device}{selectorlist}{selector} } )
        {
            if (   $input->{value} eq "1"
                && $input->{zone} ne "00"
                && $input->{id} ne "80" )
            {
                my $id   = $input->{id};
                my $name = trim( $input->{name} );
                $inputs_txt .= $name . ",";
            }
        }

        $inputs_txt =~ s/\s/_/g;
        $inputs_txt = substr( $inputs_txt, 0, -1 );
    }

    # use general list of possible inputs
    else {
        # Find out valid inputs
        my $inputs =
          ONKYOdb::ONKYO_GetRemotecontrolValue( $zone,
            ONKYOdb::ONKYO_GetRemotecontrolCommand( $zone, "input" ) );

        foreach my $input ( sort keys %{$inputs} ) {
            $inputs_txt .= $input . ","
              if ( !( $input =~ /^(07|08|09|up|down|query)$/ ) );
        }
        $inputs_txt = substr( $inputs_txt, 0, -1 );
    }

    # list of network channels/services
    if (   defined( $IOhash->{helper}{receiver} )
        && ref( $IOhash->{helper}{receiver} ) eq "HASH"
        && defined( $IOhash->{helper}{receiver}{device}{netservicelist}{count} )
        && $IOhash->{helper}{receiver}{device}{netservicelist}{count} > 0 )
    {

        foreach my $id (
            sort keys
            %{ $IOhash->{helper}{receiver}{device}{netservicelist}{netservice} }
          )
        {
            if (
                defined(
                    $IOhash->{helper}{receiver}{device}{netservicelist}
                      {netservice}{$id}{value}
                )
                && $IOhash->{helper}{receiver}{device}{netservicelist}
                {netservice}{$id}{value} eq "1"
              )
            {
                $channels_txt .=
                  trim( $IOhash->{helper}{receiver}{device}{netservicelist}
                      {netservice}{$id}{name} )
                  . ",";
            }
        }

        $channels_txt =~ s/\s/_/g;
        $channels_txt = substr( $channels_txt, 0, -1 );
    }

    # for each reading, check if there is a known command for it
    # and allow to set values if there are any available
    if ( defined( $hash->{READINGS} ) ) {

        foreach my $reading ( keys %{ $hash->{READINGS} } ) {
            my $cmd_raw =
              ONKYOdb::ONKYO_GetRemotecontrolCommand( $zone, $reading );
            my @readingExceptions = ( "volume", "input", "mute", "sleep" );

            if ( $cmd_raw && !( grep $_ eq $reading, @readingExceptions ) ) {
                my $cmd_details =
                  ONKYOdb::ONKYO_GetRemotecontrolCommandDetails( $zone,
                    $cmd_raw );

                my $value_list = "";
                my $debuglist;
                foreach my $value ( keys %{ $cmd_details->{values} } ) {
                    next
                      if ( $value eq "QSTN" );

                    if ( defined( $cmd_details->{values}{$value}{name} ) ) {
                        $value_list .= "," if ( $value_list ne "" );

                        $value_list .= $cmd_details->{values}{$value}{name}
                          if (
                            ref( $cmd_details->{values}{$value}{name} ) eq "" );

                        $value_list .= $cmd_details->{values}{$value}{name}[0]
                          if (
                            ref( $cmd_details->{values}{$value}{name} ) eq
                            "ARRAY" );
                    }
                }

                if ( $value_list ne "" ) {
                    push @implicit_cmds, $reading;
                    $implicit_txt .= " $reading:$value_list";
                }
            }
        }
    }

    my $shuffle_txt = "shuffle:";
    $shuffle_txt .= "," if ( ReadingsVal( $name, "shuffle", "-" ) eq "-" );
    $shuffle_txt .= "off,on,on-album,on-folder";

    my $repeat_txt = "repeat:";
    $repeat_txt .= "," if ( ReadingsVal( $name, "repeat", "-" ) eq "-" );
    $repeat_txt .= "off,all,all-folder,one";

    my $usage =
        "Unknown argument '"
      . @$a[1]
      . "', choose one of toggle:noArg on:noArg off:noArg volume:slider,0,1,100 volumeUp:noArg volumeDown:noArg mute:off,on muteT:noArg play:noArg pause:noArg stop:noArg previous:noArg next:noArg shuffleT:noArg repeatT:noArg remoteControl:play,pause,repeat,stop,top,down,up,right,delete,display,ff,left,mode,return,rew,select,setup,0,1,2,3,4,5,6,7,8,9,prev,next,shuffle,menu channelDown:noArg channelUp:noArg input:"
      . $inputs_txt;
    $usage .= " channel:$channels_txt";
    $usage .= " $shuffle_txt";
    $usage .= " $repeat_txt";
    $usage .= $implicit_txt if ( $implicit_txt ne "" );

    my $cmd = '';

    readingsBeginUpdate($hash);

    # channel
    if ( lc( @$a[1] ) eq "channel" ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1] . " " . @$a[2];

        if ( !defined( @$a[2] ) ) {
            $return = "Syntax: CHANNELNAME [USERNAME PASSWORD]";
        }
        else {
            if ( $presence eq "absent" ) {
                $return =
                  "Device is offline and cannot be controlled at that stage.";
            }
            elsif ( $state eq "off" ) {
                $return = fhem "set $name on";
                $return .= fhem "sleep 5;set $name channel " . @$a[2];
            }
            elsif ( $hash->{INPUT} ne "2B" ) {
                ONKYO_AVR_ZONE_SendCommand( $hash, "input", "2B" );
                $return = fhem "sleep 1;set $name channel " . @$a[2];
            }
            elsif (
                ReadingsVal( $name, "channel", "" ) ne @$a[2]
                && defined(
                    $IOhash->{helper}{receiver}{device}{netservicelist}
                      {netservice}
                )
              )
            {

                my $servicename = "";
                my $channelname = @$a[2];
                $channelname =~ s/_/ /g;

                foreach my $id (
                    sort keys %{
                        $IOhash->{helper}{receiver}{device}{netservicelist}
                          {netservice}
                    }
                  )
                {
                    if (
                        defined(
                            $IOhash->{helper}{receiver}{device}
                              {netservicelist}{netservice}{$id}{value}
                        )
                        && $IOhash->{helper}{receiver}{device}
                        {netservicelist}{netservice}{$id}{value} eq "1"
                        && $IOhash->{helper}{receiver}{device}
                        {netservicelist}{netservice}{$id}{name} eq $channelname
                      )
                    {
                        $servicename .= uc($id);
                        $servicename .= "0" if ( !defined( @$a[3] ) );
                        $servicename .= @$a[3] if ( defined( @$a[3] ) );
                        $servicename .= @$a[4] if ( defined( @$a[4] ) );

                        last;
                    }
                }

                $return =
                  ONKYO_AVR_SendCommand( $IOhash, "net-service", $servicename )
                  if ( $servicename ne "" );

                $return = "Unknown network service name " . @$a[2]
                  if ( $servicename eq "" );
            }
        }
    }

    # implicit commands through available readings
    elsif ( grep $_ eq lc( @$a[1] ), @implicit_cmds ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1] . " " . @$a[2];

        if ( !defined( @$a[2] ) ) {
            $return = "No argument given, choose one of ?";
        }
        else {
            if ( $presence eq "absent" ) {
                $return =
                  "Device is offline and cannot be controlled at that stage.";
            }
            else {
                $return = ONKYO_AVR_ZONE_SendCommand( $hash, @$a[1], @$a[2] );
            }
        }
    }

    # toggle
    elsif ( lc( @$a[1] ) eq "toggle" ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];

        if ( $state eq "off" ) {
            $return = fhem "set $name on";
        }
        else {
            $return = fhem "set $name off";
        }
    }

    # on
    elsif ( lc( @$a[1] ) eq "on" ) {
        if ( $presence eq "absent" ) {
            Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1] . " (wakeup)";
            my $wakeupCmd = AttrVal( $name, "wakeupCmd", "" );

            if ( $wakeupCmd ne "" ) {
                $wakeupCmd =~ s/\$DEVICE/$name/g;

                if ( $wakeupCmd =~ s/^[ \t]*\{|\}[ \t]*$//g ) {
                    Log3 $name, 4,
"ONKYO_AVR_ZONE executing wake-up command (Perl): $wakeupCmd";
                    $return = eval $wakeupCmd;
                }
                else {
                    Log3 $name, 4,
"ONKYO_AVR_ZONE executing wake-up command (fhem): $wakeupCmd";
                    $return = fhem $wakeupCmd;
                }
            }
            else {
                $return =
                  "Device is offline and cannot be controlled at that stage.";
            }
        }
        else {
            Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "power", "on" );
        }
    }

    # off
    elsif ( lc( @$a[1] ) eq "off" ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];

        if ( $presence eq "absent" ) {
            $return =
              "Device is offline and cannot be controlled at that stage.";
        }
        else {
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "power", "off" );
        }
    }

    # remoteControl
    elsif ( lc( @$a[1] ) eq "remotecontrol" ) {
        if ( !defined( @$a[2] ) ) {
            $return = "No argument given, choose one of minutes off";
        }
        else {
            Log3 $name, 3, "ONKYO_AVR set $name " . @$a[1] . " " . @$a[2];

            if ( $presence eq "absent" ) {
                $return =
                  "Device is offline and cannot be controlled at that stage.";
            }
            else {
                if (   lc( @$a[2] ) eq "play"
                    || lc( @$a[2] ) eq "pause"
                    || lc( @$a[2] ) eq "repeat"
                    || lc( @$a[2] ) eq "stop"
                    || lc( @$a[2] ) eq "top"
                    || lc( @$a[2] ) eq "down"
                    || lc( @$a[2] ) eq "up"
                    || lc( @$a[2] ) eq "right"
                    || lc( @$a[2] ) eq "delete"
                    || lc( @$a[2] ) eq "display"
                    || lc( @$a[2] ) eq "ff"
                    || lc( @$a[2] ) eq "left"
                    || lc( @$a[2] ) eq "mode"
                    || lc( @$a[2] ) eq "return"
                    || lc( @$a[2] ) eq "rew"
                    || lc( @$a[2] ) eq "select"
                    || lc( @$a[2] ) eq "setup"
                    || lc( @$a[2] ) eq "0"
                    || lc( @$a[2] ) eq "1"
                    || lc( @$a[2] ) eq "2"
                    || lc( @$a[2] ) eq "3"
                    || lc( @$a[2] ) eq "4"
                    || lc( @$a[2] ) eq "5"
                    || lc( @$a[2] ) eq "6"
                    || lc( @$a[2] ) eq "7"
                    || lc( @$a[2] ) eq "8"
                    || lc( @$a[2] ) eq "9" )
                {
                    $return =
                      ONKYO_AVR_SendCommand( $hash, "net-usb-z", lc( @$a[2] ) );
                }
                elsif ( lc( @$a[2] ) eq "prev" ) {
                    $return =
                      ONKYO_AVR_SendCommand( $hash, "net-usb-z", "trdown" );
                }
                elsif ( lc( @$a[2] ) eq "next" ) {
                    $return =
                      ONKYO_AVR_SendCommand( $hash, "net-usb-z", "trup" );
                }
                elsif ( lc( @$a[2] ) eq "shuffle" ) {
                    $return =
                      ONKYO_AVR_SendCommand( $hash, "net-usb-z", "random" );
                }
                elsif ( lc( @$a[2] ) eq "menu" ) {
                    $return =
                      ONKYO_AVR_SendCommand( $hash, "net-usb-z", "men" );
                }
                else {
                    $return = "Unsupported remoteControl command: " . @$a[2];
                }
            }
        }
    }

    # play
    elsif ( lc( @$a[1] ) eq "play" ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];

        if ( $state ne "on" ) {
            $return =
"Device power is turned off, this function is unavailable at that stage.";
        }
        else {
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "net-usb-z", "play" );
        }
    }

    # pause
    elsif ( lc( @$a[1] ) eq "pause" ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];

        if ( $state ne "on" ) {
            $return =
"Device power is turned off, this function is unavailable at that stage.";
        }
        else {
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "net-usb-z", "pause" );
        }
    }

    # stop
    elsif ( lc( @$a[1] ) eq "stop" ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];

        if ( $state ne "on" ) {
            $return =
"Device power is turned off, this function is unavailable at that stage.";
        }
        else {
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "net-usb-z", "stop" );
        }
    }

    # shuffle
    elsif ( lc( @$a[1] ) eq "shuffle" || lc( @$a[1] ) eq "shufflet" ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];

        if ( $state ne "on" ) {
            $return =
"Device power is turned off, this function is unavailable at that stage.";
        }
        else {
            $return =
              ONKYO_AVR_ZONE_SendCommand( $hash, "net-usb-z", "random" );
        }
    }

    # repeat
    elsif ( lc( @$a[1] ) eq "repeat" || lc( @$a[1] ) eq "repeatt" ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];

        if ( $state ne "on" ) {
            $return =
"Device power is turned off, this function is unavailable at that stage.";
        }
        else {
            $return =
              ONKYO_AVR_ZONE_SendCommand( $hash, "net-usb-z", "repeat" );
        }
    }

    # previous
    elsif ( lc( @$a[1] ) eq "previous" ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];

        if ( $state ne "on" ) {
            $return =
"Device power is turned off, this function is unavailable at that stage.";
        }
        else {
            $return =
              ONKYO_AVR_ZONE_SendCommand( $hash, "net-usb-z", "trdown" );
        }
    }

    # next
    elsif ( lc( @$a[1] ) eq "next" ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];

        if ( $state ne "on" ) {
            $return =
"Device power is turned off, this function is unavailable at that stage.";
        }
        else {
            $return = ONKYO_AVR_ZONE_SendCommand( $hash, "net-usb-z", "trup" );
        }
    }

    # mute
    elsif ( lc( @$a[1] ) eq "mute" || lc( @$a[1] ) eq "mutet" ) {
        if ( defined( @$a[2] ) ) {
            Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1] . " " . @$a[2];
        }
        else {
            Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];
        }

        if ( $state eq "on" ) {
            if ( !defined( @$a[2] ) || @$a[2] eq "toggle" ) {
                $return = ONKYO_AVR_ZONE_SendCommand( $hash, "mute", "toggle" );
            }
            elsif ( lc( @$a[2] ) eq "off" ) {
                $return = ONKYO_AVR_ZONE_SendCommand( $hash, "mute", "off" );
            }
            elsif ( lc( @$a[2] ) eq "on" ) {
                $return = ONKYO_AVR_ZONE_SendCommand( $hash, "mute", "on" );
            }
            else {
                $return = "Argument does not seem to be one of on off toogle";
            }
        }
        else {
            $return = "Device needs to be ON to mute/unmute audio.";
        }
    }

    # volume
    elsif ( lc( @$a[1] ) eq "volume" ) {
        if ( !defined( @$a[2] ) ) {
            $return = "No argument given";
        }
        else {
            Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1] . " " . @$a[2];

            if ( $state eq "on" ) {
                my $_ = @$a[2];
                if ( m/^\d+$/ && $_ >= 0 && $_ <= 100 ) {
                    $return =
                      ONKYO_AVR_ZONE_SendCommand( $hash, "volume",
                        ONKYO_AVR_ZONE_dec2hex($_) );
                }
                else {
                    $return =
"Argument does not seem to be a valid integer between 0 and 100";
                }
            }
            else {
                $return = "Device needs to be ON to adjust volume.";
            }
        }
    }

    # volumeUp/volumeDown
    elsif ( lc( @$a[1] ) =~ /^(volumeup|volumedown)$/ ) {
        Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1];

        if ( $state eq "on" ) {
            if ( lc( @$a[1] ) eq "volumeup" ) {
                $return =
                  ONKYO_AVR_ZONE_SendCommand( $hash, "volume", "level-up" );
            }
            else {
                $return =
                  ONKYO_AVR_ZONE_SendCommand( $hash, "volume", "level-down" );
            }
        }
        else {
            $return = "Device needs to be ON to adjust volume.";
        }
    }

    # input
    elsif ( lc( @$a[1] ) eq "input" ) {
        if ( !defined( @$a[2] ) ) {
            $return = "No input given";
        }
        else {
            Log3 $name, 3, "ONKYO_AVR_ZONE set $name " . @$a[1] . " " . @$a[2];

            if ( $state eq "off" ) {
                $return = fhem "set $name on";
                $return = ONKYO_AVR_ZONE_SendCommand( $hash, "input", @$a[2] );
            }
            elsif ( $state eq "on" ) {
                $return = ONKYO_AVR_ZONE_SendCommand( $hash, "input", @$a[2] );
            }
            else {
                $return = "Device needs to be ON to change input.";
            }
        }
    }

    # return usage hint
    else {
        $return = $usage;
    }

    readingsEndUpdate( $hash, 1 );

    # return result
    return $return;
}

############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################

###################################
sub ONKYO_AVR_ZONE_SendCommand($$$) {
    my ( $hash, $cmd, $value ) = @_;
    my $IOhash = $hash->{IODev};
    my $name   = $hash->{NAME};
    my $zone   = $hash->{ZONE};

    Log3 $name, 5,
      "ONKYO_AVR_ZONE $name: called function ONKYO_AVR_ZONE_SendCommand()";

    # Input alias handling
    if ( $cmd eq "input" ) {

        # Resolve input alias to correct name
        if ( defined( $hash->{helper}{receiver}{input_names}{$value} ) ) {
            $value = $hash->{helper}{receiver}{input_names}{$value};
        }

        # Resolve device specific input alias
        $value =~ s/_/ /g;
        if (
            defined(
                $IOhash->{helper}{receiver}{device}{selectorlist}{selector}
            )
            && ref(
                $IOhash->{helper}{receiver}{device}{selectorlist}{selector} )
            eq "ARRAY"
          )
        {

            foreach my $input (
                @{ $IOhash->{helper}{receiver}{device}{selectorlist}{selector} }
              )
            {
                if (   $input->{value} eq "1"
                    && $input->{zone} ne "00"
                    && $input->{id} ne "80"
                    && $value eq trim( $input->{name} ) )
                {
                    $value = uc( $input->{id} );
                    last;
                }
            }
        }

    }

    # Resolve command and value to ISCP raw command
    my $cmd_raw = ONKYOdb::ONKYO_GetRemotecontrolCommand( $zone, $cmd );
    my $value_raw =
      ONKYOdb::ONKYO_GetRemotecontrolValue( $zone, $cmd_raw, $value );

    if ( !defined($cmd_raw) ) {
        Log3 $name, 4,
"ONKYO_AVR_ZONE $name: command '$cmd$value' is an unregistered command within zone$zone, be careful! Will be handled as raw command";
        $cmd_raw   = $cmd;
        $value_raw = $value;
    }
    elsif ( !defined($value_raw) ) {
        Log3 $name, 4,
"ONKYO_AVR_ZONE $name: $cmd - Warning, value '$value' not found in HASH table, will be sent to receiver 'as is'";
        $value_raw = $value;
    }

    Log3 $name, 4,
      "ONKYO_AVR_ZONE $name: snd $cmd -> $value ($cmd_raw$value_raw)";

    if ( $cmd_raw ne "" && $value_raw ne "" ) {
        IOWrite( $hash, $cmd_raw . $value_raw );
    }

    return;
}

###################################
sub ONKYO_AVR_ZONE_dec2hex($) {
    my ($dec) = @_;
    my $hex = uc( sprintf( "%x", $dec ) );

    return "0" . $hex if ( length($hex) eq 1 );
    return $hex;
}

###################################
sub ONKYO_AVR_ZONE_GetStateAV($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if ( ReadingsVal( $name, "presence", "absent" ) eq "absent" ) {
        return "absent";
    }
    elsif ( ReadingsVal( $name, "power", "off" ) eq "off" ) {
        return "off";
    }
    elsif ( ReadingsVal( $name, "mute", "off" ) eq "on" ) {
        return "muted";
    }
    elsif ( $hash->{INPUT} eq "2B"
        && ReadingsVal( $name, "playStatus", "stopped" ) ne "stopped" )
    {
        return ReadingsVal( $name, "playStatus", "stopped" );
    }
    else {
        return ReadingsVal( $name, "power", "off" );
    }
}

1;

=pod
=item device
=begin html

    <p>
      <a name="ONKYO_AVR_ZONE" id="ONKYO_AVR_ZONE"></a>
    </p>
    <h3>
      ONKYO_AVR_ZONE
    </h3>
    <ul>
      <a name="ONKYO_AVR_ZONEdefine" id="ONKYO_AVR_ZONEdefine"></a> <b>Define</b>
      <ul>
        <code>define &lt;name&gt; ONKYO_AVR_ZONE [&lt;zone-id&gt;]</code><br>
        <br>
        This is a supplement module for <a href="#ONKYO_AVR">ONKYO_AVR</a> representing zones.<br>
        <br>
        Example:<br>
        <ul>
          <code>
          define avr ONKYO_AVR_ZONE<br>
          <br>
          # For zone2<br>
          define avr ONKYO_AVR_ZONE 2<br>
          <br>
          # For zone3<br>
          define avr ONKYO_AVR_ZONE 3<br>
          <br>
          # For zone4<br>
          define avr ONKYO_AVR_ZONE 4
          </code>
        </ul>
      </ul><br>
      <br>
      <a name="ONKYO_AVRset" id="ONKYO_AVRset"></a> <b>Set</b>
      <ul>
        <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code><br>
        <br>
        Currently, the following commands are defined:<br>
        <ul>
          <li>
            <b>channel</b> &nbsp;&nbsp;-&nbsp;&nbsp; set active network service (e.g. Spotify)
          </li>
          <li>
            <b>input</b> &nbsp;&nbsp;-&nbsp;&nbsp; switches between inputs
          </li>
          <li>
            <b>mute</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; controls volume mute
          </li>
          <li>
            <b>muteT</b> &nbsp;&nbsp;-&nbsp;&nbsp; toggle mute state
          </li>
          <li>
            <b>next</b> &nbsp;&nbsp;-&nbsp;&nbsp; skip track
          </li>
          <li>
            <b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; turns the device in standby mode
          </li>
          <li>
            <b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; powers on the device
          </li>
          <li>
            <b>pause</b> &nbsp;&nbsp;-&nbsp;&nbsp; pause current playback
          </li>
          <li>
            <b>play</b> &nbsp;&nbsp;-&nbsp;&nbsp; start playback
          </li>
          <li>
            <b>power</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; set power mode
          </li>
          <li>
            <b>previous</b> &nbsp;&nbsp;-&nbsp;&nbsp; back to previous track
          </li>
          <li>
            <b>remoteControl</b> Send specific remoteControl command to device
          </li>
          <li>
            <b>repeat</b> off,all,all-folder,one &nbsp;&nbsp;-&nbsp;&nbsp; set repeat setting
          </li>
          <li>
            <b>repeatT</b> &nbsp;&nbsp;-&nbsp;&nbsp; toggle repeat state
          </li>
          <li>
            <b>shuffle</b> off,on,on-album,on-folder &nbsp;&nbsp;-&nbsp;&nbsp; set shuffle setting
          </li>
          <li>
            <b>shuffleT</b> &nbsp;&nbsp;-&nbsp;&nbsp; toggle shuffle state
          </li>
          <li>
            <b>sleep</b> 1..90,off &nbsp;&nbsp;-&nbsp;&nbsp; sets auto-turnoff after X minutes
          </li>
          <li>
            <b>stop</b> &nbsp;&nbsp;-&nbsp;&nbsp; stop current playback
          </li>
          <li>
            <b>toggle</b> &nbsp;&nbsp;-&nbsp;&nbsp; switch between on and off
          </li>
          <li>
            <b>volume</b> 0...100 &nbsp;&nbsp;-&nbsp;&nbsp; set the volume level in percentage
          </li>
          <li>
            <b>volumeUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; increases the volume level
          </li>
          <li>
            <b>volumeDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; decreases the volume level
          </li>
        </ul>
        <ul>
        <br>
        Other set commands may appear dynamically based on previously used "get avr remoteControl"-commands and resulting readings.<br>
        See "get avr remoteControl &lt;Set-name&gt; help" to get more information about possible readings and set values.
        </ul>
      </ul><br>
      <br>
      <a name="ONKYO_AVRget" id="ONKYO_AVRget"></a> <b>Get</b>
      <ul>
        <code>get &lt;name&gt; &lt;what&gt;</code><br>
        <br>
        Currently, the following commands are defined:<br>
        <br>
        <ul>
          <li>
            <b>createZone</b> &nbsp;&nbsp;-&nbsp;&nbsp; creates a separate <a href="#ONKYO_AVR_ZONE">ONKYO_AVR_ZONE</a> device for available zones of the device
          </li>
          <li>
            <b>remoteControl</b> &nbsp;&nbsp;-&nbsp;&nbsp; sends advanced remote control commands based on current zone; you may use "get avr remoteControl &lt;Get-command&gt; help" to see details about possible values and resulting readings. In Case the device does not support the command, just nothing happens as normally the device does not send any response. In case the command is temporarily not available you may see according feedback from the log file using attribute verbose=4.
          </li>
          <li>
            <b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; clears cached settings and re-reads device XML configurations
          </li>
        </ul>
      </ul><br>
      <br>
      <b>Generated Readings/Events:</b><br>
      <ul>
        <li>
          <b>channel</b> - Shows current network service name when (e.g. streaming services like Spotify); part of FHEM-4-AV-Devices compatibility
        </li>
        <li>
          <b>currentAlbum</b> - Shows current Album information; part of FHEM-4-AV-Devices compatibility
        </li>
        <li>
          <b>currentArtist</b> - Shows current Artist information; part of FHEM-4-AV-Devices compatibility
        </li>
        <li>
          <b>currentMedia</b> - currently no in use
        </li>
        <li>
          <b>currentTitle</b> - Shows current Title information; part of FHEM-4-AV-Devices compatibility
        </li>
        <li>
          <b>currentTrack*</b> - Shows current track timer information; part of FHEM-4-AV-Devices compatibility
        </li>
        <li>
          <b>input</b> - Shows currently used input; part of FHEM-4-AV-Devices compatibility
        </li>
        <li>
          <b>mute</b> - Reports the mute status of the device (can be "on" or "off")
        </li>
        <li>
          <b>playStatus</b> - Shows current network service playback status; part of FHEM-4-AV-Devices compatibility
        </li>
        <li>
          <b>power</b> - Reports the power status of the device (can be "on" or "off")
        </li>
        <li>
          <b>presence</b> - Reports the presence status of the receiver (can be "absent" or "present"). In case of an absent device, control is not possible.
        </li>
        <li>
          <b>repeat</b> - Shows current network service repeat status; part of FHEM-4-AV-Devices compatibility
        </li>
        <li>
          <b>shuffle</b> - Shows current network service shuffle status; part of FHEM-4-AV-Devices compatibility
        </li>
        <li>
          <b>state</b> - Reports current network connection status to the device
        </li>
        <li>
          <b>stateAV</b> - Zone status from user perspective combining readings presence, power, mute and playStatus to a useful overall status.
        </li>
        <li>
          <b>volume</b> - Reports current volume level of the receiver in percentage values (between 0 and 100 %)
        </li>
      </ul>
        <br>
        Using remoteControl get-command might result in creating new readings in case the device sends any data.<br>
    </ul>

=end html

=begin html_DE

    <p>
      <a name="ONKYO_AVR_ZONE" id="ONKYO_AVR_ZONE"></a>
    </p>
    <h3>
      ONKYO_AVR_ZONE
    </h3>
    <ul>
      Eine deutsche Version der Dokumentation ist derzeit nicht vorhanden. Die englische Version ist hier zu finden:
    </ul>
    <ul>
      <a href='http://fhem.de/commandref.html#ONKYO_AVR_ZONE'>ONKYO_AVR_ZONE</a>
    </ul>

=end html_DE

=cut