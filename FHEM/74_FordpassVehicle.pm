###############################################################################
#
# Developed with eclipse on windows os using fiddler to catch ip communication.
#
#  (c) 2019 Copyright: J.K. (J0EK3R at gmx dot net)
#  All rights reserved
#
#  Special thanks goes to committers:
#  * me
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
# $Id: 74_FordpassVehicle.pm 201 2020-04-04 06:14:00Z J0EK3R $
#
###############################################################################

package main;

my $VERSION = "1.0.1";

use strict;
use warnings;

my $missingModul = "";

use FHEM::Meta;
use Date::Parse;
use Time::Local;
use Time::HiRes qw(gettimeofday);
eval {use JSON;1 or $missingModul .= "JSON "};

#########################
# Forward declaration
sub FordpassVehicle_Initialize($);
sub FordpassVehicle_Define($$);
sub FordpassVehicle_Ready($);
sub FordpassVehicle_Undef($$);
sub FordpassVehicle_Delete($$);
sub FordpassVehicle_Rename($$);
sub FordpassVehicle_Attr(@);
sub FordpassVehicle_Notify($$);
sub FordpassVehicle_Set($@);
sub FordpassVehicle_Parse($$);

sub FordpassVehicle_Upgrade($);
sub FordpassVehicle_UpdateInternals($);

sub FordpassVehicle_TimerExecute($);
sub FordpassVehicle_TimerRemove($);

sub FordpassVehicle_IOWrite($$);

sub FordpassVehicle_Update($);
sub FordpassVehicle_GetDetails($;$$);
sub FordpassVehicle_GetStatusV2($;$$);
sub FordpassVehicle_GetStatusV4($;$$);
sub FordpassVehicle_GetCapability($;$$);
sub FordpassVehicle_GetFuelConsumptionInfo($;$$);
sub FordpassVehicle_GetRecalls($;$$);

sub FordpassVehicle_SetCommandDoor($$;$$);

sub FordpassVehicle_GetApplianceCommand($;$$);
sub FordpassVehicle_SetCommand($$$;$$);

sub FordpassVehicle_RefreshReadingsFromObject($$$);

sub FordpassVehicle_Store($$$$);
sub FordpassVehicle_Restore($$$$);
sub FordpassVehicle_StoreRename($$$$);

sub FordpassVehicle_GetLTZFromUTC($);

#########################
# Constants

my $GetLoopDataInterval                = 1;     # interval of the data-get-timer

my $Vehicle_DefaultIntervalSlow        = 60 * 1; # default value for the slow polling interval in seconds
my $Vehicle_DefaultIntervalFast        = 30 * 1; # default value for the fast polling interval in seconds

my $Vehicle_DefaultStateFormat         = ""; # State: state<br/>Valve: CmdValveState<br/>Consumption: TodayWaterConsumption l<br/>Temperature: LastTemperature Grad C<br/>Pressure: LastPressure bar";
my $Vehicle_DefaultWebCmdFormat        = "update";

my $API_URL     = 'https://usapi.cv.ford.com/api';  # US Connected Vehicle api
my $VEHICLE_URL = 'https://services.cx.ford.com/api';
my $USER_URL    = 'https://api.mps.ford.com/api';
my $TOKEN_URL   = 'https://sso.ci.ford.com/oidc/endpoint/default/token';

my $TimeStampFormat   = "%Y-%m-%dT%H:%M:%S";
my $DefaultSeperator  = "_";
my $DebugMarker       = "Dbg";
my $TimestampMarker   = "_Timestamp";

my %replacechartable = ("?" => "ae", "?" => "Ae", "?" => "ue", "?" => "Ue", "?" => "oe", "?" => "Oe", "?" => "ss" );
my $replacechartablekeys = join ("|", keys(%replacechartable));

# AttributeList for all types of FordpassVehicle 
my $FordpassVehicle_AttrList = 
    "debug:0,1 " . 
    "debugJSON:0,1 " . 
    "disable:0,1 " . 
    "intervalslow " .
    "intervalfast " .
    "refreshSatusMode:ignitionOn,never,always " .
    "showTimestamps:0,1 " .
    "genericReadings:none,valid,full " . 
    ""; 

#####################################
# FordpassVehicle_Initialize( $hash )
sub FordpassVehicle_Initialize($)
{
  my ( $hash ) = @_;

  $hash->{DefFn}    = \&FordpassVehicle_Define;
  $hash->{UndefFn}  = \&FordpassVehicle_Undef;
  $hash->{DeleteFn} = \&FordpassVehicle_Delete;
  $hash->{RenameFn} = \&FordpassVehicle_Rename;
  $hash->{AttrFn}   = \&FordpassVehicle_Attr;
  $hash->{NotifyFn} = \&FordpassVehicle_Notify;
  $hash->{SetFn}    = \&FordpassVehicle_Set;
  $hash->{ParseFn}  = \&FordpassVehicle_Parse;

  $hash->{Match} = "^FORDPASSVEHICLE_.*";
  
  # list of attributes has changed from V2 -> V3
  # -> the redefinition is done automatically
  # old attribute list is set to be able to get the deprecated attribute values
  # on global event "INITIALIZED" the new attribute list is set 
  $hash->{AttrList} = 
    $FordpassVehicle_AttrList . 
    $readingFnAttributes;

  foreach my $d ( sort keys %{ $modules{FordpassVehicle}{defptr} } )
  {
    my $hash = $modules{FordpassVehicle}{defptr}{$d};
    $hash->{VERSION} = $VERSION;
  }

  return FHEM::Meta::InitMod( __FILE__, $hash );
}

#####################################
# FordpassVehicle_Define( $hash, $def )
sub FordpassVehicle_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);

  return $@
    unless(FHEM::Meta::SetInternals($hash));

  return "wrong number of parameters: define <NAME> FordpassVehicle <FORDPASSACCOUNT> <VEHICLEID>"
    if ( @a != 4 );

  return "Cannot define FordpassVehicle. Perl modul $missingModul is missing."
    if($missingModul);

  # set marker to prevent actions while define is running
  $hash->{helper}{DefineRunning} = "Running";

  my $name;
  my $bridge = undef;
  my $vehicleId;

  if(@a == 4)
  {
    $name       = $a[0];
    $bridge     = $a[2];
    $vehicleId  = $a[3];
  }
  else
  {
    return "wrong number of parameters: define <NAME> FordpassVehicle <bridge> <vehicleId>"
  }

  # the SenseGuard devices update every 15 minutes
  $hash->{".DEFAULTINTERVALSLOW"} = $Vehicle_DefaultIntervalSlow;
  $hash->{".DEFAULTINTERVALFAST"} = $Vehicle_DefaultIntervalFast;
  $hash->{".AttrList"} =
    $FordpassVehicle_AttrList . 
    $readingFnAttributes;

  $hash->{helper}{Telegram_GetDetailsCounter}   = 0;
  $hash->{helper}{Telegram_GetStatusV2Counter}  = 0;
  $hash->{helper}{Telegram_GetStatusV4Counter}  = 0;
  $hash->{helper}{Telegram_SetCommandCounter}   = 0;

  if($init_done)
  {
    # device is created *after* fhem has started -> don't restore old values
    Log3($name, 5, "FordpassVehicle_Define($name) - device is created after fhem has started -> don't restore old values");
  }
  else
  {
    # device is created *while* fhem is starting -> restore old values
    Log3($name, 5, "FordpassVehicle_Define($name) - device is created while fhem is starting -> restore old values");

#    $hash->{helper}{GetSuspendReadings}                     = FordpassVehicle_Restore( $hash, "FordpassVehicle_Define", "GetSuspendReadings", $hash->{helper}{GetSuspendReadings});
#    $hash->{helper}{LastProcessedWithdrawalTimestamp_LUTC}  = FordpassVehicle_Restore( $hash, "FordpassVehicle_Define", "LastProcessedWithdrawalTimestamp_LUTC", $hash->{helper}{LastProcessedWithdrawalTimestamp_LUTC});
#    $hash->{helper}{LastProcessedTimestamp_LUTC}            = FordpassVehicle_Restore( $hash, "FordpassVehicle_Define", "LastProcessedTimestamp_LUTC", $hash->{helper}{LastProcessedTimestamp_LUTC});
  }
  
  $hash->{VEHICLEID}                  = $vehicleId;
  $hash->{VERSION}                    = $VERSION;
  $hash->{NOTIFYDEV}                  = "global,$name,$bridge";
  $hash->{RETRIES}                    = 3;
  $hash->{DataTimerIntervalSlow}      = $hash->{".DEFAULTINTERVALSLOW"};
  $hash->{DataTimerIntervalFast}      = $hash->{".DEFAULTINTERVALFAST"};
  $hash->{helper}{DEBUG}              = "0";
  $hash->{helper}{IsDisabled}         = "0";
  $hash->{helper}{GenericReadings}    = "none";
  $hash->{helper}{ShowTimestamps}     = "0";
  $hash->{helper}{RefreshStatusMode}  = "ignitionOn";
  $hash->{helper}{IgnitionStatus}     = "Unknown";

  AssignIoPort($hash, $bridge);

  my $iodev = $hash->{IODev}->{NAME};

  my $d = $modules{FordpassVehicle}{defptr}{$vehicleId};

  return "FordpassVehicle device $name on FordpassAccount $iodev already defined."
    if(defined($d) and 
      $d->{IODev} == $hash->{IODev} and 
      $d->{NAME} ne $name);

  # ensure attribute stateformat is present
  if(AttrVal($name, "stateFormat", "none") eq "none" and
    $Vehicle_DefaultStateFormat ne "")
  {
    CommandAttr(undef, $name . " stateFormat " . $Vehicle_DefaultStateFormat)
  }

  # ensure attribute webcmd is present
  if(AttrVal($name, "webCmd", "none") eq "none" and
    $Vehicle_DefaultWebCmdFormat ne "")
  {
    CommandAttr(undef, $name . " webCmd " . $Vehicle_DefaultWebCmdFormat)
  }
  
  # ensure attribute room is present
  if(AttrVal($name, "room", "none") eq "none")
  {
    my $room = AttrVal($iodev, "room", "Fordpass");
    CommandAttr(undef, $name . " room " . $room);
  }
  
  # ensure attribute inerval is present
  if(AttrVal($name, "interval", "none") eq "none")
  {
    CommandAttr(undef, $name . " interval " . $hash->{DataTimerIntervalSlow})
  }

  Log3($name, 3, "FordpassVehicle_Define($name) - defined FordpassVehicle with DEVICEID: $vehicleId");

  readingsSingleUpdate($hash, "state", "initialized", 1);

  $modules{FordpassVehicle}{defptr}{$vehicleId} = $hash;

  # remove marker value
  $hash->{helper}{DefineRunning} = undef;

  return undef;
}

####################################
# FordpassVehicle_Ready( $hash )
sub FordpassVehicle_Ready($)
{
  my ($hash)  = @_;
  my $name    = $hash->{NAME};

  Log3($name, 4, "FordpassVehicle_Ready($name)");

  FordpassVehicle_Upgrade($hash);
}

#####################################
# FordpassVehicle_Undef( $hash, $arg )
sub FordpassVehicle_Undef($$)
{
  my ( $hash, $arg ) = @_;
  my $name      = $hash->{NAME};
  my $vehicleId = $hash->{VEHICLEID};

  Log3($name, 4, "FordpassVehicle_Undef($name)");

  FordpassVehicle_TimerRemove($hash);

  delete $modules{FordpassVehicle}{defptr}{$vehicleId};

  return undef;
}

#####################################
# FordpassVehicle_Delete( $hash, $name )
sub FordpassVehicle_Delete($$)
{
  my ( $hash, $name ) = @_;

  Log3($name, 4, "FordpassVehicle_Delete($name)");

  # delete all stored values
#  FordpassVehicle_Store($hash, "FordpassVehicle_Delete", "LastProcessedTimestamp_LUTC", undef);
#  FordpassVehicle_Store($hash, "FordpassVehicle_Delete", "LastProcessedWithdrawalTimestamp_LUTC", undef);
  
  return undef;
}

#####################################
# FordpassVehicle_Rename($new_name, $old_name)
sub FordpassVehicle_Rename($$)
{
  my ($new_name, $old_name) = @_;
  my $hash = $defs{$new_name};
  my $name = $hash->{NAME};

  Log3($name, 4, "FordpassVehicle_Rename($name)");

  # rename all stored values
#  FordpassVehicle_StoreRename($hash, "FordpassVehicle_Rename", $old_name, "LastProcessedTimestamp_LUTC");
#  FordpassVehicle_StoreRename($hash, "FordpassVehicle_Rename", $old_name, "LastProcessedWithdrawalTimestamp_LUTC");

  return undef;
}

#####################################
# FordpassVehicle_Attr( $cmd, $name, $attrName, $attrVal )
sub FordpassVehicle_Attr(@)
{
  my ( $cmd, $name, $attrName, $attrVal ) = @_;
  my $hash = $defs{$name};

  Log3($name, 4, "FordpassVehicle_Attr($name) - $attrName was called");

  # Attribute "disable"
  if($attrName eq "disable")
  {
    if($cmd eq "set" and 
      $attrVal eq "1" )
    {
      $hash->{helper}{IsDisabled} = "1";

      FordpassVehicle_TimerRemove($hash);
      FordpassVehicle_GetData_TimerRemove($hash);

      readingsSingleUpdate( $hash, "state", "inactive", 1 );
      Log3($name, 3, "FordpassVehicle($name) - disabled");
    } 
    else
    {
      $hash->{helper}{IsDisabled} = "0";

      readingsSingleUpdate( $hash, "state", "active", 1 );

      FordpassVehicle_TimerExecute($hash)
        if($init_done and
          not $hash->{helper}{DefineRunning});
          
      Log3($name, 3, "FordpassVehicle($name) - enabled");
    }
  }

  # Attribute "genericReadings"
  elsif($attrName eq "genericReadings")
  {
    if($cmd eq "set" and 
      ($attrVal eq "valid" or $attrVal eq "full"))
    {
      $hash->{helper}{GenericReadings} = $attrVal;

      Log3($name, 3, "FordpassVehicle_Attr($name) - set genericReadings: $attrVal");
    } 
    else
    {
      $hash->{helper}{GenericReadings} = "none";

      Log3($name, 3, "FordpassVehicle_Attr($name) - set genericReadings: none");
    }
    FordpassVehicle_UpdateInternals($hash);
  }

  # Attribute "showTimestamps"
  elsif($attrName eq "showTimestamps")
  {
    if($cmd eq "set")
    {
      $hash->{helper}{ShowTimestamps} = "$attrVal";

      Log3($name, 3, "FordpassVehicle_Attr($name) - set showTimestamps: $attrVal");
    } 
    else
    {
      $hash->{helper}{ShowTimestamps} = "0";

      Log3($name, 3, "FordpassVehicle_Attr($name) - set showTimestamps: none");
    }
    FordpassVehicle_UpdateInternals($hash);
  }

  # Attribute "refreshSatusMode"
  elsif($attrName eq "refreshSatusMode")
  {
    if($cmd eq "set")
    {
      $hash->{helper}{RefreshStatusMode} = $attrVal;

      Log3($name, 3, "FordpassVehicle_Attr($name) - set mode: $attrVal");
    } 
    else
    {
      $hash->{helper}{RefreshStatusMode} = "never";

      Log3($name, 3, "FordpassVehicle_Attr($name) - set genericReadings: default");
    }
    FordpassVehicle_UpdateInternals($hash);
  }

  # Attribute "intervalslow"
  elsif($attrName eq "intervalslow")
  {
    # onchange event for attribute "intervalslow" is handled in sub "Notify" -> calls "updateValues" -> Timer is reloaded
    if($cmd eq "set")
    {
      return "Interval must be greater than 0"
        unless($attrVal > 0);

      $hash->{DataTimerIntervalSlow} = $attrVal;

      Log3($name, 3, "FordpassVehicle_Attr($name) - set interval: $attrVal");
    } 
    elsif($cmd eq "del")
    {
      $hash->{DataTimerIntervalSlow} = $hash->{".DEFAULTINTERVALSLOW"};

      Log3($name, 3, "FordpassVehicle_Attr($name) - delete interval and set default: 60");
    }

    FordpassVehicle_TimerExecute($hash)
      if($init_done and
        not $hash->{helper}{DefineRunning});
  }

  # Attribute "intervalfast"
  elsif($attrName eq "intervalfast")
  {
    # onchange event for attribute "intervalfast" is handled in sub "Notify" -> calls "updateValues" -> Timer is reloaded
    if($cmd eq "set")
    {
      return "Interval must be greater than 0"
        unless($attrVal > 0);

      $hash->{DataTimerIntervalFast} = $attrVal;

      Log3($name, 3, "FordpassVehicle_Attr($name) - set interval: $attrVal");
    } 
    elsif($cmd eq "del")
    {
      $hash->{DataTimerIntervalFast} = $hash->{".DEFAULTINTERVALFAST"};

      Log3($name, 3, "FordpassVehicle_Attr($name) - delete interval and set default: 60");
    }

    FordpassVehicle_TimerExecute($hash)
      if($init_done and
        not $hash->{helper}{DefineRunning});
  }

  # Attribute "debug"
  elsif($attrName eq "debug")
  {
    if($cmd eq "set")
    {
      Log3($name, 3, "FordpassAccount_Attr($name) - debugging enabled");

      $hash->{helper}{DEBUG} = "$attrVal";
      FordpassVehicle_UpdateInternals($hash);
    } 
    elsif($cmd eq "del")
    {
      Log3($name, 3, "FordpassAccount_Attr($name) - debugging disabled");

      $hash->{helper}{DEBUG} = "0";
      FordpassVehicle_UpdateInternals($hash);
    }
  }

  return undef;
}

#####################################
# FordpassVehicle_Notify( $hash, $dev )
sub FordpassVehicle_Notify($$)
{
  my ($hash, $dev)  = @_;
  my $name          = $hash->{NAME};

  return
    if($hash->{helper}{IsDisabled} ne "0");

  my $devname = $dev->{NAME};
  my $devtype = $dev->{TYPE};
  my $events  = deviceEvents( $dev, 1 );

  return
    if(!$events);

  Log3($name, 4, "FordpassVehicle_Notify($name) - DevType: \"$devtype\"");

  # process "global" events
  if($devtype eq "Global")
  {
    if (grep(m/^INITIALIZED$/, @{$events}))
    {
      # this is the initial call after fhem has startet
      Log3($name, 3, "FordpassVehicle_Notify($name) - INITIALIZED");

      FordpassVehicle_Ready($hash);
    }

    elsif (grep(m/^REREADCFG$/, @{$events}))
    {
      Log3($name, 3, "FordpassVehicle_Notify($name) - REREADCFG");

      FordpassVehicle_Ready($hash);
    }

    elsif (grep(m/^DEFINED.$name$/, @{$events}) )
    {
      Log3($name, 3, "FordpassVehicle_Notify($name) - DEFINED");
    }

    elsif (grep(m/^MODIFIED.$name$/, @{$events}))
    {
      Log3($name, 3, "FordpassVehicle_Notify($name) - MODIFIED");
    }

    if ($init_done)
    {
    }
  }
  
  # process events from Bridge
  elsif( $devtype eq "FordpassAccount" )
  {
    if(grep /^state:.*$/, @{$events})
    {
      my $ioDeviceState = ReadingsVal($hash->{IODev}->{NAME}, "state", "none");
      
      Log3($name, 4, "FordpassVehicle_Notify($name) - event \"state: $ioDeviceState\" from FordpassAccount was catched");

      if($ioDeviceState eq "connected to cloud")
      {
      }
      else
      {
        readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged($hash, "state", "bridge " . $ioDeviceState, 1);
        readingsEndUpdate($hash, 1);
      }
    }
    else
    {
      Log3($name, 4, "FordpassVehicle_Notify($name) - event from FordpassAccount was catched");
    }
  }
  
  # process internal events
  elsif($devtype eq "FordpassVehicle")
  {
  }

  return;
}

#####################################
# FordpassVehicle_Set( $hash, $name, $cmd, @args )
sub FordpassVehicle_Set($@)
{
  my ( $hash, $name, $cmd, @args ) = @_;

  Log3($name, 4, "FordpassVehicle_Set($name) - cmd= $cmd");

  ### Command "update"
  if( lc $cmd eq lc "update" )
  {
    FordpassVehicle_Update($hash);
    return;
  }
  ### Command "refreshStatus"
  elsif( lc $cmd eq lc "refreshStatus" )
  {
    FordpassVehicle_RefreshStatusV2($hash);
    return;
  }
  ### Command "clearreadings"
  elsif( lc $cmd eq lc "clearreadings" )
  {
    return "usage: $cmd <mask>"
      if ( @args != 1 );

    my $mask = $args[0];
    fhem("deletereading $name $mask", 1);
    return;
  }
  ### Command "engine"
  elsif( lc $cmd eq lc "engine" )
  {
    # parameter is "start" or "stop" so convert to "true" : "false"
    my $onoff = lc join(" ", @args ) eq lc "start" ? "true" : "false";

    FordpassVehicle_SetCommand($hash, "engine/start", $onoff);
    return;
  }
  ### Command "door"
  elsif( lc $cmd eq lc "door" )
  {
    # parameter is "lock" or "unlock" so convert to "true" : "false"
    my $onoff = lc join(" ", @args ) eq lc "lock" ? "true" : "false";

    FordpassVehicle_SetCommand($hash, "doors/lock", $onoff);
    return;
  }
  ### unknown Command
  else
  {
    my $list = "";
    $list .= "update:noArg ";
    $list .= "refreshStatus:noArg ";

    $list .= "engine:start,stop "
      if(defined($hash->{Capability_RemoteStart}) and 
        $hash->{Capability_RemoteStart} eq "True" or
        $hash->{helper}{DEBUG} eq "1");

    $list .= "door:lock,unlock "
      if(defined($hash->{Capability_RemoteLock}) and
        $hash->{Capability_RemoteLock} or
        $hash->{helper}{DEBUG} eq "1");

    $list .= "clearreadings:$DebugMarker.*,.*.$TimestampMarker,.* ";

    return "Unknown argument $cmd, choose one of $list";
  }
}

#####################################
# FordpassVehicle_Parse( $io_hash, $match )
sub FordpassVehicle_Parse($$)
{
  my ($io_hash, $match) = @_;
  my $io_name = $io_hash->{NAME};

  # to pass parameters to this underlying logical device
  # the hash "currentVehicle" is set in io_hash for the moment
  my $current_vehicle       = $io_hash->{currentVehicle};
  my $current_vehicle_id    = $current_vehicle->{vehicleId};
  my $current_name          = $current_vehicle->{name};
  my $autocreate            = $current_vehicle->{autocreate};

  # replace "umlaute"
  $current_name =~ s/($replacechartablekeys)/$replacechartable{$1}/g;

  Log3($io_name, 4, "FordpassAccount($io_name) -> FordpassVehicle_Parse");

  if(defined($current_vehicle_id))
  {
    # Vehicle with $deviceId found:
    if(my $hash = $modules{FordpassVehicle}{defptr}{$current_vehicle_id})
    {
      my $name = $hash->{NAME};

      Log3($name, 5, "FordpassVehicle_Parse($name) - found logical device");

      # set capabilities
      $hash->{Capability_TCU}                     = "$current_vehicle->{vehicleDetails}->{tcuEnabled}" eq "1" ? "True" : "False"; 
      $hash->{Capability_CssConnectivity}         = "$current_vehicle->{vehicleCapabilities}->{ccsConnectivity}" eq "On" ? "True" : "False"; 
      $hash->{Capability_CssLocation}             = "$current_vehicle->{vehicleCapabilities}->{ccsLocation}" eq "On" ? "True" : "False";
      $hash->{Capability_CssVehicleData}          = "$current_vehicle->{vehicleCapabilities}->{ccsVehicleData}" eq "On" ? "True" : "False";
      $hash->{Capability_OilLife}                 = "$current_vehicle->{vehicleCapabilities}->{oilLife}" eq "Display" ? "True" : "False";
      $hash->{Capability_TirePressureMonitoring}  = "$current_vehicle->{vehicleCapabilities}->{tirePressureMonitoring}" eq "Display" ? "True" : "False";
      $hash->{Capability_WifiHotspot}             = "$current_vehicle->{vehicleCapabilities}->{wifiHotspot}" eq "Display" ? "True" : "False";
      $hash->{Capability_RemoteLock}              = "$current_vehicle->{vehicleCapabilities}->{remoteLock}" eq "Display" ? "True" : "False";
      $hash->{Capability_RemoteStart}             = "$current_vehicle->{vehicleCapabilities}->{remoteStart}" eq "Display" ? "True" : "False";
      $hash->{Capability_RemoteWindow}            = "$current_vehicle->{vehicleCapabilities}->{remoteWindowCapability}" eq "Display" ? "True" : "False";

      readingsBeginUpdate($hash);
      # change state to "connected to cloud" -> Notify -> load timer
      readingsBulkUpdateIfChanged($hash, "state", "connected to cloud", 1 );

      if($hash->{helper}{GenericReadings} ne "none")
      {
        FordpassVehicle_RefreshReadingsFromObject($hash, $DebugMarker . $DefaultSeperator . "Vehicle", $current_vehicle);
      }
      
      readingsEndUpdate($hash, 1);
      
      # if not timer is running then start one
      if(not defined($hash->{DataTimerNext}) or
        $hash->{DataTimerNext} eq "none")
      {
        FordpassVehicle_TimerExecute($hash);
      }

      return $name;
    }

    # Vehicle not found, create new one
    elsif($autocreate eq "1")
    {
      my $deviceName = makeDeviceName($current_name);
      
      Log3($io_name, 3, "FordpassAccount($io_name) -> autocreate new device $deviceName with vehicleId $current_vehicle_id");

      return "UNDEFINED $deviceName FordpassVehicle $io_name $current_vehicle_id";
    }
  }
}

##################################
# FordpassVehicle_Upgrade( $hash )
sub FordpassVehicle_Upgrade($)
{
  my ( $hash ) = @_;
  my $name = $hash->{NAME};
}

#####################################
# FordpassVehicle_UpdateInternals( $hash )
# This methode copies values from $hash-{helper} to visible internals 
sub FordpassVehicle_UpdateInternals($)
{
  my ( $hash ) = @_;
  my $name  = $hash->{NAME};

  Log3($name, 5, "FordpassVehicle_UpdateInternals($name)");

  # debug-internals
  if($hash->{helper}{DEBUG} eq "1")
  {
    $hash->{DEBUG_IsDisabled}         = $hash->{helper}{IsDisabled};
    $hash->{DEBUG_GenericReadings}    = $hash->{helper}{GenericReadings};
    $hash->{DEBUG_ShowTimestamps}     = $hash->{helper}{ShowTimestamps};
    $hash->{DEBUG_RefreshStatusMode}  = $hash->{helper}{RefreshStatusMode};
    $hash->{DEBUG_IgnitionStatus}     = $hash->{helper}{IgnitionStatus};
    
    my @retrystring_keys =  grep /Telegram_/, keys %{$hash->{helper}};
    foreach (@retrystring_keys)
    {
      $hash->{"DEBUG_" . $_} = $hash->{helper}{$_};
    }
  }
  else
  {
    # delete all keys starting with "DEBUG_"
    my @matching_keys =  grep /DEBUG_/, keys %$hash;
    foreach (@matching_keys)
    {
      delete $hash->{$_};
    }
  }
}

##################################
# FordpassVehicle_TimerExecute( $hash )
sub FordpassVehicle_TimerExecute($)
{
  my ( $hash )  = @_;
  my $name      = $hash->{NAME};

  FordpassVehicle_TimerRemove($hash);

  if($init_done and 
    $hash->{helper}{IsDisabled} eq "0" )
  {
    Log3($name, 4, "FordpassVehicle_TimerExecute($name)");

    FordpassVehicle_Update($hash);

    # if ignition ist "on" then wait "fast" interval for next call else "slow"
    my $interval = $hash->{helper}{IgnitionStatus} eq "1" ?
      $hash->{DataTimerIntervalFast} : 
      $hash->{DataTimerIntervalSlow};
  
    # reload timer
    my $nextTimer = gettimeofday() + $interval;
    $hash->{DataTimerNext} = strftime($TimeStampFormat, localtime($nextTimer));
    InternalTimer($nextTimer, "FordpassVehicle_TimerExecute", $hash);
  } 
  else
  {
    readingsSingleUpdate($hash, "state", "disabled", 1);

    Log3($name, 4, "FordpassVehicle_TimerExecute($name) - device is disabled");
  }
}

##################################
# FordpassVehicle_TimerRemove( $hash )
sub FordpassVehicle_TimerRemove($)
{
  my ( $hash ) = @_;
  my $name = $hash->{NAME};

  Log3($name, 4, "FordpassVehicle_TimerRemove($name)");

  $hash->{DataTimerNext} = "none";
  RemoveInternalTimer($hash, "FordpassVehicle_TimerExecute");
}

##################################
# FordpassVehicle_IOWrite( $hash, $param )
sub FordpassVehicle_IOWrite($$)
{
  my ($hash, $param) = @_;
  my $name = $hash->{NAME};

  Log3($name, 4, "FordpassVehicle_IOWrite($name)");

  IOWrite($hash, $param);
}

##################################
# FordpassVehicle_Update( $hash )
sub FordpassVehicle_Update($)
{
  my ( $hash ) = @_;
  my $name     = $hash->{NAME};

  if($hash->{Capability_TCU} eq "True")
  {
    Log3($name, 4, "FordpassVehicle_Update($name)");

    if(($hash->{helper}{RefreshStatusMode} eq "always") ||
      ($hash->{helper}{RefreshStatusMode} eq "ignitionOn" && $hash->{helper}{IgnitionStatus} eq "1"))
    {
      # serial call:
      #my $getRecalls              = sub { FordpassVehicle_GetRecalls($hash); };
      my $getFuelConsumptionInfo  = sub { FordpassVehicle_GetFuelConsumptionInfo($hash); };
#      my $getCapability           = sub { FordpassVehicle_GetCapability($hash, $getFuelConsumptionInfo); };
#      my $getStateV4              = sub { FordpassVehicle_GetStatusV4($hash, $getCapability); };
      my $getStateV4              = sub { FordpassVehicle_GetStatusV4($hash, $getFuelConsumptionInfo); };
      my $getStateV2              = sub { FordpassVehicle_GetStatusV2($hash, $getStateV4); };
      my $refreshStateV2          = sub { FordpassVehicle_RefreshStatusV2($hash, $getStateV2); };
      my $getDetails              = sub { FordpassVehicle_GetDetails($hash, $refreshStateV2); };
      $getDetails->();
    }
    else
    {
      #my $getRecalls              = sub { FordpassVehicle_GetRecalls($hash); };
      my $getFuelConsumptionInfo  = sub { FordpassVehicle_GetFuelConsumptionInfo($hash); };
#      my $getCapability           = sub { FordpassVehicle_GetCapability($hash, $getFuelConsumptionInfo); };
#      my $getStateV4              = sub { FordpassVehicle_GetStatusV4($hash, $getCapability); };
      my $getStateV4              = sub { FordpassVehicle_GetStatusV4($hash, $getFuelConsumptionInfo); };
      my $getStateV2              = sub { FordpassVehicle_GetStatusV2($hash, $getStateV4); };
      #my $refreshStateV2          = sub { FordpassVehicle_RefreshStatusV2($hash, $getStateV2); };
      my $getDetails              = sub { FordpassVehicle_GetDetails($hash, $getStateV2); };
      $getDetails->();
    }
  }
  else
  {
    Log3($name, 5, "FordpassVehicle_Update($name) - Capability_TCU is False");
  }
}

##################################
# FordpassVehicle_GetDetails( $hash, $callbackSuccess, $callbackFail )
sub FordpassVehicle_GetDetails($;$$)
{
  my ( $hash, $callbackSuccess, $callbackFail ) = @_;
  my $name    = $hash->{NAME};

  # definition of the lambda function wich is called to process received data
  my $resultCallback = sub 
  {
    my ( $callbackparam, $data, $errorMsg ) = @_;

    my $stopwatch = gettimeofday();
    $hash->{helper}{Telegram_GetDetailsTimeRequest} = $stopwatch - $callbackparam->{timestampStart};
    $hash->{helper}{Telegram_GetDetailsCallback}    = strftime($TimeStampFormat, localtime($stopwatch));
    Log3($name, 4, "FordpassVehicle_GetDetails($name) - resultCallback");

    if( $errorMsg eq "" )
    {
      my $decode_json = eval { decode_json($data) };
    
      if($@)
      {
        Log3($name, 3, "FordpassVehicle_GetDetails($name) - JSON error while request: $@");

        if( AttrVal( $name, "debugJSON", 0 ) == 1 )
        {
          readingsBeginUpdate($hash);
          readingsBulkUpdate( $hash, "JSON_ERROR", $@, 1 );
          readingsBulkUpdate( $hash, "JSON_ERROR_STRING", "\"" . $data . "\"", 1 );
          readingsEndUpdate($hash, 1);
        }
        $errorMsg = "GetDetails: JSON_ERROR";
      }
      else
      {
        readingsBeginUpdate($hash);
        if($hash->{helper}{GenericReadings} ne "none")
        {
          FordpassVehicle_RefreshReadingsFromObject($hash, $DebugMarker . $DefaultSeperator . "Vehicle", $decode_json);
        }
        
        #  {
        #    "vehicle":
        #    {
        #      "vin":"xxxxxxxxxxxxxxxxx",
        #      "nickName":"Flitzer",
        #      "vehicleType":"2019 Focus",
        #      "color":"ABSOLUTE BLACK",
        #      "modelName":"Focus",
        #      "modelCode":"VLGE",
        #      "modelYear":"2019",
        #      "tcuEnabled":1,
        #      "make":"F",
        #      "cylinders":null,
        #      "drivetrain":null,
        #      "engineDisp":"ENYZ",
        #      "fuelType":"G",
        #      "series":"4 Door Wagon",
        #      "productVariant":null,
        #      "averageMiles":null,
        #      "estimatedMileage":"0",
        #      "mileage":"0",
        #      "mileageDate":"2019-01-01T00:00:00.000Z",
        #      "mileageSource":null,
        #      "drivingConditionId":null,
        #      "configurationId":null,
        #      "primaryIndicator":"",
        #      "licenseplate":"Y 123",
        #      "purchaseDate":null,
        #      "registrationDate":"2019-01-01T00:00:00.000Z",
        #      "ownerCycle":null,
        #      "ownerindicator":"N",
        #      "brandCode":"Ford",
        #      "vehicleImageId":null,
        #      "headUnitType":null,
        #      "steeringWheelType":null,
        #      "lifeStyleXML":"",
        #      "syncVehicleIndicator":"",
        #      "vhrReadyDate":"01/01/0001 00:00:00",
        #      "vhrNotificationDate":"01/01/0001 00:00:00",
        #      "vhrUrgentNotificationStatus":null,
        #      "vhrStatus":null,
        #      "vhrNotificationStatus":null,
        #      "ngSdnManaged":1,
        #      "transmission":"6 Speed Manual Trans - B6 Plus",
        #      "bodyStyle":null,
        #      "preferredDealer":"GK1T9A0",
        #      "assignedDealer":null,
        #      "sellingDealer":null,
        #      "vhrReadyIndicator":null,
        #      "vehicleAuthorizationIndicator":1,
        #      "hasAuthorizedUser":1,
        #      "latestMileage":null,
        #      "vehicleRole":null,
        #      "warrantyStartDate":null,
        #      "versionDescription":"SERIES 85",
        #      "vehicleUpdateDate":null
        #    }
        #  }
        if(defined($decode_json) and
          ref($decode_json) eq "HASH")
        {
          my $currentVehicle = $decode_json->{"vehicle"};
          
          if(defined($currentVehicle))
          {
            readingsBulkUpdate($hash, "Vehicle_VIN", "$currentVehicle->{vin}")
              if (defined($currentVehicle->{vin}) and $currentVehicle->{vin} ne "null");
            readingsBulkUpdate($hash, "Vehicle_NickName", "$currentVehicle->{nickName}")
              if (defined($currentVehicle->{nickName}) and $currentVehicle->{nickName} ne "null");
            readingsBulkUpdate($hash, "Vehicle_Type", "$currentVehicle->{vehicleType}")
              if (defined($currentVehicle->{vehicleType}) and $currentVehicle->{vehicleType} ne "null");
            readingsBulkUpdate($hash, "Vehicle_Color", "$currentVehicle->{color}")
              if (defined($currentVehicle->{color}) and $currentVehicle->{color} ne "null");
            readingsBulkUpdate($hash, "Vehicle_ModelName", "$currentVehicle->{modelName}")
              if (defined($currentVehicle->{modelName}) and $currentVehicle->{modelName} ne "null");
            readingsBulkUpdate($hash, "Vehicle_ModelCode", "$currentVehicle->{modelCode}")
              if (defined($currentVehicle->{modelCode}) and $currentVehicle->{modelCode} ne "null");
            readingsBulkUpdate($hash, "Vehicle_ModelYear", "$currentVehicle->{modelYear}")
              if (defined($currentVehicle->{modelYear}) and $currentVehicle->{modelYear} ne "null");
            readingsBulkUpdate($hash, "Vehicle_Series", "$currentVehicle->{series}")
              if (defined($currentVehicle->{series}) and $currentVehicle->{series} ne "null");
            readingsBulkUpdate($hash, "Vehicle_EngineDisp", "$currentVehicle->{engineDisp}")
              if (defined($currentVehicle->{engineDisp}) and $currentVehicle->{engineDisp} ne "null");
            readingsBulkUpdate($hash, "Vehicle_FuelType", "$currentVehicle->{fuelType}")
              if (defined($currentVehicle->{fuelType}) and $currentVehicle->{fuelType} ne "null");
            readingsBulkUpdate($hash, "Vehicle_Licenseplate", "$currentVehicle->{licenseplate}")
              if (defined($currentVehicle->{licenseplate}) and $currentVehicle->{licenseplate} ne "null");
            readingsBulkUpdate($hash, "Vehicle_BrandCode", "$currentVehicle->{brandCode}")
              if (defined($currentVehicle->{brandCode}) and $currentVehicle->{brandCode} ne "null");
            readingsBulkUpdate($hash, "Vehicle_Transmission", "$currentVehicle->{transmission}")
              if (defined($currentVehicle->{transmission}) and $currentVehicle->{transmission} ne "null");
            readingsBulkUpdate($hash, "Vehicle_VersionDescription", "$currentVehicle->{versionDescription}")
              if (defined($currentVehicle->{versionDescription}) and $currentVehicle->{versionDescription} ne "null");
          }
        }
        else
        {
          $errorMsg = "UNKNOWN Data";
        }

        readingsEndUpdate($hash, 1);
      }
    }

    $hash->{helper}{Telegram_GetDetailsCounter}++;
    $hash->{helper}{Telegram_GetDetailsTimeProcess}  = gettimeofday() - $stopwatch;
    FordpassVehicle_UpdateInternals($hash);

    if( $errorMsg eq "" )
    {
      # if there is a callback then call it
      if( defined($callbackSuccess) )
      {
        Log3($name, 4, "FordpassVehicle_GetDetails($name) - callbackSuccess");
        $callbackSuccess->();
      }
    }
    else
    {
      # if there is a callback then call it
      if( defined($callbackFail) )
      {
        Log3($name, 4, "FordpassVehicle_GetDetails($name) - callbackFail");
        $callbackFail->();
      }
    }
  }; 

  my $vehicleId = $hash->{VEHICLEID};

  if(defined($vehicleId))
  {
    my $header = 
      "accept: */*\n" .
      "content-type: application/json";

    my $param = {};
    $param->{method} = "GET";
    $param->{url} = $API_URL . "/users/vehicles/" . $vehicleId . "/detail?lrdt=01-01-1970%2000:00:00";
    $param->{header} = $header;
#    $param->{data} = ;
#    $param->{httpversion} = "1.0";
#    $param->{ignoreredirects} = 0;
#    $param->{keepalive} = 1;
      
    $param->{resultCallback} = $resultCallback;
    $param->{timestampStart} = gettimeofday();
    
    $hash->{helper}{Telegram_GetDetailsIOWrite} = strftime($TimeStampFormat, localtime($param->{timestampStart}));

    FordpassVehicle_IOWrite( $hash, $param );
  }
  else
  {
    # if there is a callback then call it
    if( defined($callbackFail) )
    {
      Log3($name, 4, "FordpassVehicle_GetDetails($name) - callbackFail");
      $callbackFail->();
    }
  }
}


##################################
# FordpassVehicle_RefreshStatusV2( $hash, $callbackSuccess, $callbackFail )
sub FordpassVehicle_RefreshStatusV2($;$$)
{
  my ( $hash, $callbackSuccess, $callbackFail ) = @_;
  my $name    = $hash->{NAME};

  # definition of the lambda function wich is called to process received data
  my $resultCallback = sub 
  {
    my ( $callbackparam, $data, $errorMsg ) = @_;

    my $stopwatch = gettimeofday();
    $hash->{helper}{Telegram_RefreshStatusV2TimeRequest} = $stopwatch - $callbackparam->{timestampStart};
    $hash->{helper}{Telegram_RefreshStatusV2Callback}    = strftime($TimeStampFormat, localtime($stopwatch));
    Log3($name, 4, "FordpassVehicle_RefreshStatusV2($name) - resultCallback");

    if( $errorMsg eq "" )
    {
      my $decode_json = eval { decode_json($data) };

      if($@)
      {
        Log3($name, 3, "FordpassVehicle_RefreshStatusV2($name) - JSON error while request: $@");

        if( AttrVal( $name, "debugJSON", 0 ) == 1 )
        {
          readingsBeginUpdate($hash);
          readingsBulkUpdate( $hash, "JSON_ERROR", $@, 1 );
          readingsBulkUpdate( $hash, "JSON_ERROR_STRING", "\"" . $data . "\"", 1 );
          readingsEndUpdate($hash, 1);
        }
        $errorMsg = "GetStatusV2: JSON_ERROR";
      }
      else
      {
        readingsBeginUpdate($hash);

        if($hash->{helper}{GenericReadings} ne "none")
        {
          FordpassVehicle_RefreshReadingsFromObject($hash, $DebugMarker . $DefaultSeperator . "StatusV2" . $DefaultSeperator . "Refresh", $decode_json);
        }

        readingsEndUpdate($hash, 1);
      }
    }

    $hash->{helper}{Telegram_RefreshStatusV2Counter}++;
    $hash->{helper}{Telegram_RefreshStatusV2TimeProcess}  = gettimeofday() - $stopwatch;
    FordpassVehicle_UpdateInternals($hash);

    if( $errorMsg eq "" )
    {
      # if there is a callback then call it
      if( defined($callbackSuccess) )
      {
        Log3($name, 4, "FordpassVehicle_RefreshStatusV2($name) - callbackSuccess");
        $callbackSuccess->();
      }
    }
    else
    {
      readingsSingleUpdate( $hash, "state", $errorMsg, 1 );

      # if there is a callback then call it
      if( defined($callbackFail) )
      {
        Log3($name, 4, "FordpassVehicle_RefreshStatusV2($name) - callbackFail");
        $callbackFail->();
      }
    }
  }; 

  my $vehicleId = $hash->{VEHICLEID};

  if(defined($vehicleId))
  {
    my $header = 
      "accept: */*\n" .
      "content-type: application/json";

    my $param = {};
    $param->{method} = "PUT";
    $param->{url} = $API_URL . "/vehicles/v2/" . $vehicleId . "/status";
    $param->{header} = $header;
    $param->{data} = "{}";
#    $param->{httpversion} = "1.0";
#    $param->{ignoreredirects} = 0;
#    $param->{keepalive} = 1;
      
    $param->{resultCallback} = $resultCallback;
    $param->{timestampStart} = gettimeofday();
    
    $hash->{helper}{Telegram_RefreshStatusV2IOWrite} = strftime($TimeStampFormat, localtime($param->{timestampStart}));

    FordpassVehicle_IOWrite( $hash, $param );
  }
  else
  {
    # if there is a callback then call it
    if( defined($callbackFail) )
    {
      Log3($name, 4, "FordpassVehicle_RefreshStatusV2($name) - callbackFail");
      $callbackFail->();
    }
  }
}

##################################
# FordpassVehicle_GetStatusV2( $hash, $callbackSuccess, $callbackFail )
sub FordpassVehicle_GetStatusV2($;$$)
{
  my ( $hash, $callbackSuccess, $callbackFail ) = @_;
  my $name    = $hash->{NAME};

  # definition of the lambda function wich is called to process received data
  my $resultCallback = sub 
  {
    my ( $callbackparam, $data, $errorMsg ) = @_;

    my $stopwatch = gettimeofday();
    $hash->{helper}{Telegram_GetStatusV2TimeRequest} = $stopwatch - $callbackparam->{timestampStart};
    $hash->{helper}{Telegram_GetStatusV2Callback}    = strftime($TimeStampFormat, localtime($stopwatch));
    Log3($name, 4, "FordpassVehicle_GetStatusV2($name) - resultCallback");

    if( $errorMsg eq "" )
    {
      my $decode_json = eval { decode_json($data) };

      if($@)
      {
        Log3($name, 3, "FordpassVehicle_GetStatusV2($name) - JSON error while request: $@");

        if( AttrVal( $name, "debugJSON", 0 ) == 1 )
        {
          readingsBeginUpdate($hash);
          readingsBulkUpdate( $hash, "JSON_ERROR", $@, 1 );
          readingsBulkUpdate( $hash, "JSON_ERROR_STRING", "\"" . $data . "\"", 1 );
          readingsEndUpdate($hash, 1);
        }
        $errorMsg = "GetStatusV2: JSON_ERROR";
      }
      else
      {
        readingsBeginUpdate($hash);

        if($hash->{helper}{GenericReadings} ne "none")
        {
          FordpassVehicle_RefreshReadingsFromObject($hash, $DebugMarker . $DefaultSeperator . "StatusV2", $decode_json);
        }
          
        # {
        #   "vehiclestatus":
        #   {
        #     "vin":"xxxxxxxxxxxxxxxxx",
        #     "longitude":"0.0000000",
        #     "latitude":"00.0000000",
        #     "remoteStartStatus":0,
        #     "remoteStartDuration":10,
        #     "remoteStartTime":0,
        #     "lockStatus":"UNLOCKED",
        #     "alarm":"NOTSET",
        #     "batteryHealth":"STATUS_LOW",
        #     "odometer":32087.0,
        #     "fuelLevel":25.00008,
        #     "oilLife":"STATUS_GOOD",
        #     "tirePressure":"STATUS_GOOD",
        #     "authorization":"AUTHORIZED",
        #     "gpsState":"UNSHIFTED",
        #     "lastRefresh":"02-08-2022 13:21:06",
        #     "lastModifiedDate":"02-08-2022 13:21:08",
        #     "oilLifeActual":89,
        #     "batteryStatusActual":15,
        #     "serverTime":"02-08-2022 13:49:25",
        #     "distanceToEmpty":167.0,
        #     "tirePressureSystemStatus":"Systm_Activ_Composite_Stat",
        #     "recommendedFrontTirePressure":30,
        #     "recommendedRearTirePressure":26,
        #     "leftFrontTireStatus":"Normal",
        #     "leftFrontTirePressure":"246",
        #     "rightFrontTireStatus":"Normal",
        #     "rightFrontTirePressure":"246",
        #     "innerLeftRearTireStatus":"Not_Supported",
        #     "innerLeftRearTirePressure":"",
        #     "innerRightRearTireStatus":"Not_Supported",
        #     "innerRightRearTirePressure":"",
        #     "outerLeftRearTireStatus":"Normal",
        #     "outerLeftRearTirePressure":"243",
        #     "outerRightRearTireStatus":"Normal",
        #     "outerRightRearTirePressure":"243",
        #     "tirePressureByLocation":1,
        #     "dualRearWheel":0,
        #     "ccsSettings":
        #     {
        #       "location":1,
        #       "vehicleConnectivity":1,
        #       "vehicleData":1,
        #       "drivingCharacteristics":-1,
        #       "contacts":-1
        #     }
        #   }
        # }
        if(defined($decode_json) and
          ref($decode_json) eq "HASH")
        {
          my $currentVehiclestatus = $decode_json->{"vehiclestatus"};

          if(defined($currentVehiclestatus))
          {
  #            readingsBulkUpdateIfChanged($hash, "VehicleVersionDescription", "$currentVehicle->{versionDescription}")
  #              if (defined($currentVehicle->{versionDescription}) and $currentVehicle->{versionDescription} ne "null");
          }
        }
        else
        {
          $errorMsg = "UNKNOWN Data";
        }

        readingsEndUpdate($hash, 1);
      }
    }

    $hash->{helper}{Telegram_GetStatusV2Counter}++;
    $hash->{helper}{Telegram_GetStatusV2TimeProcess}  = gettimeofday() - $stopwatch;
    FordpassVehicle_UpdateInternals($hash);

    if( $errorMsg eq "" )
    {
      # if there is a callback then call it
      if( defined($callbackSuccess) )
      {
        Log3($name, 4, "FordpassVehicle_GetStatusV2($name) - callbackSuccess");
        $callbackSuccess->();
      }
    }
    else
    {
      readingsSingleUpdate( $hash, "state", $errorMsg, 1 );

      # if there is a callback then call it
      if( defined($callbackFail) )
      {
        Log3($name, 4, "FordpassVehicle_GetStatusV2($name) - callbackFail");
        $callbackFail->();
      }
    }
  }; 

  my $vehicleId = $hash->{VEHICLEID};

  if(defined($vehicleId))
  {
    my $header = 
      "accept: */*\n" .
      "content-type: application/json";
      
    my $param = {};
    $param->{method} = "GET";
    $param->{url} = $API_URL . "/vehicles/v2/" . $vehicleId . "/status";
    $param->{header} = $header;
#    $param->{data} = "{}";
#    $param->{httpversion} = "1.0";
#    $param->{ignoreredirects} = 0;
#    $param->{keepalive} = 1;
      
    $param->{resultCallback} = $resultCallback;
    $param->{timestampStart} = gettimeofday();
    
    $hash->{helper}{Telegram_GetStatusV2IOWrite} = strftime($TimeStampFormat, localtime($param->{timestampStart}));

    FordpassVehicle_IOWrite( $hash, $param );
  }
  else
  {
    # if there is a callback then call it
    if( defined($callbackFail) )
    {
      Log3($name, 4, "FordpassVehicle_GetStatusV2($name) - callbackFail");
      $callbackFail->();
    }
  }
}

##################################
# FordpassVehicle_GetStatusV4( $hash, $callbackSuccess, $callbackFail )
sub FordpassVehicle_GetStatusV4($;$$)
{
  my ( $hash, $callbackSuccess, $callbackFail ) = @_;
  my $name    = $hash->{NAME};

  # definition of the lambda function wich is called to process received data
  my $resultCallback = sub 
  {
    my ( $callbackparam, $data, $errorMsg ) = @_;

    my $stopwatch = gettimeofday();
    $hash->{helper}{Telegram_GetStatusV4TimeRequest} = $stopwatch - $callbackparam->{timestampStart};
    $hash->{helper}{Telegram_GetStatusV4Callback}    = strftime($TimeStampFormat, localtime($stopwatch));
    Log3($name, 4, "FordpassVehicle_GetStatusV4($name) - resultCallback");

    if( $errorMsg eq "" )
    {
      my $decode_json = eval { decode_json($data) };

      if($@)
      {
        Log3($name, 3, "FordpassVehicle_GetStatusV4($name) - JSON error while request: $@");

        if( AttrVal( $name, "debugJSON", 0 ) == 1 )
        {
          readingsBeginUpdate($hash);
          readingsBulkUpdate( $hash, "JSON_ERROR", $@, 1 );
          readingsBulkUpdate( $hash, "JSON_ERROR_STRING", "\"" . $data . "\"", 1 );
          readingsEndUpdate($hash, 1);
        }
        $errorMsg = "GetStatusV4: JSON_ERROR";
      }
      else
      {
        readingsBeginUpdate($hash);

        if($hash->{helper}{GenericReadings} ne "none")
        {
          FordpassVehicle_RefreshReadingsFromObject($hash, $DebugMarker . $DefaultSeperator . "StatusV4", $decode_json);
        }
        
=for Comment
{
  "vehiclestatus":
  {
    "vin":"xxxxxxxxxxxxxxxxx",
    "lockStatus":
    {
      "value":"LOCKED",
      "status":"CURRENT",
      "timestamp":"02-19-2022 06:04:16"
    },
    "alarm":
    {
      "value":"NOTSET",
      "status":"CURRENT",
      "timestamp":"02-19-2022 06:04:16"
    },
    "PrmtAlarmEvent":
    {
      "value":"Null",
      "status":"CURRENT",
      "timestamp":"02-19-2022 06:04:16"
    },
    "odometer":
    {
      "value":32368.0,
      "status":"CURRENT",
      "timestamp":"02-19-2022 06:04:16"
    },
    "fuel":
    {
      "fuelLevel":-5.217408,
      "distanceToEmpty":217.5,
      "status":"CURRENT",
      "timestamp":"02-19-2022 06:04:16"
    },
    "gps":
    {
      "latitude":"00.0000000",
      "longitude":"0.0000000",
      "gpsState":"UNSHIFTED",
      "status":"LAST_KNOWN",
      "timestamp":"02-18-2022 15:03:00"
    },
    "remoteStart":
    {
      "remoteStartDuration":10,
      "remoteStartTime":0,
      "status":"CURRENT",
      "timestamp":"02-19-2022 06:04:16"
    },
    "remoteStartStatus":
    {
      "value":0,
      "status":"CURRENT",
      "timestamp":"02-19-2022 06:04:16"
    },
    "battery":
    {
      "batteryHealth":
      {
        "value":"STATUS_LOW",
        "timestamp":"09-08-2020 01:49:22"
      },
      "batteryStatusActual":
      {
        "value":12,
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      }
    },
    "oil":
    {
      "oilLife":"STATUS_GOOD",
      "oilLifeActual":87,
      "status":"CURRENT",
      "timestamp":"02-19-2022 06:04:16"
    },
    "tirePressure":
    {
      "value":"STATUS_GOOD",
      "timestamp":"02-19-2022 06:04:14"
    },
    "authorization":"AUTHORIZED",
    "TPMS":
    {
      "tirePressureByLocation":
      {
        "value":1,
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "tirePressureSystemStatus":
      {
        "value":"Systm_Activ_Composite_Stat",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "dualRearWheel":
      {
        "value":0,
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "leftFrontTireStatus":
      {
        "value":"Normal",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "leftFrontTirePressure":
      {
        "value":"238",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "rightFrontTireStatus":
      {
        "value":"Normal",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "rightFrontTirePressure":
      {
        "value":"236",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "outerLeftRearTireStatus":
      {
        "value":"Normal",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "outerLeftRearTirePressure":
      {
        "value":"236",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "outerRightRearTireStatus":
      {
        "value":"Normal",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "outerRightRearTirePressure":
      {
        "value":"234",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "innerLeftRearTireStatus":
      {
        "value":"Not_Supported",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "innerLeftRearTirePressure":null,
      "innerRightRearTireStatus":
      {
        "value":"Not_Supported",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "innerRightRearTirePressure":null,
      "recommendedFrontTirePressure":
      {
        "value":30,
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "recommendedRearTirePressure":
      {
        "value":26,
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      }
    },
    "firmwareUpgInProgress":
    {
      "value":false,
      "timestamp":"06-10-2021 13:16:04"
    },
    "deepSleepInProgress":
    {
      "value":false,
      "timestamp":"06-12-2021 06:24:37"
    },
    "ccsSettings":
    {
      "timestamp":"04-15-2020 01:42:31",
      "location":1,
      "vehicleConnectivity":1,
      "vehicleData":1,
      "drivingCharacteristics":-1,
      "contacts":-1
    },
    "lastRefresh":"02-19-2022 06:04:14",
    "lastModifiedDate":"02-19-2022 06:04:16",
    "serverTime":"02-19-2022 06:05:07",
    "batteryFillLevel":null,
    "elVehDTE":null,
    "hybridModeStatus":null,
    "chargingStatus":null,
    "plugStatus":null,
    "chargeStartTime":null,
    "chargeEndTime":null,
    "preCondStatusDsply":null,
    "chargerPowertype":null,
    "batteryPerfStatus":null,
    "outandAbout":
    {
      "value":"PwPckOffTqNotAvailable",
      "status":"CURRENT",
      "timestamp":"02-19-2022 06:04:16"
    },
    "batteryChargeStatus":null,
    "dcFastChargeData":null,
    "windowPosition":
    {
      "driverWindowPosition":
      {
        "value":"Fully_Closed",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "passWindowPosition":
      {
        "value":"Fully_Closed",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "rearDriverWindowPos":
      {
        "value":"Fully_Closed",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "rearPassWindowPos":
      {
        "value":"Fully_Closed",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      }
    },
    "doorStatus":
    {
      "rightRearDoor":
      {
        "value":"Closed",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "leftRearDoor":
      {
        "value":"Closed",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "driverDoor":
      {
        "value":"Closed",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "passengerDoor":
      {
        "value":"Closed",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "hoodDoor":
      {
        "value":"Closed",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "tailgateDoor":
      {
        "value":"Closed",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      },
      "innerTailgateDoor":
      {
        "value":"Closed",
        "status":"CURRENT",
        "timestamp":"02-19-2022 06:04:16"
      }
    },
    "ignitionStatus":
    {
      "value":"Off",
      "status":"CURRENT",
      "timestamp":"02-19-2022 06:04:16"
    },
    "batteryTracLowChargeThreshold":null,
    "battTracLoSocDDsply":null,
    "dieselSystemStatus":
    {
      "exhaustFluidLevel":null,
      "filterSoot":null,
      "ureaRange":null,
      "metricType":null,
      "filterRegenerationStatus":null
    }
  },
  "version":"4.0.0",
  "status":200
}
=cut

        if(defined($decode_json) and
          ref($decode_json) eq "HASH")
        {
          my $currentVehiclestatus = $decode_json->{"vehiclestatus"};

          if(defined($currentVehiclestatus))
          {
            if("$hash->{Capability_CssLocation}" eq "True")
            {
              readingsBulkUpdate($hash, "Location_Latitude", "$currentVehiclestatus->{gps}->{latitude}")
                if (defined($currentVehiclestatus->{gps}->{latitude}));
              readingsBulkUpdate($hash, "Location_Longitude", "$currentVehiclestatus->{gps}->{longitude}")
                if (defined($currentVehiclestatus->{gps}->{longitude}));
              
              if ($hash->{helper}{ShowTimestamps} eq "1")
              {
                readingsBulkUpdate($hash, "Location" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{gps}->{timestamp}))
                  if(defined($currentVehiclestatus->{gps}->{timestamp}));
              }
            }

            if("$hash->{Capability_OilLife}" eq "True")
            {
              readingsBulkUpdate($hash, "Oil_Life_Status", "$currentVehiclestatus->{oil}->{oilLife}")
                if (defined($currentVehiclestatus->{oil}->{oilLife}));
                
              readingsBulkUpdate($hash, "Oil_Life_Percent", "$currentVehiclestatus->{oil}->{oilLifeActual}")
                if (defined($currentVehiclestatus->{oil}->{oilLifeActual}));

              if ($hash->{helper}{ShowTimestamps} eq "1")
              {
                readingsBulkUpdate($hash, "Oil_Life" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{oil}->{timestamp}))
                  if(defined($currentVehiclestatus->{oil}->{timestamp}));
              }
            }

            #if("$hash->{Capability_TirePressureMonitoring}" eq "True")
            {
              readingsBulkUpdate($hash, "Odometer", "$currentVehiclestatus->{odometer}->{value}")
                if (defined($currentVehiclestatus->{odometer}->{value}));

              if ($hash->{helper}{ShowTimestamps} eq "1")
              {
                readingsBulkUpdate($hash, "Odometer" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{odometer}->{timestamp}))
                  if(defined($currentVehiclestatus->{odometer}->{timestamp}));
              }
            }

            if (defined($currentVehiclestatus->{ignitionStatus}->{value}))
            {
              readingsBulkUpdate($hash, "Status_Ignition", "$currentVehiclestatus->{ignitionStatus}->{value}");
              $hash->{helper}{IgnitionStatus} = $currentVehiclestatus->{ignitionStatus}->{value} eq "Run" ? "1" : "0";

              if ($hash->{helper}{ShowTimestamps} eq "1")
              {
                readingsBulkUpdate($hash, "Status_Ignition" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{ignitionStatus}->{timestamp}))
                  if(defined($currentVehiclestatus->{ignitionStatus}->{timestamp}));
              }
            }

            #if (defined($currentVehiclestatus->{ignitionStatus}->{value})
            {
              readingsBulkUpdate($hash, "Status_Lock", "$currentVehiclestatus->{lockStatus}->{value}")
                if (defined($currentVehiclestatus->{lockStatus}->{value}));

              if ($hash->{helper}{ShowTimestamps} eq "1")
              {
                readingsBulkUpdate($hash, "Status_Lock" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{lockStatus}->{timestamp}))
                  if(defined($currentVehiclestatus->{lockStatus}->{timestamp}));
              }
            }

            #if (defined($currentVehiclestatus->{ignitionStatus}->{value})
            {
              readingsBulkUpdate($hash, "Status_Alarm", "$currentVehiclestatus->{alarm}->{value}")
                if (defined($currentVehiclestatus->{alarm}->{value}));

              if ($hash->{helper}{ShowTimestamps} eq "1")
              {
                readingsBulkUpdate($hash, "Status_Alarm" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{alarm}->{timestamp}))
                  if(defined($currentVehiclestatus->{alarm}->{timestamp}));
              }
            }

            #if (defined($currentVehiclestatus->{ignitionStatus}->{value})
            {
              readingsBulkUpdate($hash, "Status_FirmwareUpgrade_InProgress", "$currentVehiclestatus->{firmwareUpgInProgress}->{value}")
                if (defined($currentVehiclestatus->{firmwareUpgInProgress}->{value}));

              if ($hash->{helper}{ShowTimestamps} eq "1")
              {
                readingsBulkUpdate($hash, "Status_FirmwareUpgrade_InProgress" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{firmwareUpgInProgress}->{timestamp}))
                  if(defined($currentVehiclestatus->{firmwareUpgInProgress}->{timestamp}));
              }
            }

            #if (defined($currentVehiclestatus->{ignitionStatus}->{value})
            {
              readingsBulkUpdate($hash, "Status_DeepSleep_InProgress", "$currentVehiclestatus->{deepSleepInProgress}->{value}")
                if (defined($currentVehiclestatus->{deepSleepInProgress}->{value}));

              if ($hash->{helper}{ShowTimestamps} eq "1")
              {
                readingsBulkUpdate($hash, "Status_DeepSleep_InProgress" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{deepSleepInProgress}->{timestamp}))
                  if(defined($currentVehiclestatus->{deepSleepInProgress}->{timestamp}));
              }
            }

            #if (defined($currentVehiclestatus->{ignitionStatus}->{value})
            {
              readingsBulkUpdate($hash, "Status_OutAndAbout", "$currentVehiclestatus->{outandAbout}->{value}")
                if (defined($currentVehiclestatus->{outandAbout}->{value}));

              if ($hash->{helper}{ShowTimestamps} eq "1")
              {
                readingsBulkUpdate($hash, "Status_OutAndAbout" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{outandAbout}->{timestamp}))
                  if(defined($currentVehiclestatus->{outandAbout}->{timestamp}));
              }
            }

            #if("$hash->{Capability_TirePressureMonitoring}" eq "True")
            {
              readingsBulkUpdate($hash, "Battery_Health", "$currentVehiclestatus->{battery}->{batteryHealth}->{value}")
                if (defined($currentVehiclestatus->{battery}->{batteryHealth}->{value}));

              if ($hash->{helper}{ShowTimestamps} eq "1")
              {
                readingsBulkUpdate($hash, "Battery_Health" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{battery}->{batteryHealth}->{timestamp}))
                  if (defined($currentVehiclestatus->{battery}->{batteryHealth}->{timestamp}));
              }
                
              readingsBulkUpdate($hash, "Battery_Status_Actual", "$currentVehiclestatus->{battery}->{batteryStatusActual}->{value}")
                if (defined($currentVehiclestatus->{battery}->{batteryStatusActual}->{value}));

              if ($hash->{helper}{ShowTimestamps} eq "1")
              {
                readingsBulkUpdate($hash, "Battery_Status_Actual" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{battery}->{batteryStatusActual}->{timestamp}))
                  if(defined($currentVehiclestatus->{battery}->{batteryStatusActual}->{timestamp}));
              }
            }

            if("$hash->{Capability_RemoteStart}" eq "True")
            {
              readingsBulkUpdate($hash, "Remote_Start_Status", "$currentVehiclestatus->{remoteStartStatus}->{value}")
                if (defined($currentVehiclestatus->{remoteStartStatus}->{value}));
              readingsBulkUpdate($hash, "Remote_Start_StartTime", "$currentVehiclestatus->{remoteStart}->{remoteStartDuration}")
                if (defined($currentVehiclestatus->{remoteStart}->{remoteStartDuration}));
              readingsBulkUpdate($hash, "Remote_Start_Duration", "$currentVehiclestatus->{remoteStart}->{remoteStartTime}")
                if (defined($currentVehiclestatus->{remoteStart}->{remoteStartTime}));

              if ($hash->{helper}{ShowTimestamps} eq "1")
              {
                readingsBulkUpdate($hash, "Remote_Start" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{remoteStart}->{timestamp}))
                  if(defined($currentVehiclestatus->{remoteStart}->{timestamp}));
              }
            }

            #if("$hash->{Capability_TirePressureMonitoring}" eq "True")
            {
              readingsBulkUpdate($hash, "Fuel_Level_Percent", "$currentVehiclestatus->{fuel}->{fuelLevel}")
                if (defined($currentVehiclestatus->{fuel}->{fuelLevel}));
              readingsBulkUpdate($hash, "Fuel_DistanceToEmpty", "$currentVehiclestatus->{fuel}->{distanceToEmpty}")
                if (defined($currentVehiclestatus->{fuel}->{distanceToEmpty}));

              if ($hash->{helper}{ShowTimestamps} eq "1")
              {
                readingsBulkUpdate($hash, "Fuel" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{fuel}->{timestamp}))
                  if(defined($currentVehiclestatus->{fuel}->{timestamp}));
              }
            }

            if("$hash->{Capability_TirePressureMonitoring}" eq "True")
            {
              readingsBulkUpdate($hash, "Tire_Status", "$currentVehiclestatus->{tirePressure}->{value}")
                if (defined($currentVehiclestatus->{tirePressure}->{value}));

              if ($hash->{helper}{ShowTimestamps} eq "1")
              {
                readingsBulkUpdate($hash, "Tire_Status" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{tirePressure}->{timestamp}))
                  if(defined($currentVehiclestatus->{tirePressure}->{timestamp}));
              }

              readingsBulkUpdate($hash, "Tire_Status_System", "$currentVehiclestatus->{TPMS}->{tirePressureSystemStatus}->{value}")
                if (defined($currentVehiclestatus->{TPMS}->{tirePressureSystemStatus}->{value}));

              if ($hash->{helper}{ShowTimestamps} eq "1")
              {
                readingsBulkUpdate($hash, "Tire_Status_System" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{TPMS}->{tirePressureSystemStatus}->{timestamp}))
                  if(defined($currentVehiclestatus->{TPMS}->{tirePressureSystemStatus}->{timestamp}));
              }

              readingsBulkUpdate($hash, "Tire_Front_Pressure_Recommended", $currentVehiclestatus->{TPMS}->{recommendedFrontTirePressure}->{value} / 10)
                if (defined($currentVehiclestatus->{TPMS}->{recommendedFrontTirePressure}->{value}));

              if ($hash->{helper}{ShowTimestamps} eq "1")
              {
                readingsBulkUpdate($hash, "Tire_Front_Pressure_Recommended" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{TPMS}->{recommendedFrontTirePressure}->{timestamp}))
                  if(defined($currentVehiclestatus->{TPMS}->{recommendedFrontTirePressure}->{timestamp}));
              }

              readingsBulkUpdate($hash, "Tire_Rear_Pressure_Recommended", $currentVehiclestatus->{TPMS}->{recommendedRearTirePressure}->{value} / 10)
                if (defined($currentVehiclestatus->{TPMS}->{recommendedRearTirePressure}->{value}));

              if ($hash->{helper}{ShowTimestamps} eq "1")
              {
                readingsBulkUpdate($hash, "Tire_Rear_Pressure_Recommended" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{TPMS}->{recommendedRearTirePressure}->{timestamp}))
                  if(defined($currentVehiclestatus->{TPMS}->{recommendedRearTirePressure}->{timestamp}));
              }
    
              if (defined($currentVehiclestatus->{TPMS}->{leftFrontTireStatus}->{value}) and
                $currentVehiclestatus->{TPMS}->{leftFrontTireStatus}->{value} ne "Not_Supported")
              {
                readingsBulkUpdate($hash, "Tire_Front_Left_Status", "$currentVehiclestatus->{TPMS}->{leftFrontTireStatus}->{value}");
                readingsBulkUpdate($hash, "Tire_Front_Left_Pressure", $currentVehiclestatus->{TPMS}->{leftFrontTirePressure}->{value} / 100);

                if ($hash->{helper}{ShowTimestamps} eq "1")
                {
                  readingsBulkUpdate($hash, "Tire_Front_Left" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{TPMS}->{leftFrontTireStatus}->{timestamp}))
                    if(defined($currentVehiclestatus->{TPMS}->{leftFrontTireStatus}->{timestamp}));
                }
              }

              if (defined($currentVehiclestatus->{TPMS}->{rightFrontTireStatus}->{value}) and
                $currentVehiclestatus->{TPMS}->{rightFrontTireStatus}->{value} ne "Not_Supported")
              {
                readingsBulkUpdate($hash, "Tire_Front_Right_Status", "$currentVehiclestatus->{TPMS}->{rightFrontTireStatus}->{value}");
                readingsBulkUpdate($hash, "Tire_Front_Right_Pressure", $currentVehiclestatus->{TPMS}->{rightFrontTirePressure}->{value} / 100);

                if ($hash->{helper}{ShowTimestamps} eq "1")
                {
                  readingsBulkUpdate($hash, "Tire_Front_Right" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{TPMS}->{rightFrontTirePressure}->{timestamp}))
                    if(defined($currentVehiclestatus->{TPMS}->{rightFrontTirePressure}->{timestamp}));
                }
              }

              if (defined($currentVehiclestatus->{TPMS}->{outerLeftRearTireStatus}->{value}) and
                $currentVehiclestatus->{TPMS}->{outerLeftRearTireStatus}->{value} ne "Not_Supported")
              {
                readingsBulkUpdate($hash, "Tire_Rear_Left_Status", "$currentVehiclestatus->{TPMS}->{outerLeftRearTireStatus}->{value}");
                readingsBulkUpdate($hash, "Tire_Rear_Left_Pressure", $currentVehiclestatus->{TPMS}->{outerLeftRearTirePressure}->{value} / 100);

                if ($hash->{helper}{ShowTimestamps} eq "1")
                {
                  readingsBulkUpdate($hash, "Tire_Rear_Left" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{TPMS}->{outerLeftRearTirePressure}->{timestamp}))
                    if(defined($currentVehiclestatus->{TPMS}->{outerLeftRearTirePressure}->{timestamp}));
                }
              }

              if (defined($currentVehiclestatus->{TPMS}->{outerRightRearTireStatus}->{value}) and
                $currentVehiclestatus->{TPMS}->{outerRightRearTireStatus}->{value} ne "Not_Supported")
              {
                readingsBulkUpdate($hash, "Tire_Rear_Right_Status", "$currentVehiclestatus->{TPMS}->{outerRightRearTireStatus}->{value}");
                readingsBulkUpdate($hash, "Tire_Rear_Right_Pressure", $currentVehiclestatus->{TPMS}->{outerRightRearTirePressure}->{value} / 100);

                if ($hash->{helper}{ShowTimestamps} eq "1")
                {
                  readingsBulkUpdate($hash, "Tire_Rear_Right" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{TPMS}->{outerRightRearTirePressure}->{timestamp}))
                    if(defined($currentVehiclestatus->{TPMS}->{outerRightRearTirePressure}->{timestamp}));
                }
              }

              if (defined($currentVehiclestatus->{TPMS}->{innerLeftRearTireStatus}->{value}) and
                $currentVehiclestatus->{TPMS}->{innerLeftRearTireStatus}->{value} ne "Not_Supported")
              {
                readingsBulkUpdate($hash, "Tire_Rear_InnerLeft_Status", "$currentVehiclestatus->{TPMS}->{innerLeftRearTireStatus}->{value}");
                readingsBulkUpdate($hash, "Tire_Rear_InnerLeft_Pressure", $currentVehiclestatus->{TPMS}->{innerLeftRearTirePressure}->{value} / 100);

                if ($hash->{helper}{ShowTimestamps} eq "1")
                {
                  readingsBulkUpdate($hash, "Tire_Rear_InnerLeft" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{TPMS}->{innerLeftRearTirePressure}->{timestamp}))
                    if(defined($currentVehiclestatus->{TPMS}->{innerLeftRearTirePressure}->{timestamp}));
                }
              }

              if (defined($currentVehiclestatus->{TPMS}->{innerRightRearTireStatus}->{value}) and
                $currentVehiclestatus->{TPMS}->{innerRightRearTireStatus}->{value} ne "Not_Supported")
              {
                readingsBulkUpdate($hash, "Tire_Rear_InnerRight_Status", "$currentVehiclestatus->{TPMS}->{innerRightRearTireStatus}->{value}");
                readingsBulkUpdate($hash, "Tire_Rear_InnerRight_Pressure", $currentVehiclestatus->{TPMS}->{innerRightRearTirePressure}->{value} / 100);

                if ($hash->{helper}{ShowTimestamps} eq "1")
                {
                  readingsBulkUpdate($hash, "Tire_Rear_InnerRight" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{TPMS}->{innerRightRearTirePressure}->{timestamp}))
                    if(defined($currentVehiclestatus->{TPMS}->{innerRightRearTirePressure}->{timestamp}));
                }
              }
            }

            #if("$hash->{Capability_TirePressureMonitoring}" eq "True")
            {
              if (defined($currentVehiclestatus->{windowPosition}->{driverWindowPosition}->{value}) and
                $currentVehiclestatus->{windowPosition}->{driverWindowPosition}->{value} ne "Not_Supported")
              {
                readingsBulkUpdate($hash, "Window_Front_Driver_Position", "$currentVehiclestatus->{windowPosition}->{driverWindowPosition}->{value}");

                if ($hash->{helper}{ShowTimestamps} eq "1")
                {
                  readingsBulkUpdate($hash, "Window_Front_Driver_Position" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{windowPosition}->{driverWindowPosition}->{timestamp}))
                    if(defined($currentVehiclestatus->{windowPosition}->{driverWindowPosition}->{timestamp}));
                }
              }

              if (defined($currentVehiclestatus->{windowPosition}->{passWindowPosition}->{value}) and
                $currentVehiclestatus->{windowPosition}->{passWindowPosition}->{value} ne "Not_Supported")
              {
                readingsBulkUpdate($hash, "Window_Front_Passenger_Position", "$currentVehiclestatus->{windowPosition}->{passWindowPosition}->{value}");

                if ($hash->{helper}{ShowTimestamps} eq "1")
                {
                  readingsBulkUpdate($hash, "Window_Front_Passenger_Position" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{windowPosition}->{passWindowPosition}->{timestamp}))
                    if(defined($currentVehiclestatus->{windowPosition}->{passWindowPosition}->{timestamp}));
                }
              }

              if (defined($currentVehiclestatus->{windowPosition}->{rearDriverWindowPos}->{value}) and
                $currentVehiclestatus->{windowPosition}->{rearDriverWindowPos}->{value} ne "Not_Supported")
              {
                readingsBulkUpdate($hash, "Window_Rear_Driver_Position", "$currentVehiclestatus->{windowPosition}->{rearDriverWindowPos}->{value}");

                if ($hash->{helper}{ShowTimestamps} eq "1")
                {
                  readingsBulkUpdate($hash, "Window_Rear_Driver_Position" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{windowPosition}->{rearDriverWindowPos}->{timestamp}))
                    if(defined($currentVehiclestatus->{windowPosition}->{rearDriverWindowPos}->{timestamp}));
                }
              }

              if (defined($currentVehiclestatus->{windowPosition}->{rearPassWindowPos}->{value}) and
                $currentVehiclestatus->{windowPosition}->{rearPassWindowPos}->{value} ne "Not_Supported")
              {
                readingsBulkUpdate($hash, "Window_Rear_Passenger_Position", "$currentVehiclestatus->{windowPosition}->{rearPassWindowPos}->{value}");

                if ($hash->{helper}{ShowTimestamps} eq "1")
                {
                  readingsBulkUpdate($hash, "Window_Rear_Passenger_Position" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{windowPosition}->{rearPassWindowPos}->{timestamp}))
                    if(defined($currentVehiclestatus->{windowPosition}->{rearPassWindowPos}->{timestamp}));
                }
              }
            }

            #if("$hash->{Capability_TirePressureMonitoring}" eq "True")
            {
              if (defined($currentVehiclestatus->{doorStatus}->{driverDoor}->{value}) and
                $currentVehiclestatus->{doorStatus}->{driverDoor}->{value} ne "Not_Supported")
              {
                readingsBulkUpdate($hash, "Door_Front_Driver", "$currentVehiclestatus->{doorStatus}->{driverDoor}->{value}");

                if ($hash->{helper}{ShowTimestamps} eq "1")
                {
                  readingsBulkUpdate($hash, "Door_Front_Driver" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{doorStatus}->{driverDoor}->{timestamp}))
                    if(defined($currentVehiclestatus->{doorStatus}->{driverDoor}->{timestamp}));
                }
              }

              if (defined($currentVehiclestatus->{doorStatus}->{passengerDoor}->{value}) and
                $currentVehiclestatus->{doorStatus}->{passengerDoor}->{value} ne "Not_Supported")
              {
                readingsBulkUpdate($hash, "Door_Front_Passenger", "$currentVehiclestatus->{doorStatus}->{passengerDoor}->{value}");

                if ($hash->{helper}{ShowTimestamps} eq "1")
                {
                  readingsBulkUpdate($hash, "Door_Front_Passenger" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{doorStatus}->{passengerDoor}->{timestamp}))
                    if(defined($currentVehiclestatus->{doorStatus}->{passengerDoor}->{timestamp}));
                }
              }

              if (defined($currentVehiclestatus->{doorStatus}->{leftRearDoor}->{value}) and
                $currentVehiclestatus->{doorStatus}->{leftRearDoor}->{value} ne "Not_Supported")
              {
                readingsBulkUpdate($hash, "Door_Rear_Left", "$currentVehiclestatus->{doorStatus}->{leftRearDoor}->{value}");

                if ($hash->{helper}{ShowTimestamps} eq "1")
                {
                  readingsBulkUpdate($hash, "Door_Rear_Left" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{doorStatus}->{leftRearDoor}->{timestamp}))
                    if(defined($currentVehiclestatus->{doorStatus}->{leftRearDoor}->{timestamp}));
                }
              }

              if (defined($currentVehiclestatus->{doorStatus}->{rightRearDoor}->{value}) and
                $currentVehiclestatus->{doorStatus}->{rightRearDoor}->{value} ne "Not_Supported")
              {
                readingsBulkUpdate($hash, "Door_Rear_Right", "$currentVehiclestatus->{doorStatus}->{rightRearDoor}->{value}");

                if ($hash->{helper}{ShowTimestamps} eq "1")
                {
                  readingsBulkUpdate($hash, "Door_Rear_Right" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{doorStatus}->{rightRearDoor}->{timestamp}))
                    if(defined($currentVehiclestatus->{doorStatus}->{rightRearDoor}->{timestamp}));
                }
              }

              if (defined($currentVehiclestatus->{doorStatus}->{hoodDoor}->{value}) and
                $currentVehiclestatus->{doorStatus}->{hoodDoor}->{value} ne "Not_Supported")
              {
                readingsBulkUpdate($hash, "Door_Hood", "$currentVehiclestatus->{doorStatus}->{hoodDoor}->{value}");

                if ($hash->{helper}{ShowTimestamps} eq "1")
                {
                  readingsBulkUpdate($hash, "Door_Hood" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{doorStatus}->{hoodDoor}->{timestamp}))
                    if(defined($currentVehiclestatus->{doorStatus}->{hoodDoor}->{timestamp}));
                }
              }

              if (defined($currentVehiclestatus->{doorStatus}->{tailgateDoor}->{value}) and
                $currentVehiclestatus->{doorStatus}->{tailgateDoor}->{value} ne "Not_Supported")
              {
                readingsBulkUpdate($hash, "Door_Tailgate", "$currentVehiclestatus->{doorStatus}->{tailgateDoor}->{value}");

                if ($hash->{helper}{ShowTimestamps} eq "1")
                {
                  readingsBulkUpdate($hash, "Door_Tailgate" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{doorStatus}->{tailgateDoor}->{timestamp}))
                    if(defined($currentVehiclestatus->{doorStatus}->{tailgateDoor}->{timestamp}));
                }
              }

              if (defined($currentVehiclestatus->{doorStatus}->{innerTailgateDoor}->{value}) and
                $currentVehiclestatus->{doorStatus}->{innerTailgateDoor}->{value} ne "Not_Supported")
              {
                readingsBulkUpdate($hash, "Door_Tailgate_Inner", "$currentVehiclestatus->{doorStatus}->{innerTailgateDoor}->{value}");

                if ($hash->{helper}{ShowTimestamps} eq "1")
                {
                  readingsBulkUpdate($hash, "Door_Tailgate_Inner" . $TimestampMarker, FordpassVehicle_GetLTZFromUTC($currentVehiclestatus->{doorStatus}->{innerTailgateDoor}->{timestamp}))
                    if(defined($currentVehiclestatus->{doorStatus}->{innerTailgateDoor}->{timestamp}));
                }
              }
            }
          }
        }
        else
        {
          $errorMsg = "UNKNOWN Data";
        }

        readingsEndUpdate($hash, 1);
      }
    }

    $hash->{helper}{Telegram_GetStatusV4Counter}++;
    $hash->{helper}{Telegram_GetStatusV4TimeProcess}  = gettimeofday() - $stopwatch;
    FordpassVehicle_UpdateInternals($hash);

    if( $errorMsg eq "" )
    {
      # if there is a callback then call it
      if( defined($callbackSuccess) )
      {
        Log3($name, 4, "FordpassVehicle_GetStatusV4($name) - callbackSuccess");
        $callbackSuccess->();
      }
    }
    else
    {
      readingsSingleUpdate( $hash, "state", $errorMsg, 1 );

      # if there is a callback then call it
      if( defined($callbackFail) )
      {
        Log3($name, 4, "FordpassVehicle_GetStatusV4($name) - callbackFail");
        $callbackFail->();
      }
    }
  }; 

  my $vehicleId = $hash->{VEHICLEID};

  if(defined($vehicleId))
  {
    my $header = 
      "accept: */*\n" .
      "content-type: application/json";

    my $param = {};
    $param->{method} = "GET";
    $param->{url} = $API_URL . "/vehicles/v4/" . $vehicleId . "/status";
    $param->{header} = $header;
#    $param->{data} = "{}";
#    $param->{httpversion} = "1.0";
#    $param->{ignoreredirects} = 0;
#    $param->{keepalive} = 1;
      
    $param->{resultCallback} = $resultCallback;
    $param->{timestampStart} = gettimeofday();
    
    $hash->{helper}{Telegram_GetStatusV4IOWrite} = strftime($TimeStampFormat, localtime($param->{timestampStart}));

    FordpassVehicle_IOWrite( $hash, $param );
  }
  else
  {
    # if there is a callback then call it
    if( defined($callbackFail) )
    {
      Log3($name, 4, "FordpassVehicle_GetStatusV4($name) - callbackFail");
      $callbackFail->();
    }
  }
}

##################################
# FordpassVehicle_GetCapability( $hash, $callbackSuccess, $callbackFail )
sub FordpassVehicle_GetCapability($;$$)
{
  # since 2022.05.10 the endpoint doesn't exist anymore. -> error 404 not found
  #
  
  my ( $hash, $callbackSuccess, $callbackFail ) = @_;
  my $name    = $hash->{NAME};

  # definition of the lambda function wich is called to process received data
  my $resultCallback = sub 
  {
    my ( $callbackparam, $data, $errorMsg ) = @_;

    my $stopwatch = gettimeofday();
    $hash->{helper}{Telegram_GetCapabilityTimeRequest} = $stopwatch - $callbackparam->{timestampStart};
    $hash->{helper}{Telegram_GetCapabilityCallback}    = strftime($TimeStampFormat, localtime($stopwatch));
    Log3($name, 4, "FordpassVehicle_GetCapability($name) - resultCallback");

    if( $errorMsg eq "" )
    {
      my $decode_json = eval { decode_json($data) };

      if($@)
      {
        Log3($name, 3, "FordpassVehicle_GetCapability($name) - JSON error while request: $@");

        if( AttrVal( $name, "debugJSON", 0 ) == 1 )
        {
          readingsBeginUpdate($hash);
          readingsBulkUpdate( $hash, "JSON_ERROR", $@, 1 );
          readingsBulkUpdate( $hash, "JSON_ERROR_STRING", "\"" . $data . "\"", 1 );
          readingsEndUpdate($hash, 1);
        }
        $errorMsg = "GetCapability: JSON_ERROR";
      }
      else
      {
        readingsBeginUpdate($hash);

        if($hash->{helper}{GenericReadings} ne "none")
        {
          FordpassVehicle_RefreshReadingsFromObject($hash, $DebugMarker . $DefaultSeperator . "Capability", $decode_json);
        }

        if(defined($decode_json) and
          ref($decode_json) eq "HASH")
        {
          my $result = $decode_json->{"result"};

          if(defined($result))
          {
  #            readingsBulkUpdateIfChanged($hash, "VehicleVersionDescription", "$currentVehicle->{versionDescription}")
  #              if (defined($currentVehicle->{versionDescription}) and $currentVehicle->{versionDescription} ne "null");
          }
        }
        else
        {
          $errorMsg = "UNKNOWN Data";
        }

        readingsEndUpdate($hash, 1);
      }
    }

    $hash->{helper}{Telegram_GetCapabilityCounter}++;
    $hash->{helper}{Telegram_GetCapabilityTimeProcess}  = gettimeofday() - $stopwatch;
    FordpassVehicle_UpdateInternals($hash);

    if( $errorMsg eq "" )
    {
      # if there is a callback then call it
      if( defined($callbackSuccess) )
      {
        Log3($name, 4, "FordpassVehicle_GetCapability($name) - callbackSuccess");
        $callbackSuccess->();
      }
    }
    else
    {
      readingsSingleUpdate( $hash, "state", $errorMsg, 1 );

      # if there is a callback then call it
      if( defined($callbackFail) )
      {
        Log3($name, 4, "FordpassVehicle_GetCapability($name) - callbackFail");
        $callbackFail->();
      }
    }
  }; 

  my $vehicleId = $hash->{VEHICLEID};

  if(defined($vehicleId))
  {
    my $header = 
      "accept: */*\n" .
      "content-type: application/json";

    my $param = {};
    $param->{method} = "GET";
    $param->{url} =  $USER_URL . "/capability/v1/vehicles/" . $vehicleId;
    $param->{header} = $header;
#    $param->{data} = "{}";
#    $param->{httpversion} = "1.0";
#    $param->{ignoreredirects} = 0;
#    $param->{keepalive} = 1;
      
    $param->{resultCallback} = $resultCallback;
    $param->{timestampStart} = gettimeofday();
    
    $hash->{helper}{Telegram_GetCapabilityIOWrite} = strftime($TimeStampFormat, localtime($param->{timestampStart}));

    FordpassVehicle_IOWrite( $hash, $param );
  }
  else
  {
    # if there is a callback then call it
    if( defined($callbackFail) )
    {
      Log3($name, 4, "FordpassVehicle_GetCapability($name) - callbackFail");
      $callbackFail->();
    }
  }
}

##################################
# FordpassVehicle_GetFuelConsumptionInfo( $hash, $callbackSuccess, $callbackFail )
sub FordpassVehicle_GetFuelConsumptionInfo($;$$)
{
  my ( $hash, $callbackSuccess, $callbackFail ) = @_;
  my $name    = $hash->{NAME};

  # definition of the lambda function wich is called to process received data
  my $resultCallback = sub 
  {
    my ( $callbackparam, $data, $errorMsg ) = @_;

    my $stopwatch = gettimeofday();
    $hash->{helper}{Telegram_GetFuelConsumptionInfosTimeRequest} = $stopwatch - $callbackparam->{timestampStart};
    $hash->{helper}{Telegram_GetFuelConsumptionInfosCallback}    = strftime($TimeStampFormat, localtime($stopwatch));
    Log3($name, 4, "FordpassVehicle_GetFuelConsumptionInfos($name) - resultCallback");

    if( $errorMsg eq "" )
    {
      my $decode_json = eval { decode_json($data) };

      if($@)
      {
        Log3($name, 3, "FordpassVehicle_GetFuelConsumptionInfos($name) - JSON error while request: $@");

        if( AttrVal( $name, "debugJSON", 0 ) == 1 )
        {
          readingsBeginUpdate($hash);
          readingsBulkUpdate( $hash, "JSON_ERROR", $@, 1 );
          readingsBulkUpdate( $hash, "JSON_ERROR_STRING", "\"" . $data . "\"", 1 );
          readingsEndUpdate($hash, 1);
        }
        $errorMsg = "GetFuelConsumptionInfos: JSON_ERROR";
      }
      else
      {
        readingsBeginUpdate($hash);

        if($hash->{helper}{GenericReadings} ne "none")
        {
          FordpassVehicle_RefreshReadingsFromObject($hash, $DebugMarker . $DefaultSeperator . "FuelConsumptionInfo", $decode_json);
        }
        
        if(defined($decode_json) and
          ref($decode_json) eq "HASH")
        {
          my $result = $decode_json->{"value"};

          if(defined($result))
          {
  #            readingsBulkUpdateIfChanged($hash, "VehicleVersionDescription", "$currentVehicle->{versionDescription}")
  #              if (defined($currentVehicle->{versionDescription}) and $currentVehicle->{versionDescription} ne "null");
          }
        }
        else
        {
          $errorMsg = "UNKNOWN Data";
        }

        readingsEndUpdate($hash, 1);
      }
    }

    $hash->{helper}{Telegram_GetFuelConsumptionInfosCounter}++;
    $hash->{helper}{Telegram_GetFuelConsumptionInfosTimeProcess}  = gettimeofday() - $stopwatch;
    FordpassVehicle_UpdateInternals($hash);

    if( $errorMsg eq "" )
    {
      # if there is a callback then call it
      if( defined($callbackSuccess) )
      {
        Log3($name, 4, "FordpassVehicle_GetFuelConsumptionInfos($name) - callbackSuccess");
        $callbackSuccess->();
      }
    }
    else
    {
      readingsSingleUpdate( $hash, "state", $errorMsg, 1 );

      # if there is a callback then call it
      if( defined($callbackFail) )
      {
        Log3($name, 4, "FordpassVehicle_GetFuelConsumptionInfos($name) - callbackFail");
        $callbackFail->();
      }
    }
  }; 

  my $vehicleId = $hash->{VEHICLEID};

  if(defined($vehicleId))
  {
    my $header = 
      "accept: */*\n" .
      "content-type: application/json";

    my $param = {};
    $param->{method} = "GET";
    $param->{url} =  $USER_URL . "/fuel-consumption-info/v1/reports/fuel?vin=" . $vehicleId;
    $param->{header} = $header;
#    $param->{data} = "{}";
#    $param->{httpversion} = "1.0";
#    $param->{ignoreredirects} = 0;
#    $param->{keepalive} = 1;
      
    $param->{resultCallback} = $resultCallback;
    $param->{timestampStart} = gettimeofday();
    
    $hash->{helper}{Telegram_GetFuelConsumptionInfosIOWrite} = strftime($TimeStampFormat, localtime($param->{timestampStart}));

    FordpassVehicle_IOWrite( $hash, $param );
  }
  else
  {
    # if there is a callback then call it
    if( defined($callbackFail) )
    {
      Log3($name, 4, "FordpassVehicle_GetFuelConsumptionInfos($name) - callbackFail");
      $callbackFail->();
    }
  }
}

##################################
# FordpassVehicle_GetRecalls( $hash, $callbackSuccess, $callbackFail )
sub FordpassVehicle_GetRecalls($;$$)
{
  my ( $hash, $callbackSuccess, $callbackFail ) = @_;
  my $name    = $hash->{NAME};

  # definition of the lambda function wich is called to process received data
  my $resultCallback = sub 
  {
    my ( $callbackparam, $data, $errorMsg ) = @_;

    my $stopwatch = gettimeofday();
    $hash->{helper}{Telegram_GetRecallsTimeRequest} = $stopwatch - $callbackparam->{timestampStart};
    $hash->{helper}{Telegram_GetRecallsCallback}    = strftime($TimeStampFormat, localtime($stopwatch));
    Log3($name, 4, "FordpassVehicle_GetRecalls($name) - resultCallback");

    if( $errorMsg eq "" )
    {
      my $decode_json = eval { decode_json($data) };

      if($@)
      {
        Log3($name, 3, "FordpassVehicle_GetRecalls($name) - JSON error while request: $@");

        if( AttrVal( $name, "debugJSON", 0 ) == 1 )
        {
          readingsBeginUpdate($hash);
          readingsBulkUpdate( $hash, "JSON_ERROR", $@, 1 );
          readingsBulkUpdate( $hash, "JSON_ERROR_STRING", "\"" . $data . "\"", 1 );
          readingsEndUpdate($hash, 1);
        }
        $errorMsg = "GetRecalls: JSON_ERROR";
      }
      else
      {
        readingsBeginUpdate($hash);
        
        if($hash->{helper}{GenericReadings} ne "none")
        {
          FordpassVehicle_RefreshReadingsFromObject($hash, $DebugMarker . $DefaultSeperator . "Recalls", $decode_json);
        }
        
        if(defined($decode_json) and
          ref($decode_json) eq "HASH")
        {
          my $result = $decode_json->{"result"};

          if(defined($result))
          {
  #            readingsBulkUpdateIfChanged($hash, "VehicleVersionDescription", "$currentVehicle->{versionDescription}")
  #              if (defined($currentVehicle->{versionDescription}) and $currentVehicle->{versionDescription} ne "null");
          }
        }
        else
        {
          $errorMsg = "UNKNOWN Data";
        }

        readingsEndUpdate($hash, 1);
      }
    }

    $hash->{helper}{Telegram_GetRecallsCounter}++;
    $hash->{helper}{Telegram_GetRecallsTimeProcess}  = gettimeofday() - $stopwatch;
    FordpassVehicle_UpdateInternals($hash);

    if( $errorMsg eq "" )
    {
      # if there is a callback then call it
      if( defined($callbackSuccess) )
      {
        Log3($name, 4, "FordpassVehicle_GetRecalls($name) - callbackSuccess");
        $callbackSuccess->();
      }
    }
    else
    {
      readingsSingleUpdate( $hash, "state", $errorMsg, 1 );

      # if there is a callback then call it
      if( defined($callbackFail) )
      {
        Log3($name, 4, "FordpassVehicle_GetRecalls($name) - callbackFail");
        $callbackFail->();
      }
    }
  }; 

  my $vehicleId = $hash->{VEHICLEID};

  if(defined($vehicleId))
  {
    my $header = 
      "accept: */*\n" .
      "content-type: application/json";

    my $param = {};
    $param->{method} = "GET";
    $param->{url} =  $USER_URL . "/recall/v2/recalls?vin=" . $vehicleId . "&language=DE-DE&region=DEU&country=DEU";
    $param->{header} = $header;
#    $param->{data} = "{}";
#    $param->{httpversion} = "1.0";
#    $param->{ignoreredirects} = 0;
#    $param->{keepalive} = 1;
      
    $param->{resultCallback} = $resultCallback;
    $param->{timestampStart} = gettimeofday();
    
    $hash->{helper}{Telegram_GetRecallsIOWrite} = strftime($TimeStampFormat, localtime($param->{timestampStart}));

    FordpassVehicle_IOWrite( $hash, $param );
  }
  else
  {
    # if there is a callback then call it
    if( defined($callbackFail) )
    {
      Log3($name, 4, "FordpassVehicle_GetRecalls($name) - callbackFail");
      $callbackFail->();
    }
  }
}

##################################
# FordpassVehicle_GetTest( $hash, $callbackSuccess, $callbackFail )
sub FordpassVehicle_GetTest($;$$)
{
  my ( $hash, $callbackSuccess, $callbackFail ) = @_;
  my $name    = $hash->{NAME};

  # definition of the lambda function wich is called to process received data
  my $resultCallback = sub 
  {
    my ( $callbackparam, $data, $errorMsg ) = @_;

    my $stopwatch = gettimeofday();
    $hash->{helper}{Telegram_GetTestTimeRequest} = $stopwatch - $callbackparam->{timestampStart};
    $hash->{helper}{Telegram_GetTestCallback}    = strftime($TimeStampFormat, localtime($stopwatch));
    Log3($name, 4, "FordpassVehicle_GetTest($name) - resultCallback");

    if( $errorMsg eq "" )
    {
      my $decode_json = eval { decode_json($data) };

      if($@)
      {
        Log3($name, 3, "FordpassVehicle_GetTest($name) - JSON error while request: $@");

        if( AttrVal( $name, "debugJSON", 0 ) == 1 )
        {
          readingsBeginUpdate($hash);
          readingsBulkUpdate( $hash, "JSON_ERROR", $@, 1 );
          readingsBulkUpdate( $hash, "JSON_ERROR_STRING", "\"" . $data . "\"", 1 );
          readingsEndUpdate($hash, 1);
        }
        $errorMsg = "GetTest: JSON_ERROR";
      }
      else
      {
        readingsBeginUpdate($hash);

        if($hash->{helper}{GenericReadings} ne "none")
        {
          FordpassVehicle_RefreshReadingsFromObject($hash, $DebugMarker . $DefaultSeperator . "Test", $decode_json);
        }
        
        if(defined($decode_json) and
          ref($decode_json) eq "HASH")
        {
          my $result = $decode_json->{"result"};

          if(defined($result))
          {
  #            readingsBulkUpdateIfChanged($hash, "VehicleVersionDescription", "$currentVehicle->{versionDescription}")
  #              if (defined($currentVehicle->{versionDescription}) and $currentVehicle->{versionDescription} ne "null");
          }
        }
        else
        {
          $errorMsg = "UNKNOWN Data";
        }

        readingsEndUpdate($hash, 1);
      }
    }

    $hash->{helper}{Telegram_GetTestCounter}++;
    $hash->{helper}{Telegram_GetTestTimeProcess}  = gettimeofday() - $stopwatch;
    FordpassVehicle_UpdateInternals($hash);

    if( $errorMsg eq "" )
    {
      # if there is a callback then call it
      if( defined($callbackSuccess) )
      {
        Log3($name, 4, "FordpassVehicle_GetTest($name) - callbackSuccess");
        $callbackSuccess->();
      }
    }
    else
    {
      readingsSingleUpdate( $hash, "state", $errorMsg, 1 );

      # if there is a callback then call it
      if( defined($callbackFail) )
      {
        Log3($name, 4, "FordpassVehicle_GetTest($name) - callbackFail");
        $callbackFail->();
      }
    }
  }; 

  my $vehicleId = $hash->{VEHICLEID};

  if(defined($vehicleId))
  {
    my $header = 
      "accept: */*\n" .
      "content-type: application/json";
  
    my $data = 
    {
#      "dashboardRefreshRequest" => "$vehicleId"
    };
  
    my $param = {};
    $param->{method} = "GET";
    $param->{url}    = $USER_URL . "/expdashboard/v1/";
    $param->{header} = $header;
    $param->{data}    = encode_json($data);
#    $param->{data} = "{}";
#    $param->{httpversion} = "1.0";
#    $param->{ignoreredirects} = 0;
#    $param->{keepalive} = 1;
      
    $param->{resultCallback} = $resultCallback;
    $param->{timestampStart} = gettimeofday();
    
    $hash->{helper}{Telegram_GetTestIOWrite} = strftime($TimeStampFormat, localtime($param->{timestampStart}));

    FordpassVehicle_IOWrite( $hash, $param );
  }
  else
  {
    # if there is a callback then call it
    if( defined($callbackFail) )
    {
      Log3($name, 4, "FordpassVehicle_GetTest($name) - callbackFail");
      $callbackFail->();
    }
  }
}

#################################
# FordpassVehicle_SetCommand( $hash, $command, $setValue, $callbackSuccess, $callbackFail )
sub FordpassVehicle_SetCommand($$$;$$)
{
  my ( $hash, $command, $setValue, $callbackSuccess, $callbackFail ) = @_;
  my $name    = $hash->{NAME};

  # definition of the lambda function wich is called to process received data
  my $resultCallback = sub 
  {
    my ( $callbackparam, $data, $errorMsg ) = @_;

    my $stopwatch = gettimeofday();
    $hash->{helper}{Telegram_SetCommandTimeRequest}  = $stopwatch - $callbackparam->{timestampStart};
    $hash->{helper}{Telegram_SetCommandCallback}     = strftime($TimeStampFormat, localtime($stopwatch));
    Log3($name, 4, "FordpassVehicle_SetCommand($name) - resultCallback");

    if( $errorMsg eq "" )
    {
      my $decode_json = eval { decode_json($data) };
    
      if($@)
      {
        Log3($name, 3, "FordpassVehicle_SetCommand($name) - JSON error while request: $@");

        if( AttrVal( $name, "debugJSON", 0 ) == 1 )
        {
          readingsBeginUpdate($hash);
          readingsBulkUpdate( $hash, "JSON_ERROR", $@, 1 );
          readingsBulkUpdate( $hash, "JSON_ERROR_STRING", "\"" . $data . "\"", 1 );
          readingsEndUpdate($hash, 1);
        }
        $errorMsg = "SETAPPLIANCECommand_JSON_ERROR";
      }
      else
      {
        readingsBeginUpdate($hash);
        
        if($hash->{helper}{GenericReadings} ne "none")
        {
          FordpassVehicle_RefreshReadingsFromObject($hash, $DebugMarker . $DefaultSeperator . "SetCommand_" . $command, $decode_json);
        }
        
        if(defined($decode_json) and
          ref($decode_json) eq "HASH")
        {
          my $result = $decode_json->{"value"};

          if(defined($result))
          {
  #            readingsBulkUpdateIfChanged($hash, "VehicleVersionDescription", "$currentVehicle->{versionDescription}")
  #              if (defined($currentVehicle->{versionDescription}) and $currentVehicle->{versionDescription} ne "null");
          }
        }
        else
        {
          $errorMsg = "UNKNOWN Data";
        }

        readingsEndUpdate($hash, 1);
      }
    }

    $hash->{helper}{Telegram_SetCommandCounter}++;
    $hash->{helper}{Telegram_SetCommandTimeProcess}  = gettimeofday() - $stopwatch;
    FordpassVehicle_UpdateInternals($hash);

    if( $errorMsg eq "" )
    {
      # if there is a callback then call it
      if( defined($callbackSuccess) )
      {
        Log3($name, 4, "FordpassVehicle_SetCommand($name) - callbackSuccess");
        $callbackSuccess->();
      }
    }
    else
    {
      readingsSingleUpdate( $hash, "state", $errorMsg, 1 );

      # if there is a callback then call it
      if( defined($callbackFail) )
      {
        Log3($name, 4, "FordpassVehicle_SetCommand($name) - callbackFail");
        $callbackFail->();
      }
    }
  }; 

  my $vehicleId = $hash->{VEHICLEID};

  if(defined($vehicleId))
  {
    my $method = "DELETE";
    if(defined($setValue))
    {
      if(lc $setValue eq "true" or
        lc $setValue eq "on" or
        $setValue != 0)
      {
        $method = "PUT";
      }
    }
    
    my $header = 
      "accept: */*\n" .
      "content-type: application/json";

    my $param = {};
    $param->{method} = $method;
    $param->{url} = $API_URL . "/vehicles/v2/" . $vehicleId . "/" . $command;
    $param->{header} = $header;
    $param->{data} = "{}";
#    $param->{httpversion} = "1.0";
#    $param->{ignoreredirects} = 0;
#    $param->{keepalive} = 1;
      
    $param->{resultCallback} = $resultCallback;
    $param->{timestampStart} = gettimeofday();
    
    $hash->{helper}{Telegram_SetCommandIOWrite} = strftime($TimeStampFormat, localtime($param->{timestampStart}));

    FordpassVehicle_IOWrite( $hash, $param );
  }
  else
  {
    # if there is a callback then call it
    if( defined($callbackFail) )
    {
      Log3($name, 4, "FordpassVehicle_SetCommand($name) - callbackFail");
      $callbackFail->();
    }
  }
}

##################################
# FordpassVehicle_RefreshReadingsFromObject
sub FordpassVehicle_RefreshReadingsFromObject($$$)
{
  my ($hash, $objectName, $objectValue) = @_;
  my $name = $hash->{NAME};

  if(!defined($objectValue))
  {
    if($hash->{helper}{GenericReadings} eq "full") # is check for invalid/unset values enabled?
    {
      readingsBulkUpdate($hash, makeReadingName($objectName), "");
    }
  } 
  elsif(ref($objectValue) eq "HASH")
  {
    my %hash = %{$objectValue};
    
    # iterate through all key-value-pairs of the hash
    while (my ($key, $value) = each(%hash))
    {
      my $currentName = $objectName . $DefaultSeperator. $key;

      # recursive call
      FordpassVehicle_RefreshReadingsFromObject($hash, $currentName, $value);
    }
  }
  elsif(ref($objectValue) eq "ARRAY")
  {
    my @array = @{$objectValue};
    
    my $arrayLength = @array - 1;
    my $stringLength = length "$arrayLength";
    my $format = "%0" . $stringLength . "d";
    # iterate through all values of the array
    for my $index (0 .. $arrayLength) 
    {
      my $currentName = $objectName . $DefaultSeperator . sprintf($format, $index);

      # recursive call
      FordpassVehicle_RefreshReadingsFromObject($hash, $currentName, $array[$index]);
    }
  }
  else
  {
    if($hash->{helper}{GenericReadings} ne "full" or # is check for invalid/unset values enabled?
      $objectValue ne "null")                              #
    {
      readingsBulkUpdate($hash, makeReadingName($objectName), "$objectValue");
    }
  }
}


##################################
# FordpassVehicle_Store
sub FordpassVehicle_Store($$$$)
{
  my ($hash, $sender, $key, $value) = @_;
  my $type = $hash->{TYPE};
  my $name = $hash->{NAME};

  my $deviceKey = $type . "_" . $name . "_" . $key;

  my $setKeyError = setKeyValue($deviceKey, $value);
  if(defined($setKeyError))
  {
    Log3($name, 3, "$sender($name) - setKeyValue $deviceKey error: $setKeyError");
  }
  else
  {
    Log3($name, 5, "$sender($name) - setKeyValue: $deviceKey -> $value");
  }
}

##################################
# FordpassVehicle_Restore
sub FordpassVehicle_Restore($$$$)
{
  my ($hash, $sender, $key, $defaultvalue) = @_;
  my $type = $hash->{TYPE};
  my $name = $hash->{NAME};

  my $deviceKey = $type . "_" . $name . "_" . $key;

  my ($getKeyError, $value) = getKeyValue($deviceKey);
  $value = $defaultvalue
    if(defined($getKeyError) or
      not defined ($value));

  if(defined($getKeyError))
  {
    Log3($name, 3, "$sender($name) - getKeyValue $deviceKey error: $getKeyError");
  }
  else
  {
    Log3($name, 5, "$sender($name) - getKeyValue: $deviceKey -> $value");
  }

  return $value;
}

##################################
# FordpassVehicle_StoreRename($hash, $sender, $old_name, $key)
sub FordpassVehicle_StoreRename($$$$)
{
  my ($hash, $sender, $old_name, $key) = @_;
  my $type = $hash->{TYPE};
  my $new_name = $hash->{NAME};

  my $old_deviceKey = $type . "_" . $old_name . "_" . $key;
  my $new_deviceKey = $type . "_" . $new_name . "_" . $key;

  my ($getKeyError, $value) = getKeyValue($old_deviceKey);

  if(defined($getKeyError))
  {
    Log3($new_name, 3, "$sender($new_name) - getKeyValue $old_deviceKey error: $getKeyError");
  }
  else
  {
    Log3($new_name, 5, "$sender($new_name) - getKeyValue: $old_deviceKey -> $value");

    my $setKeyError = setKeyValue($new_deviceKey, $value);
    if(defined($setKeyError))
    {
      Log3($new_name, 3, "$sender($new_name) - setKeyValue $new_deviceKey error: $setKeyError");
    }
    else
    {
      Log3($new_name, 5, "$sender($new_name) - setKeyValue: $new_deviceKey -> $value");
    }
  }

  # delete old key
  setKeyValue($old_deviceKey, undef);
}

##################################
# FordpassVehicle_GetLTZFromUTC($)
sub FordpassVehicle_GetLTZFromUTC($)
{
  my ( $timestampUTCString ) = @_;

  if(defined($timestampUTCString) and
    $timestampUTCString ne "")
  {
    # 03-07-2022 05:02:02 Format ist Month-Day-Year
    my ($datehour, $rest) = split(/:/,$timestampUTCString,2);
    my ($month, $day, $year, $hour) = $datehour =~ /(\d\d)-(\d\d)-(\d+)\s+(\d\d)/;
    
    #  proto: $time = timegm($sec, $min, $hour, $mday, $mon, $year);
    my $epoch = timegm(0, 0, $hour, $day, $month-1, $year);
    
    #  proto: ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
    my ($lyear, $lmonth, $lday, $lhour, $isdst) =  (localtime($epoch))[5,4,3,2,-1];

    return sprintf("%04d-%02d-%02d %02d:%s", $lyear + 1900, $lmonth + 1, $lday, $lhour, $rest);
  }
  else
  {
    return undef;
  }
}

1;

=pod

=item device
=item summary Module wich represents a vehicle of the Ford-Cloud

=begin html

<a name="FordpassVehicle"></a>
<h3>FordpassVehicle</h3>
<ul>
    In combination with FHEM module <a href="#FordpassAccount">FordpassAccount</a> this module represents a vehicle.<br>
    It communicates over <a href="#FordpassAccount">FordpassAccount</a> to the <b>Ford-Cloud</b> to get some states and measured values like 
    odometer, ignition state, door and window states, tire pressures, battery level, oil state, fuel level and distance to empty and location.<br> 
    And you can set some commands i.E. lock/unlock the doors or start/stop the engine (if supported).<br>
    <br>
    Once the FordpassAccount device is created, the registered devices are recognized and created automatically as FordpassVehicles in FHEM.<br>
    <br>
    <br>
    <b>Notes</b>
    <ul>
      <li>This module communicates with the <b>Ford-Cloud</b> - you have to be registered.
      </li>
      <li>If you want to get the gps location of your vehicle you have to permit location access in the app.
      </li>
      <li>There is a <b>debug-mode</b> you can enable/disable with the <b>attribute debug</b> to see more internals.
      </li>
    </ul>
    <br>
    <a name="FordpassVehicle"></a><b>Define</b>
    <ul>
      <code><B>define &lt;name&gt; FordpassVehicle &lt;FordpassAccount&gt; &lt;vehicleId&gt;</B></code>
      <br><br>
      Example:<br>
      <ul>
        <code>
        define myCar FordpassVehicle myFordAccound XYZ00ABCDEFGH01234<br>
        <br>
        </code>
      </ul>
    </ul><br>
    <br> 
    <a name="FordpassVehicle"></a><b>Set</b>
    <ul>
      <li><a name="FordpassVehicleupdate">update</a><br>
        Update configuration and values.<br>
        <br>
        <code>
          set &lt;name&gt; update
        </code>
      </li>
      <br>
      <li><a name="FordpassVehicleclearreadings">clearreadings</a><br>
        Clear all/debug readings of the module.<br>
        <br>
        <code>
          set &lt;name&gt; clearreadings Dbg.*
        </code>
      </li>
      <br>
      <li><a name="FordpassVehiclerefreshStatus">refreshStatus</a><br>
        Refresh status.<br>
        <br>
        <code>
          set &lt;name&gt; refreshStatus
        </code>
      </li>
      <br>
      <li><a name="FordpassVehicledoor">door</a><br>
        Lock/unlock doors if supported by vehicle.<br>
        <br>
        <code>
          set &lt;name&gt; door lock
        </code>
        <br>
        <code>
          set &lt;name&gt; door unlock
        </code>
      </li>
      <br>
      <li><a name="FordpassVehicleengine">engine</a><br>
        Start/stop engine if supported by vehicle.<br>
        <br>
        <code>
          set &lt;name&gt; engine start
        </code>
        <br>
        <code>
          set &lt;name&gt; engine stop
        </code>
      </li>
      <br>
    </ul>
    <br>
    <a name="FordpassVehicleattr"></a><b>Attributes</b><br>
    <ul>
      <li><a name="FordpassVehicleintervalslow">intervalslow</a><br>
        Interval in seconds to poll for valeus.
      </li>
      <br>
      <li><a name="FordpassVehicleintervalfast">intervalfast</a><br>
        Interval in seconds to poll for vales .
      </li>
      <br>
      <li><a name="FordpassVehicledisable">disable</a><br>
        If <b>0</b> (default) then FordpassVehicle is <b>enabled</b>.<br>
        If <b>1</b> then FordpassVehicle is <b>disabled</b> - no communication to the Ford-Cloud will be done.<br>
      </li>
      <br>
      <li><a name="FordpassVehicledebug">debug</a><br>
        If <b>0</b> (default) debugging mode is <b>disabled</b>.<br>
        If <b>1</b> debugging mode is <b>enabled</b> - more internals and commands are shown.<br>
      </li>
      <br>
      <li><a name="FordpassVehicledebugJSON">debugJSON</a><br>
        If <b>0</b> (default)<br>
        If <b>1</b> if communication fails the json-payload of incoming telegrams is set to a reading.<br>
      </li>
      <br>
      <li><a name="FordpassVehiclegenericReadings">genericReadings</a><br>
        Control wich readings are shown.
        <ul>
          <li>
          <b>none</b> - (default) some certain values are mapped to a reading 
          </li>
          <li>
          <b>valid</b> - all valid json entries are mapped to a reading
          </li>
          <li>
          <b>full</b> - all json entries are mapped to a reading
          </li>
        </ul>
      </li>
      <br>
    </ul><br>
    <br>
</ul>

=end html

=for :application/json;q=META.json 74_FordpassVehicle.pm
{
  "abstract": "Modul wich represents Fordpass Vehicle",
  "x_lang": {
    "de": {
      "abstract": "Modul, das ein Fordpass Vehicle darstellt"
    }
  },
  "keywords": [
    "fhem-mod-device",
    "fhem-core",
    "Ford",
    "Fordpass",
    "Smart"
  ],
  "release_status": "stable",
  "license": "GPL_2",
  "author": [
    "J0EK3R <J0EK3R@gmx.net>"
  ],
  "x_fhem_maintainer": [
    "J0EK3R"
  ],
  "x_fhem_maintainer_github": [
    "J0EK3R@gmx.net"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.016, 
        "Meta": 0,
        "JSON": 0,
        "Time::Local": 0
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  }
}
=end :application/json;q=META.json

=cut
