###############################################################################
#
# Developed with eclipse
#
#  (c) 2019 Copyright: J.K. (J0EK3R at gmx dot net)
#  All rights reserved
#
#   Special thanks goes to committers:
#
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
# $Id: 73_FordpassAccount.pm 201 2020-04-04 06:14:00Z J0EK3R $
#
###############################################################################

package main;

my $VERSION = "0.0.10";

use strict;
use warnings;

my $missingModul = "";

use FHEM::Meta;
eval {use HTML::Entities;1 or $missingModul .= "HTML::Entities "};
eval {use JSON;1 or $missingModul .= "JSON "};

#use HttpUtils;

#########################
# Forward declaration
sub FordpassAccount_Initialize($);
sub FordpassAccount_Define($$);
sub FordpassAccount_Undef($$);
sub FordpassAccount_Delete($$);
sub FordpassAccount_Rename(@);
sub FordpassAccount_Attr(@);
sub FordpassAccount_Notify($$);
sub FordpassAccount_Set($@);
sub FordpassAccount_Write($$);

sub FordpassAccount_TimerExecute($);
sub FordpassAccount_TimerRemove($);
sub FordpassAccount_UpdateInternals($);
sub FordpassAccount_Connect($;$$);
sub FordpassAccount_ClearLogin($);
sub FordpassAccount_Login($;$$);
sub FordpassAccount_Login_GetAuthCode($;$$);
sub FordpassAccount_Login_GetToken($;$$);

sub FordpassAccount_Update($;$$);
sub FordpassAccount_GetDashboard($;$$);

sub FordpassAccount_RequestParam($$);
sub FordpassAccount_SendReceive($$);
sub FordpassAccount_RequestErrorHandling($$$);

sub FordpassAccount_ProcessSetCookies($@);
sub FordpassAccount_Header_AddAuthorization($$);
sub FordpassAccount_Header_AddCountryCode($$);
sub FordpassAccount_Header_AddLocale($$);
sub FordpassAccount_Header_AddApplicationId($$);
sub FordpassAccount_Header_AddUserAgent($$);
sub FordpassAccount_Header_AddCookies($$);

sub FordpassAccount_RefreshReadingsFromObject($$$);

sub FordpassAccount_StorePassword($$);
sub FordpassAccount_ReadPassword($);
sub FordpassAccount_DeletePassword($);

my $DefaultRetries      = 3;                              # default number of retries
my $DefaultInterval     = 60;                             # default value for the polling interval in seconds
my $DefaultTimeout      = 5;                              # default value for response timeout in seconds

my $DefaultSeperator    = "_";
my $DebugMarker         = "Dbg";

my $DefaultRegion             = "EU";
my $DefaultHeaderCountryCode  = "DEU";
my $DefaultHeaderUserAgent    = "FordPass/5 CFNetwork/1240.0.4 Darwin/20.6.0";
my $DefaultHeaderLocale       = "DE-DE";

my $API_URL     = 'https://usapi.cv.ford.com/api';  # US Connected Vehicle api
my $VEHICLE_URL = 'https://services.cx.ford.com/api';
my $USER_URL    = 'https://api.mps.ford.com/api';
my $TOKEN_URL   = 'https://sso.ci.ford.com/oidc/endpoint/default/token';

my %regions = 
(
  "US"  => "71A3AD0A-CF46-4CCF-B473-FC7FE5BC4592",
  "CA"  => "71A3AD0A-CF46-4CCF-B473-FC7FE5BC4592",
  "EU"  => "1E8C7794-FF5F-49BC-9596-A1E0C86C5B19",
  "AU"  => "5C80A6BB-CF0D-4A30-BDBF-FC804B5C1A98",
);

my $TimeStampFormat = "%Y-%m-%dT%I:%M:%S";

my $ReloginOffset_s = -60;                             # (negative) timespan in seconds to add "expires_in" timespan to relogin

#####################################
# FordpassAccount_Initialize( $hash )
sub FordpassAccount_Initialize($)
{
  my ( $hash ) = @_;

  $hash->{DefFn}    = \&FordpassAccount_Define;
  $hash->{UndefFn}  = \&FordpassAccount_Undef;
  $hash->{DeleteFn} = \&FordpassAccount_Delete;
  $hash->{RenameFn} = \&FordpassAccount_Rename;
  $hash->{AttrFn}   = \&FordpassAccount_Attr;
  $hash->{NotifyFn} = \&FordpassAccount_Notify;
  $hash->{SetFn}    = \&FordpassAccount_Set;
  $hash->{WriteFn}  = \&FordpassAccount_Write;

  $hash->{Clients}   = "FordpassVehicle";
  $hash->{MatchList} = { "1:FordpassVehicle" => "FORDPASSVEHICLE_.*" };

  $hash->{AttrList} = 
    "debug:0,1 " . 
    "debugJSON:0,1 " . 
    "autocreatedevices:1,0 " . 
    "disable:0,1 " . 
    "genericReadings:none,valid,full " . 
    "countrycode " . 
#    "region:US,CA,EU,AU " . # AU not working yet
    "region:US,CA,EU " . 
    "interval " . 
    "fordpassUser " . 
    $readingFnAttributes;

  foreach my $d ( sort keys %{ $modules{FordpassAccount}{defptr} } )
  {
    my $hash = $modules{FordpassAccount}{defptr}{$d};
    $hash->{VERSION} = $VERSION;
  }

  return FHEM::Meta::InitMod( __FILE__, $hash );
}

#####################################
# FordpassAccount_Define( $hash, $def )
sub FordpassAccount_Define($$)
{
  my ( $hash, $def ) = @_;

  my @a = split( "[ \t][ \t]*", $def );

  return $@
    unless ( FHEM::Meta::SetInternals($hash) );

  return "wrong number of parameters: define <NAME> FordpassAccount"
    if ( @a != 2 );

  return "Cannot define FordpassAccount. Perl modul " . ${missingModul} . " is missing."
    if ($missingModul);

  my $name = $a[0];
  $hash->{VERSION}                        = $VERSION;
  $hash->{NOTIFYDEV}                      = "global,$name";
  $hash->{INTERVAL}                       = $DefaultInterval;
  $hash->{TIMEOUT}                        = $DefaultTimeout;
  $hash->{RETRIES}                        = $DefaultRetries;
  $hash->{REQUESTID}                      = 0;

  $hash->{helper}{RESPONSECOUNT_ERROR}    = 0;
  $hash->{helper}{RESPONSESUCCESSCOUNT}   = 0; # statistics
  $hash->{helper}{RESPONSEERRORCOUNT}     = 0; # statistics
  $hash->{helper}{RESPONSETOTALTIMESPAN}  = 0; # statistics
  $hash->{helper}{access_token}           = "none";
  $hash->{helper}{LoginInProgress}        = "0";
  $hash->{helper}{LoginCounter}           = 0;
  $hash->{helper}{LoginErrCounter}        = 0;
  $hash->{helper}{DEBUG}                  = "0";
  $hash->{helper}{IsDisabled}             = "0";
  $hash->{helper}{GenericReadings}        = "none";
  $hash->{helper}{AUTOCREATEDEVICES}      = "0";
  $hash->{helper}{region}                 = $DefaultRegion;
  $hash->{helper}{header_applicationid}   = $regions{$hash->{helper}{region}};
  $hash->{helper}{header_countrycode}     = $DefaultHeaderCountryCode;
  $hash->{helper}{header_locale}          = $DefaultHeaderLocale;;
  $hash->{helper}{header_useragent}       = $DefaultHeaderUserAgent;
  
  # set default Attributes
  if (AttrVal($name, "room", "none" ) eq "none")
  {
    CommandAttr(undef, $name . " room Ford");
  }

  readingsSingleUpdate( $hash, "state", "initialized", 1 );

  Log3($name, 3, "FordpassAccount_Define($name) - defined FordpassAccount");

  $modules{FordpassAccount}{defptr}{ACCOUNT} = $hash;

  return undef;
}

#####################################
# FordpassAccount_Undef( $hash, $name )
sub FordpassAccount_Undef($$)
{
  my ( $hash, $name ) = @_;

  FordpassAccount_TimerRemove($hash);

  delete $modules{FordpassAccount}{defptr}{ACCOUNT}
    if ( defined( $modules{FordpassAccount}{defptr}{ACCOUNT} ) );

  return undef;
}

#####################################
# FordpassAccount_Delete( $hash, $name )
sub FordpassAccount_Delete($$)
{
  my ( $hash, $name ) = @_;

  setKeyValue( $hash->{TYPE} . "_" . $name . "_passwd", undef );
  return undef;
}

#####################################
# FordpassAccount_Rename( $new, $old )
sub FordpassAccount_Rename(@)
{
  my ( $new, $old ) = @_;
  my $hash = $defs{$new};

  FordpassAccount_StorePassword( $hash, FordpassAccount_ReadPassword($hash) );
  setKeyValue( $hash->{TYPE} . "_" . $old . "_passwd", undef );

  return undef;
}


#####################################
# FordpassAccount_Attr($cmd, $name, $attrName, $attrVal)
sub FordpassAccount_Attr(@)
{
  my ( $cmd, $name, $attrName, $attrVal ) = @_;
  my $hash = $defs{$name};

  Log3($name, 4, "FordpassAccount_Attr($name) - AttrName \"$attrName\" : \"$attrVal\"");

  # Attribute "disable"
  if ( $attrName eq "disable" )
  {
    if ( $cmd eq "set" and 
      $attrVal eq "1" )
    {
      Log3($name, 3, "FordpassAccount_Attr($name) - disabled");

      $hash->{helper}{IsDisabled} = "1";
      
      FordpassAccount_TimerRemove($hash);

      readingsBeginUpdate($hash);
      readingsBulkUpdateIfChanged( $hash, "state", "inactive", 1 );
      readingsEndUpdate( $hash, 1 );
    } 
    else
    {
      Log3($name, 3, "FordpassAccount_Attr($name) - enabled");

      $hash->{helper}{IsDisabled} = "0";

      readingsBeginUpdate($hash);
      readingsBulkUpdateIfChanged( $hash, "state", "active", 1 );
      readingsEndUpdate( $hash, 1 );
      
      FordpassAccount_TimerExecute($hash);
    }
  }

  # Attribute "interval"
  elsif ( $attrName eq "interval" )
  {
    if ( $cmd eq "set" )
    {
      return "Interval must be greater than 0"
        unless ( $attrVal > 0 );

      Log3($name, 3, "FordpassAccount_Attr($name) - set interval: $attrVal");

      FordpassAccount_TimerRemove($hash);

      $hash->{INTERVAL} = $attrVal;

      FordpassAccount_TimerExecute($hash);      
    } 
    elsif ( $cmd eq "del" )
    {
      Log3($name, 3, "FordpassAccount_Attr($name) - delete User interval and set default: $DefaultInterval");

      FordpassAccount_TimerRemove($hash);
    
      $hash->{INTERVAL} = $DefaultInterval;

      FordpassAccount_TimerExecute($hash);      
    }
  }

  # Attribute "debug"
  elsif ( $attrName eq "debug" )
  {
    if ( $cmd eq "set")
    {
      Log3($name, 3, "FordpassAccount_Attr($name) - debugging enabled");

      $hash->{helper}{DEBUG} = "$attrVal";
      FordpassAccount_UpdateInternals($hash);
    } 
    elsif ( $cmd eq "del" )
    {
      Log3($name, 3, "FordpassAccount_Attr($name) - debugging disabled");

      $hash->{helper}{DEBUG} = "0";
      FordpassAccount_UpdateInternals($hash);
    }
  }

  # Attribute "genericReadings"
  if( $attrName eq "genericReadings" )
  {
    if($cmd eq "set" and 
      ($attrVal eq "valid" or $attrVal eq "full"))
    {
      $hash->{helper}{GenericReadings} = $attrVal;

      Log3($name, 3, "FordpassAccount_Attr($name) - set genericReadings: $attrVal");
    } 
    else
    {
      $hash->{helper}{GenericReadings} = "none";

      Log3($name, 3, "FordpassAccount_Attr($name) - set genericReadings: none");
    }
    FordpassAccount_UpdateInternals($hash);
  }

  # Attribute "countrycode"
  elsif ( $attrName eq "countrycode" )
  {
    if ( $cmd eq "set")
    {
      $hash->{helper}{header_countrycode} = "$attrVal";
      Log3($name, 3, "FordpassAccount_Attr($name) - countrycode set to \"" . $hash->{helper}{header_countrycode} . "\"");

      FordpassAccount_UpdateInternals($hash);
      FordpassAccount_ClearLogin($hash);
      FordpassAccount_TimerExecute($hash);
    } 
    elsif ( $cmd eq "del" )
    {
      $hash->{helper}{header_countrycode} = $DefaultHeaderCountryCode;

      Log3($name, 3, "FordpassAccount_Attr($name) - countrycode set to \"" . $hash->{helper}{header_countrycode} . "\"");

      FordpassAccount_UpdateInternals($hash);
      FordpassAccount_ClearLogin($hash);
      FordpassAccount_TimerExecute($hash);
    }
  }

  # Attribute "region"
  elsif ($attrName eq "region" )
  {
    if ($cmd eq "set")
    {
      $hash->{helper}{region} = "$attrVal";
      # Update ApplianceId
      $hash->{helper}{header_applicationid} = $regions{$hash->{helper}{region}};
      Log3($name, 3, "FordpassAccount_Attr($name) - region set to \"" . $hash->{helper}{region} . "\"");

      FordpassAccount_UpdateInternals($hash);
      FordpassAccount_ClearLogin($hash);
      FordpassAccount_TimerExecute($hash);
    } 
    elsif ( $cmd eq "del" )
    {
      $hash->{helper}{region} = $DefaultRegion;
      # Update ApplianceId
      $hash->{helper}{header_applicationid} = $regions{$hash->{helper}{region}};

      Log3($name, 3, "FordpassAccount_Attr($name) - region set to \"" . $hash->{helper}{region} . "\"");

      FordpassAccount_UpdateInternals($hash);
      FordpassAccount_ClearLogin($hash);
      FordpassAccount_TimerExecute($hash);
    }
  }

  # Attribute "fordpassUser"
  elsif ( $attrName eq "fordpassUser" )
  {
    if ( $cmd eq "set")
    {
      Log3($name, 3, "FordpassAccount_Attr($name) - fordpassUser set to \"$attrVal\"");

      FordpassAccount_TimerExecute($hash);      
      FordpassAccount_ClearLogin($hash);
      FordpassAccount_TimerExecute($hash);
    } 
    elsif ( $cmd eq "del" )
    {
      Log3($name, 3, "FordpassAccount_Attr($name) - fordpassUser deleted");

      FordpassAccount_TimerRemove($hash);
      FordpassAccount_ClearLogin($hash);
      FordpassAccount_TimerExecute($hash);
    }
  }

  ### Attribute "autocreatedevices"
  elsif ( $attrName eq "autocreatedevices" )
  {
    if ( $cmd eq "set" )
    {
      if ($attrVal eq "1" )
      {
        $hash->{helper}{AUTOCREATEDEVICES} = "1";
        Log3($name, 3, "FordpassAccount_Attr($name) - autocreatedevices enabled");
      }
      elsif ($attrVal eq "0" )
      {
        $hash->{helper}{AUTOCREATEDEVICES} = "0";
        Log3($name, 3, "FordpassAccount_Attr($name) - autocreatedevices disabled");
      }
      else
      {
        return "autocreatedevices must be 0 or 1";
      }
    } 
    elsif ( $cmd eq "del" )
    {
      $hash->{helper}{AUTOCREATEDEVICES} = "0";
      Log3($name, 3, "FordpassAccount_Attr($name) - autocreatedevices disabled");
    }
  }

  return undef;
}

#####################################
# FordpassAccount_Notify( $hash, $dev )
sub FordpassAccount_Notify($$)
{
  my ( $hash, $dev ) = @_;
  my $name = $hash->{NAME};

  return
    if ($hash->{helper}{IsDisabled} ne "0");

  my $devname = $dev->{NAME};
  my $devtype = $dev->{TYPE};
  my $events  = deviceEvents( $dev, 1 );

  return
    if (!$events);

  Log3($name, 4, "FordpassAccount_Notify($name) - DevType: \"$devtype\"");

  # process "global" events
  if ($devtype eq "Global")
  { 
    if (grep(m/^INITIALIZED$/, @{$events}))
    {
      # this is the initial call after fhem has startet
      Log3($name, 3, "FordpassAccount_Notify($name) - INITIALIZED");

      FordpassAccount_TimerExecute($hash);
    }

    elsif (grep(m/^REREADCFG$/, @{$events}))
    {
      Log3($name, 3, "FordpassAccount_Notify($name) - REREADCFG");

      FordpassAccount_TimerExecute($hash);
    }

    elsif (grep(m/^DEFINED.$name$/, @{$events}) )
    {
      Log3($name, 3, "FordpassAccount_Notify($name) - DEFINED");

      FordpassAccount_TimerExecute($hash);
    }

    elsif (grep(m/^MODIFIED.$name$/, @{$events}))
    {
      Log3($name, 3, "FordpassAccount_Notify($name) - MODIFIED");

      FordpassAccount_TimerExecute($hash);
    }

    if ($init_done)
    {
    }
  }
  
  # process internal events
  elsif ($devtype eq "FordpassAccount") 
  {
  }
  
  return;
}

#####################################
# FordpassAccount_Set( $hash, $name, $cmd, @args )
sub FordpassAccount_Set($@)
{
  my ( $hash, $name, $cmd, @args ) = @_;

  Log3($name, 4, "FordpassAccount_Set($name) - Set was called cmd: >>$cmd<<");

  my $isUserSet = AttrVal($name, "fordpassUser", "none") ne "none";
  my $isPasswordSet = $isUserSet && defined(FordpassAccount_ReadPassword($hash));

  ### Command "update"
  if ( lc $cmd eq lc "update" )
  {
    FordpassAccount_Update($hash);
  }
  ###  Command "fordpassUser"
  elsif ( lc $cmd eq lc "fordpassUser" )
  {
    return "usage: $cmd " . '<user@email.com>'
      if ( @args != 1 );
    
    my $user = join( " ", @args );

    CommandAttr(undef, $name . " fordpassUser $user");
  } 
  ###  Command "fordpassPassword"
  elsif ( lc $cmd eq lc "fordpassPassword" )
  {
    return "please set Attribut fordpassUser first"
      if (AttrVal( $name, "fordpassUser", "none" ) eq "none" );

    return "usage: $cmd <password>"
      if ( @args != 1 );

    my $passwd = join( " ", @args );
    FordpassAccount_StorePassword( $hash, $passwd );
    FordpassAccount_ClearLogin($hash);
    FordpassAccount_Update($hash);
  } 
  ### Command "deletePassword"
  elsif ( lc $cmd eq lc "deletePassword" )
  {
    FordpassAccount_DeletePassword($hash);
    FordpassAccount_ClearLogin($hash);
  } 
  ### Command "clearreadings"
  elsif ( lc $cmd eq lc "clearreadings" )
  {
    return "usage: $cmd <mask>"
      if ( @args != 1 );

    my $mask = $args[0];
    fhem("deletereading $name $mask", 1);
    return;
  }
  ### Command "debugGetDevicesState"
  elsif ( lc $cmd eq lc "debugGetDevicesState" )
  {
    FordpassAccount_Update($hash);
  }
  ### Command "debugLogin"
  elsif ( lc $cmd eq lc "debugLogin" )
  {
    return "please set Attribut fordpassUser first"
      if ( AttrVal( $name, "fordpassUser", "none" ) eq "none" );

    return "please set fordpassPassword first"
      if ( not defined( FordpassAccount_ReadPassword($hash) ) );

    FordpassAccount_Login($hash);
  }
  ### Command "debugSetLoginState"
  elsif ( lc $cmd eq lc "debugSetLoginState" )
  {
    $hash->{helper}{LoginInProgress} = join( " ", @args );
    FordpassAccount_UpdateInternals($hash);
  }
  ### Command "debugSetTokenExpired"
  elsif ( lc $cmd eq lc "debugSetTokenExpired" )
  {
    my $loginNextTimeStamp = gettimeofday();
    $hash->{helper}{LoginNextTimeStamp} = $loginNextTimeStamp; 
    FordpassAccount_UpdateInternals($hash);
  }
  else
  {
    my $list = "";

    $list .= "clearreadings:$DebugMarker.*,.* ";

    $list .= "fordpassUser "
      if(!$isUserSet);

    $list .= "fordpassPassword "
      if($isUserSet);

    $list .= "deletePassword:noArg "
      if ($isPasswordSet);

    $list .= "update:noArg "
      if($isPasswordSet);

    $list .= "debugGetDevicesState:noArg "
      if ( $isPasswordSet and $hash->{helper}{DEBUG} ne "0");

    $list .= "debugLogin:noArg "
      if ( $isPasswordSet and $hash->{helper}{DEBUG} ne "0");

    $list .= "debugSetLoginState:0,1 "
      if ( $isPasswordSet and $hash->{helper}{DEBUG} ne "0");

    $list .= "debugSetTokenExpired:noArg "
      if ( $isPasswordSet and $hash->{helper}{DEBUG} ne "0");

    return "Unknown argument $cmd, choose one of $list";
  }
  return undef;
}

#####################################
# FordpassAccount_Write( $hash, $param )
sub FordpassAccount_Write($$)
{
  my ( $hash, $param ) = @_;
  my $name = $hash->{NAME};
  my $resultCallback = $param->{resultCallback};

  Log3($name, 4, "FordpassAccount_Write($name)");

  my $callbackSuccess = sub
  {
    # Add Authorization to Header
    FordpassAccount_Header_AddAuthorization($hash, $param);
    FordpassAccount_Header_AddCountryCode($hash, $param);
    FordpassAccount_Header_AddApplicationId($hash, $param);
    FordpassAccount_Header_AddUserAgent($hash, $param);

    $param->{hash} = $hash;

    FordpassAccount_RequestParam( $hash, $param );
  };

  my $callbackFail = sub
  {
    # is there a callback function?
    if(defined($resultCallback))
    {
      my $data = undef;
      my $errorMsg = $_[0];

      $resultCallback->($param, $data, $errorMsg);
    }
  };
  
  FordpassAccount_Connect($hash, $callbackSuccess, $callbackFail);
}

#####################################
# FordpassAccount_TimerExecute( $hash )
sub FordpassAccount_TimerExecute($)
{
  my ($hash)  = @_;
  my $name    = $hash->{NAME};

  FordpassAccount_TimerRemove($hash);

  if(!$init_done)
  {
    Log3($name, 5, "FordpassAccount_TimerExecute($name) - Init not done yet");

    # reload timer
    my $nextTimer = gettimeofday() + 2;
    $hash->{NEXTTIMER} = strftime($TimeStampFormat, localtime($nextTimer));
    InternalTimer( $nextTimer, \&FordpassAccount_TimerExecute, $hash );

    return;
  }

  if ($hash->{helper}{IsDisabled} ne "0")
  {
    Log3($name, 4, "FordpassAccount_TimerExecute($name) - Disabled");
  }
  else
  {
    Log3($name, 4, "FordpassAccount_TimerExecute($name)");
  
    FordpassAccount_Update($hash);

    # reload timer
    my $nextTimer = gettimeofday() + $hash->{INTERVAL};
    $hash->{NEXTTIMER} = strftime($TimeStampFormat, localtime($nextTimer));
    InternalTimer($nextTimer, \&FordpassAccount_TimerExecute, $hash);
  }
}

#####################################
# FordpassAccount_TimerRemove( $hash )
sub FordpassAccount_TimerRemove($)
{
  my ($hash)  = @_;
  my $name    = $hash->{NAME};
  
  Log3($name, 4, "FordpassAccount_TimerRemove($name)");
  
  $hash->{NEXTTIMER} = "none";
  RemoveInternalTimer($hash, \&FordpassAccount_TimerExecute);
}

#####################################
# FordpassAccount_UpdateInternals( $hash )
sub FordpassAccount_UpdateInternals($)
{
  my ($hash)  = @_;
  my $name    = $hash->{NAME};

  Log3($name, 5, "FordpassAccount_UpdateInternals($name)");
  
  if($hash->{helper}{DEBUG} eq "1")
  {
    $hash->{DEBUG_WRITEMETHOD}              = $hash->{helper}{WRITEMETHOD};
    $hash->{DEBUG_WRITEURL}                 = $hash->{helper}{WRITEURL};
    $hash->{DEBUG_WRITEHEADER}              = $hash->{helper}{WRITEHEADER};
    $hash->{DEBUG_WRITEDATA}                = $hash->{helper}{WRITEDATA};
    $hash->{DEBUG_WRITEHTTPVERSION}         = $hash->{helper}{WRITEHTTPVERSION};
    $hash->{DEBUG_WRITEIGNOREREDIRECTS}     = $hash->{helper}{WRITEIGNOREREDIRECTS};
    $hash->{DEBUG_WRITEKEEPALIVE}           = $hash->{helper}{WRITEKEEPALIVE};

    $hash->{DEBUG_RESPONSECOUNT_SUCCESS}    = $hash->{helper}{RESPONSECOUNT_SUCCESS};
    $hash->{DEBUG_RESPONSECOUNT_ERROR}      = $hash->{helper}{RESPONSECOUNT_ERROR};
    $hash->{DEBUG_RESPONSEAVERAGETIMESPAN}  = $hash->{helper}{RESPONSEAVERAGETIMESPAN};

    my @retrystring_keys =  grep /RESPONSECOUNT_RETRY_/, keys %{$hash->{helper}};
    foreach (@retrystring_keys)
    {
      $hash->{"DEBUG_" . $_} = $hash->{helper}{$_};
    }

    $hash->{DEBUG_access_token}             = $hash->{helper}{access_token};
    $hash->{DEBUG_refresh_token}            = $hash->{helper}{refresh_token};
    $hash->{DEBUG_grant_id}                 = $hash->{helper}{grant_id};
    $hash->{DEBUG_expires_in}               = $hash->{helper}{expires_in};
    $hash->{DEBUG_token_type}               = $hash->{helper}{token_type};
    $hash->{DEBUG_cat1_token}               = $hash->{helper}{cat1_token};
    $hash->{DEBUG_userId}                   = $hash->{helper}{userId};
    
    $hash->{DEBUG_LOGIN_INPROGRESS}         = $hash->{helper}{LoginInProgress};
    $hash->{DEBUG_LOGIN_NEXTTIMESTAMP}      = $hash->{helper}{LoginNextTimeStamp}
      if(defined($hash->{helper}{LoginNextTimeStamp}));
    $hash->{DEBUG_LOGIN_NEXTTIMESTAMPAT}    = strftime($TimeStampFormat, localtime($hash->{helper}{LoginNextTimeStamp}))
      if(defined($hash->{helper}{LoginNextTimeStamp}));
    $hash->{DEBUG_LOGIN_COUNTER}            = $hash->{helper}{LoginCounter};
    $hash->{DEBUG_LOGIN_COUNTER_ERROR}      = $hash->{helper}{LoginErrCounter};

    $hash->{DEBUG_IsDisabled}               = $hash->{helper}{IsDisabled};

    $hash->{DEBUG_REGION}                   = $hash->{helper}{region};
    $hash->{DEBUG_HEADER_COUNTRYCODE}       = $hash->{helper}{header_countrycode};
    $hash->{DEBUG_HEADER_APPLICATIONID}     = $hash->{helper}{header_applicationid};
    $hash->{DEBUG_HEADER_USERAGENT}         = $hash->{helper}{header_useragent};
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

#####################################
# FordpassAccount_Connect( $hash, $callbackSuccess, $callbackFail )
sub FordpassAccount_Connect($;$$)
{
  my ($hash, $callbackSuccess, $callbackFail) = @_;
  my $name    = $hash->{NAME};
  my $now     = gettimeofday();
  my $message = "";

  if($hash->{helper}{IsDisabled} ne "0")
  {
    Log3($name, 4, "FordpassAccount_Connect($name) - IsDisabled");

    # if there is a callback then call it
    if(defined($callbackFail))
    {
      Log3($name, 4, "FordpassAccount_Connect($name) - callbackFail");
      $callbackFail->("account inactive");
    }
  }
  elsif($hash->{helper}{LoginInProgress} ne "0")
  {
    Log3($name, 4, "FordpassAccount_Connect($name) - LoginInProgress");

    # if there is a callback then call it
    if( defined($callbackFail) )
    {
      Log3($name, 4, "FordpassAccount_Connect($name) - callbackFail");
      $callbackFail->("login in progress");
    }
  }
  else
  {
    Log3($name, 4, "FordpassAccount_Connect($name)");
    
    # no valid AccessToken
    if(!defined( $hash->{helper}{access_token}) or
      $hash->{helper}{access_token} eq "none")
    {
      $message = "No valid AccessToken";
    }
    # token has expired
    elsif(!defined($hash->{helper}{LoginNextTimeStamp}) or
      $now >= $hash->{helper}{LoginNextTimeStamp})
    {
      $message = "AccessToken expired - Relogin needed";
    }
  
    if($message eq "")
    {
      # if there is a callback then call it
      if( defined($callbackSuccess) )
      {
        Log3($name, 4, "FordpassAccount_Connect($name) - callbackSuccess");
        $callbackSuccess->();
      }
    }
    else
    {
      Log3($name, 3, "FordpassAccount_Connect($name) - $message");

      FordpassAccount_Login($hash, $callbackSuccess, $callbackFail);
    }
  }
}

#####################################
# FordpassAccount_ClearLogin( $hash )
sub FordpassAccount_ClearLogin($)
{
  my ($hash)  = @_;
  my $name    = $hash->{NAME};

  Log3($name, 4, "FordpassAccount_ClearLogin($name)");

  readingsBeginUpdate($hash);
  readingsBulkUpdateIfChanged( $hash, "state", "login cleared", 1 );
  readingsEndUpdate( $hash, 1 );

  # clear $hash->{helper} to reset statemachines
  delete $hash->{helper}{access_token};
  delete $hash->{helper}{refresh_token};
  delete $hash->{helper}{id_token};
  delete $hash->{helper}{grant_id};
  delete $hash->{helper}{token_type};
  delete $hash->{helper}{expires_in};
  
  delete $hash->{helper}{LoginNextTimeStamp};
}

#####################################
# FordpassAccount_Login( $hash, $callbackSuccess, $callbackFail )
sub FordpassAccount_Login($;$$)
{
  my ($hash, $callbackSuccess, $callbackFail) = @_;
  my $name      = $hash->{NAME};
  my $errorMsg  = "";

  Log3($name, 4, "FordpassAccount_Login($name)");

  # Check for AccountEmail
  if (AttrVal($name, "fordpassUser", "none" ) eq "none")
  {
    $errorMsg = "please set Attribut fordpassUser first";
  }
  # Check for Password
  elsif (not defined(FordpassAccount_ReadPassword($hash)))
  {
    $errorMsg = "please set account password first";
  }
  elsif($hash->{helper}{LoginInProgress} ne "0")
  {
    $errorMsg = "login in progress";
  }

  FordpassAccount_ClearLogin($hash);

  if($errorMsg eq "")
  {
    $hash->{helper}{LoginInProgress}       = "1";
    FordpassAccount_UpdateInternals($hash);

    readingsBeginUpdate($hash);
    readingsBulkUpdateIfChanged( $hash, "state", "logging in", 1 );
    readingsEndUpdate( $hash, 1 );

    my $loginSuccess = sub
    {
      $hash->{helper}{LoginInProgress}       = "0";
      FordpassAccount_UpdateInternals($hash);

      # if there is a callback then call it
      if(defined($callbackSuccess))
      {
        Log3($name, 4, "FordpassAccount_Login($name) - callbackFail");
        $callbackSuccess->();
      }
    };

    my $loginFail = sub
    {
      $hash->{helper}{LoginInProgress}       = "0";
      FordpassAccount_UpdateInternals($hash);

      # if there is a callback then call it
      if(defined($callbackFail))
      {
        Log3($name, 4, "FordpassAccount_Login($name) - callbackFail");
        $callbackFail->($errorMsg);
      }
    };

    my $login_GetToken    = sub { FordpassAccount_Login_GetToken($hash, $loginSuccess, $loginFail); };
    my $login_GetAuthCode = sub { FordpassAccount_Login_GetAuthCode($hash, $login_GetToken, $loginFail); };
  
    $login_GetAuthCode->();
  }
  else
  {
    readingsBeginUpdate($hash);
    readingsBulkUpdateIfChanged( $hash, "state", $errorMsg, 1 );
    readingsEndUpdate( $hash, 1 );
    
    # if there is a callback then call it
    if(defined($callbackFail))
    {
      Log3($name, 4, "FordpassAccount_Login($name) - callbackFail");
      $callbackFail->($errorMsg);
    }
  }
}

#####################################
# FordpassAccount_Login_GetAuthCode( $hash, $callbackSuccess, $callbackFail )
#####################################
sub FordpassAccount_Login_GetAuthCode($;$$)
{
  my ( $hash, $callbackSuccess, $callbackFail ) = @_;
  my $name = $hash->{NAME};

  my $now = gettimeofday();
  Log3($name, 4, "FordpassAccount_Login_GetAuthCode($name)");

  # definition of the lambda function wich is called to process received data
  my $resultCallback = sub 
  {
    my ( $callbackparam, $data, $errorMsg ) = @_;

    if ($errorMsg eq "")
    {
      my $decode_json = eval { decode_json($data) };

      if ($@)
      {
        Log3($name, 3, "FordpassAccount_Login_GetAuthCode($name) - JSON error while request: $@");

        if( AttrVal( $name, "debugJSON", 0 ) == 1 )
        {
          readingsBeginUpdate($hash);
          readingsBulkUpdate( $hash, "JSON_ERROR", $@, 1 );
          readingsBulkUpdate( $hash, "JSON_ERROR_STRING", "\"" . $data . "\"", 1 );
          readingsEndUpdate( $hash, 1 );
        }
        $errorMsg = "Login_GetAuthCode: JSON_ERROR";
      }
      # {
      #   "access_token":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      #   "refresh_token":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      #   "grant_id":"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
      #   "token_type":"jwt",
      #   "expires_in":300
      #  }
      elsif (ref($decode_json) eq "HASH" and
        defined( $decode_json->{refresh_token}))
      {
        $hash->{helper}{access_token}   = $decode_json->{access_token};
        $hash->{helper}{refresh_token}  = $decode_json->{refresh_token};
        $hash->{helper}{grant_id}       = $decode_json->{grant_id};
        $hash->{helper}{token_type}     = $decode_json->{token_type};
        $hash->{helper}{expires_in}     = $decode_json->{expires_in};

        my $loginNextTimeStamp = $now + $decode_json->{expires_in} + $ReloginOffset_s;
        $hash->{helper}{LoginNextTimeStamp} = $loginNextTimeStamp; 
        $hash->{helper}{LoginCounter}++;
        
        Log3($name, 5, "FordpassAccount_Login_GetAuthCode($name) - RefreshToken\n" . $hash->{helper}{refresh_token});

        # find all "Set-Cookie" lines and create cookie header
        #ProcessSetCookies($hash, $param->{httpheader}, "AWSALB");
        FordpassAccount_ProcessSetCookies( $hash, $callbackparam->{httpheader}, undef );
      }
      else
      {
        $hash->{helper}{access_token}   = undef;
        $hash->{helper}{refresh_token}  = undef;
        $hash->{helper}{id_token}       = undef;
        $hash->{helper}{grant_id}       = undef;
        $hash->{helper}{token_type}     = undef;
        $hash->{helper}{expires_in}     = undef;

        my $loginNextTimeStamp = $now;
        $hash->{helper}{LoginNextTimeStamp} = $loginNextTimeStamp; 
        $hash->{helper}{LoginErrCounter}++;

        $errorMsg = "Login_GetAuthCode: WRONG JSON STRUCTURE";
      }

      FordpassAccount_UpdateInternals($hash);
    }
    
    if( $errorMsg eq "" )
    {
      # if there is a callback then call it
      if( defined($callbackSuccess) )
      {
        Log3($name, 4, "FordpassAccount_Login_GetAuthCode($name) - callbackSuccess");
        $callbackSuccess->();
      }
    }
    else
    {
      readingsBeginUpdate($hash);
      readingsBulkUpdateIfChanged( $hash, "state", $errorMsg, 1 );
      readingsEndUpdate( $hash, 1 );

      # if there is a callback then call it
      if( defined($callbackFail) )
      {
        Log3($name, 4, "FordpassAccount_Login_GetAuthCode($name) - callbackFail");
        $callbackFail->($errorMsg);
      }
    }
  }; 

  my $header = 
    "accept: */*\n" .
    "content-type: application/x-www-form-urlencoded\n" .
    "authorization: Basic ZWFpLWNsaWVudDo=";
  
  my $data = 
    "client_id=9fb503e0-715b-47e8-adfd-ad4b7770f73b" . "&" .
    "username=" . urlEncode(AttrVal($name, "fordpassUser", "none")) . "&" .
    "password=" . urlEncode(FordpassAccount_ReadPassword($hash)) . "&" .
    "grant_type=password";

  my $param = {};
  $param->{method} = "POST";
  $param->{url} = $TOKEN_URL;
  $param->{header} = $header;
  $param->{data} = $data;
#  $param->{httpversion} = "1.1";
#  $param->{ignoreredirects} = 0;
#  $param->{keepalive} = 1;

  $param->{hash} = $hash;
  $param->{resultCallback} = $resultCallback;
  
  FordpassAccount_Header_AddUserAgent($hash, $param);
  FordpassAccount_RequestParam($hash, $param);
}

#####################################
# FordpassAccount_Login_GetToken( $hash, $callbackSuccess, $callbackFail )
#####################################
sub FordpassAccount_Login_GetToken($;$$)
{
  my ( $hash, $callbackSuccess, $callbackFail ) = @_;
  my $name = $hash->{NAME};

  my $now = gettimeofday();
  Log3($name, 4, "FordpassAccount_Login_GetToken($name)");

  # definition of the lambda function wich is called to process received data
  my $resultCallback = sub 
  {
    my ( $callbackparam, $data, $errorMsg ) = @_;

    if( $errorMsg eq "" )
    {
      # {
      #   "httpStatus":200,
      #   "status":200,
      #   "requestStatus":"CURRENT",
      #   "error":null,
      #   "lastRequested":null,
      #   "version":null,
      #   "UserProfile":null,
      #   "access_token":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      #   "refresh_token":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      #   "cat1_token":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      #   "userId":"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
      #   "expires_in":1800,
      #   "refresh_expires_in":31556952
      # }      

      # get json-structure from data-string
      my $decode_json = eval { decode_json($data) };
      if ($@)
      {
        Log3($name, 3, "FordpassAccount_Login_GetToken($name) - JSON error while request: $@");

        if(AttrVal( $name, "debugJSON", 0) == 1)
        {
          readingsBeginUpdate($hash);
          readingsBulkUpdate( $hash, "JSON_ERROR", $@, 1 );
          readingsBulkUpdate( $hash, "JSON_ERROR_STRING", "\"" . $data . "\"", 1 );
          readingsEndUpdate( $hash, 1 );
        }

        $errorMsg = "JSON_ERROR";
      }
      elsif (ref($decode_json) eq "HASH" and
        defined( $decode_json->{refresh_token}))
      {
        $hash->{helper}{access_token}   = $decode_json->{access_token};
        $hash->{helper}{refresh_token}  = $decode_json->{refresh_token};
        $hash->{helper}{cat1_token}     = $decode_json->{cat1_token};
        $hash->{helper}{userId}         = $decode_json->{userId};
        $hash->{helper}{expires_in}     = $decode_json->{expires_in};

        my $loginNextTimeStamp = $now + $decode_json->{expires_in} + $ReloginOffset_s;
        $hash->{helper}{LoginNextTimeStamp} = $loginNextTimeStamp; 
        $hash->{helper}{LoginCounter}++;
        
        Log3($name, 5, "FordpassAccount_Login_GetToken($name) - RefreshToken\n$hash->{helper}{refresh_token}");

        # find all "Set-Cookie" lines and create cookie header
        FordpassAccount_ProcessSetCookies( $hash, $callbackparam->{httpheader}, undef );
      }
      else
      {
        $hash->{helper}{access_token}   = undef;
        $hash->{helper}{refresh_token}  = undef;
        $hash->{helper}{cat1_token}     = undef;
        $hash->{helper}{userId}         = undef;
        $hash->{helper}{expires_in}     = undef;

        my $loginNextTimeStamp = $now;
        $hash->{helper}{LoginNextTimeStamp} = $loginNextTimeStamp; 
        $hash->{helper}{LoginErrCounter}++;

        $errorMsg = "LOGIN_GETTOKEN: WRONG JSON STRUCTURE";
      }

      FordpassAccount_UpdateInternals($hash);
    }

    if( $errorMsg eq "" )
    {
      readingsBeginUpdate($hash);
      readingsBulkUpdateIfChanged( $hash, "state", "logged in", 1 );
      readingsEndUpdate( $hash, 1 );

      # if there is a callback then call it
      if( defined($callbackSuccess) )
      {
        Log3($name, 4, "FordpassAccount_Login_GetToken($name) - callbackSuccess");
        $callbackSuccess->();
      }
    }
    else
    {
      readingsBeginUpdate($hash);
      readingsBulkUpdateIfChanged( $hash, "state", $errorMsg, 1 );
      readingsEndUpdate( $hash, 1 );
      
      # if there is a callback then call it
      if( defined($callbackFail) )
      {
        Log3($name, 4, "FordpassAccount_Login_GetToken($name) - callbackFail");
        $callbackFail->($errorMsg);
      }
    }
  }; 

  my $header = 
    "accept: */*\n" .
    "content-type: application/json";

  my $data = 
  {
    "code" => $hash->{helper}{access_token}
  };

  my $param = {};
  $param->{method}  = "PUT";
  $param->{url}     = $USER_URL . "/oauth2/v1/token";
  $param->{header}  = $header;
  $param->{data}    = encode_json($data);
#  $param->{httpversion} = "1.1";
#  $param->{ignoreredirects} = 0;
#  $param->{keepalive} = 1;

  $param->{hash} = $hash;
  $param->{resultCallback} = $resultCallback;

  #FordpassAccount_Header_AddCookies($hash, $param);
  FordpassAccount_Header_AddApplicationId($hash, $param);
  FordpassAccount_Header_AddUserAgent($hash, $param);
  FordpassAccount_RequestParam($hash, $param);
}


#####################################
# FordpassAccount_Update( $hash, $callbackSuccess, $callbackFail )
sub FordpassAccount_Update($;$$)
{
  my ( $hash, $callbackSuccess, $callbackFail ) = @_;
  my $name = $hash->{NAME};

  Log3($name, 4, "FordpassAccount_Update($name) - fetch device list and device states");

  $hash->{helper}{CountVehicles} = 0;

  my $getLocations = sub { FordpassAccount_GetDashboard($hash, $callbackSuccess, $callbackFail); };
  my $connect = sub { FordpassAccount_Connect($hash, $getLocations, $callbackFail); };
  $connect->();
}

#####################################
# FordpassAccount_GetDashboard( $hash, $callbackSuccess, $callbackFail )
sub FordpassAccount_GetDashboard($;$$)
{
  my ( $hash, $callbackSuccess, $callbackFail ) = @_;
  my $name = $hash->{NAME};

  Log3($name, 4, "FordpassAccount_GetDashboard($name)");

  # definition of the lambda function wich is called to process received data
  my $resultCallback = sub 
  {
    my ( $callbackparam, $data, $errorMsg ) = @_;

    if( $errorMsg eq "")
    {
      my $decode_json = eval { decode_json($data) };
      if ($@)
      {
        Log3($name, 3, "FordpassAccount_GetDashboard($name) - JSON error while request: $@");

        if(AttrVal($name, "debugJSON", 0) == 1)
        {
          readingsBeginUpdate($hash);
          readingsBulkUpdate( $hash, "JSON_ERROR", $@, 1 );
          readingsBulkUpdate( $hash, "JSON_ERROR_STRING", "\"" . $data . "\"", 1 );
          readingsEndUpdate( $hash, 1 );
        }
        $errorMsg = "GetDashboard: JSON_ERROR";
      }
      else
      {
        if($hash->{helper}{GenericReadings} ne "none")
        {
          readingsBeginUpdate($hash);
          FordpassAccount_RefreshReadingsFromObject($hash, $DebugMarker . $DefaultSeperator . "Dashboard", $decode_json);
          readingsEndUpdate($hash, 1);
        }

        # hash of all vehicles
        # $vehicleList->{VIN} 
        my $vehicleList = {};

        # {
        #   "userVehicles":
        #   {
        #     "vehicleDetails":
        #     [
        #       {
        #         "VIN":"xxxxxxxxxxxxxxxxx",
        #         "nickName":"first Flitzer",
        #         "tcuEnabled":false,
        #         "isASDN":false
        #       },
        #       {
        #         "VIN":"yyyyyyyyyyyyyyyyy",
        #         "nickName":"second Flitzer",
        #         "tcuEnabled":true,
        #         "isASDN":false
        #       }
        #     ],
        #     "status":
        #     {
        #       "cache-control":"max-age=86400",
        #       "last_modified":"Sat, 19 Feb 2022 04:45:49 GMT",
        #       "statusCode":"200"
        #     }
        #   },

        if (ref($decode_json) eq "HASH" and
          defined($decode_json->{"userVehicles"}->{"vehicleDetails"}))
        {
          # iterate through all entries of "vehicleDetail" array
          foreach my $vehicleDetails (@{$decode_json->{"userVehicles"}->{"vehicleDetails"}})
          {
            my $current_vehicleId = $vehicleDetails->{"VIN"};
            my $current_nickName  = $vehicleDetails->{"nickName"};
            
            # save current vehicle in list
            $hash->{helper}{vehicles_list}{$current_vehicleId} = 
            {
              vehicleId   => $current_vehicleId,
              name        => $current_nickName,
            };
            
            # create current entry in the hash
            $vehicleList->{$current_vehicleId}->{vehicleId}       = $current_vehicleId;
            $vehicleList->{$current_vehicleId}->{name}            = $current_nickName;
            $vehicleList->{$current_vehicleId}->{autocreate}      = $hash->{helper}{AUTOCREATEDEVICES};
            # append current structure to currentVehicle entry in the hash
            $vehicleList->{$current_vehicleId}->{vehicleDetails}  = $vehicleDetails;
          }
        }

        # "vehicleCapabilities":
        # [
        #   {
        #     "VIN":"xxxxxxxxxxxxxxxxx",
        #     "dieselExhaustFluid":"NoDisplay",
        #     "achievements":"NoDisplay",
        #     "zoneLighting":"NoDisplay",
        #     "bidirectionalPowerTransferRemoteControl":"NoDisplay",
        #     "intelligentDigitalAssistant":"NoDisplay",
        #     "remotePanicAlarm":"NoDisplay",
        #     "displayOTAStatusReport":"NoDisplay",
        #     "getDtcsViaApplink":"NoDisplay",
        #     "wifiSettings":"NoDisplay",
        #     "tripReadyNotification":"NoDisplay",
        #     "remoteParkAssist":"NoDisplay",
        #     "boundaryAlerts":"NoDisplay",
        #     "notificationSettings":"NoDisplay",
        #     "scheduleStart":"NoDisplay",
        #     "remoteHeatingCooling":"NoDisplay",
        #     "smartCharge":"NoDisplay",
        #     "remoteLock":"Display",
        #     "displayPreferredChargeTimes":"NoDisplay",
        #     "tripPlanner":"NoDisplay",
        #     "plugAndCharge":"NoDisplay",
        #     "offPlugConditioning":"NoDisplay",
        #     "payForCharge":"NoDisplay",
        #     "remoteChirpHonk":"NoDisplay",
        #     "utilityRateServices":"NoDisplay",
        #     "tripAndChargeLogs":"NoDisplay",
        #     "vehicleChargingStatusExtended":"NoDisplay",
        #     "onlineTrafficViaApplink":"NoDisplay",
        #     "drivingTrends":"NoDisplay",
        #     "paak":"NoDisplay",
        #     "proPowerOnBoard":"NoDisplay",
        #     "stolenVehicleServices":"NoDisplay",
        #     "guardMode":"NoDisplay",
        #     "trailerLightCheck":"NoDisplay",
        #     "remoteStart":"NoDisplay",
        #     "departureTimes":"NoDisplay",
        #     "oilLife":"Display",
        #     "realTimeTraffic":"NoDisplay",
        #     "tirePressureMonitoring":"Display",
        #     "extendRemoteStart":"NoDisplay",
        #     "userAuthStatus":"Authorized",
        #     "payForChargeUserSubscription":"None",
        #     "plugAndChargeUserSubscription":"None",
        #     "userAuthFlow":"None",
        #     "canITow":"NoDisplay",
        #     "ccsConnectivity":"On",
        #     "stolenVehicleStatus":"Unavailable",
        #     "ccsDrivingCharacteristics":"Unavailable",
        #     "wifiHotspot":"Display",
        #     "ccsVehicleData":"On",
        #     "ccsLocation":"On",
        #     "ccsContacts":"Unavailable",
        #     "wifiDataUsage":true,
        #     "remoteWindowCapability":"NoDisplay",
        #     "firstAuthorizedUser":"Not Applicable",
        #     "status":
        #     {
        #       "cache-control":"max-age=900",
        #       "last_modified":"Sun, 2 Jan 2022 08:42:55 GMT",
        #       "statusCode":"207"
        #     }
        #   }
        # ],
        if (ref($decode_json) eq "HASH" and
          defined($decode_json->{"vehicleCapabilities"}))
        {
          foreach my $vehicleCapabilities ( @{ $decode_json->{"vehicleCapabilities"} } )
          {
            my $current_vehicleId = $vehicleCapabilities->{"VIN"};
            
            # to pass parameters to the underlying logical device
            # the hash "currentAppliance" is set for the moment
            $vehicleList->{$current_vehicleId}->{vehicleCapabilities} = $vehicleCapabilities;
          }
        }

        # "vehicleProfile":
        # [
        #   {
        #     "VIN":"yyyyyyyyyyyyyyyyy",
        #     "showEVBatteryLevel":false,
        #     "showFuelLevel":true,
        #     "cabinCargoDoubleUnlock":"False",
        #     "lastMileNavigated":true,
        #     "alarmFunctionality":"False",
        #     "asBuiltCountry":"DEU",
        #     "year":2019,
        #     "vehicleImage":"https://www.gpas-cache.ford.com/nas/gforcenaslive/deu/cge04/yyn/images/deucge04yynbs-ffvs-d4acmaa(a)(a)pnzatshowroom_0_0.png",
        #     "heatedSteeringWheel":false,
        #     "numberOfTires":"Four",
        #     "remoteParkAssistLevel":"None",
        #     "engineType":"ICE",
        #     "frontCargoArea":"None",
        #     "numberOfLightingZones":"0",
        #     "cabinCargoUnlock":"False",
        #     "activationType":"HMI",
        #     "plugAndChargeToggleOnStatus":false,
        #     "model":"Focus",
        #     "make":"Ford",
        #     "displaySmartCharging":"No Data",
        #     "productType":"C",
        #     "zoneUnlock":"False",
        #     "grossVehicleWeightRatingPounds":0,
        #     "fuelLevelApplink":false,
        #     "proPowerZones":"0",
        #     "oilLifeApplink":false,
        #     "healthDataViaApplink":false,
        #     "rearCargoArea":"None",
        #     "blackLabelTrim":false,
        #     "doubleLocking":"False",
        #     "driverHeatedSeat":"None",
        #     "modemDeactivated":"None",
        #     "proPowerWattage":"None",
        #     "proPowerApplink":false,
        #     "remoteClimateControl":false,
        #     "sendNavigationToCar":true,
        #     "sdn":"VSDN",
        #     "displayRecommendedTirePressure":false,
        #     "onboardScaleSmartHitch":"None",
        #     "commonName":"Focus - GE",
        #     "fuelType":"G",
        #     "paintDescription":"ABSOLUTE BLACK",
        #     "transmissionIndicator":"M",
        #     "warrantyStartDate":"2019-03-11T00:00:00",
        #     "vehicleImageLabel":"2019 Ford Focus",
        #     "status":
        #     {
        #       "cache-control":"max-age=108000",
        #       "last_modified":"Sun, 2 Jan 2022 15:56:27 GMT",
        #       "statusCode":"207"
        #     }
        #   }
        # ],
        if (ref($decode_json) eq "HASH" and
          defined($decode_json->{"vehicleProfile"}))
        {
          foreach my $vehicleProfile ( @{ $decode_json->{"vehicleProfile"} } )
          {
            my $current_vehicleId = $vehicleProfile->{"VIN"};
            
            # to pass parameters to the underlying logical device
            # the hash "currentAppliance" is set for the moment
            $vehicleList->{$current_vehicleId}->{vehicleProfile} = $vehicleProfile;
          }
        }

        # "vehicleRecall":
        # {
        #   "totalRecalls":0,
        #   "vehicleRecallItems":
        #   [
        #       {
        #         "VIN":"xxxxxxxxxxxxxxxxx",
        #         "numberofRecall":0,
        #         "numberofFSA":0,
        #         "status":
        #         {
        #           "cache-control":"max-age=86400",
        #           "last_modified":"Sat, 19 Feb 2022 04:45:49 GMT",
        #           "statusCode":"200"
        #         }
        #       },
        #       {
        #         "VIN":"yyyyyyyyyyyyyyyyy",
        #         "numberofRecall":0,
        #         "numberofFSA":0,
        #         "status":
        #       {
        #         "cache-control":"max-age=86400",
        #         "last_modified":"Sat, 19 Feb 2022 04:45:49 GMT",
        #         "statusCode":"200"
        #       }
        #     }
        #   ]
        # }
        if (ref($decode_json) eq "HASH" and
          defined($decode_json->{"vehicleRecall"}))
        {
          foreach my $vehicleRecallItem ( @{ $decode_json->{"vehicleRecall"}->{"vehicleRecallItems"} } )
          {
            my $current_vehicleId = $vehicleRecallItem->{"VIN"};
            
            # to pass parameters to the underlying logical device
            # the hash "currentAppliance" is set for the moment
            $vehicleList->{$current_vehicleId}->{vehicleRecallItem} = $vehicleRecallItem;
          }
        }

        # iterate through all vehicles in table and call dispatch
        foreach my $key (keys %{$vehicleList})
        {
          my $currentVehicle = $vehicleList->{$key};

          if(defined($currentVehicle))
          {
            $hash->{helper}{CountVehicles}++;
            
            # to pass parameters to the underlying logical device (->vehicle)
            # the hash "currentVehicle" is set for the moment
            $hash->{currentVehicle} = $currentVehicle;
            my $current_vehicleId = $currentVehicle->{"vehicleId"};
  
            # dispatch to GroheOndusSmartDevice::Parse()
            my $found = Dispatch( $hash, "FORDPASSVEHICLE_" . $current_vehicleId, undef );
            
            # If a new device was created $found is undef.
            # So dispatch again to get the new created device in running state.
            if(not defined($found))
            {
              Dispatch( $hash, "FORDPASSVEHICLE_" . $current_vehicleId, undef );
            }
          }
        }
        # delete it again
        delete $hash->{currentVehicle}; 
  
        Log3($name, 5, "FordpassAccount_GetDashboard($name) - vehicles count " . $hash->{helper}{CountVehicles});

        # update reading
        readingsSingleUpdate( $hash, "count_vehicles", $hash->{helper}{CountVehicles}, 0 );
      }
    }
    
    if( $errorMsg eq "" )
    {
    }
    else
    {
      readingsBeginUpdate($hash);
      readingsBulkUpdateIfChanged( $hash, "state", $errorMsg, 1 );
      readingsEndUpdate( $hash, 1 );
      
      # if there is a callback then call it
      if( defined($callbackFail) )
      {
        Log3($name, 4, "FordpassAccount_GetDashboard($name) - callbackFail");
        $callbackFail->($errorMsg);
      }
    }
  }; 

  my $header = 
    "accept: */*\n" .
    "content-type: application/json";

  my $data = 
  {
    "dashboardRefreshRequest" => "All"
  };

  my $param = {};
  $param->{method} = "POST";
  $param->{url}    = $USER_URL . "/expdashboard/v1/details/";
  $param->{header} = $header;
  $param->{data}    = encode_json($data);
#  $param->{httpversion} = "1.0";
#  $param->{ignoreredirects} = 0;
#  $param->{keepalive} = 1;

  $param->{hash} = $hash;
  $param->{resultCallback} = $resultCallback;

  FordpassAccount_Header_AddApplicationId($hash, $param);
  FordpassAccount_Header_AddUserAgent($hash, $param);
  FordpassAccount_Header_AddAuthorization($hash, $param);
  FordpassAccount_Header_AddCountryCode($hash, $param);
  FordpassAccount_Header_AddLocale($hash, $param);
  
  FordpassAccount_RequestParam($hash, $param);
}

#####################################
# FordpassAccount_RequestParam( $hash, $param )
sub FordpassAccount_RequestParam($$)
{
  my ( $hash, $param ) = @_;
  my $name = $hash->{NAME};
  my $resultCallback = $param->{resultCallback};

  Log3($name, 4, "FordpassAccount_RequestParam($name)");

  if( $hash->{helper}{IsDisabled} ne "0" )
  {
    # is there a callback function?
    if(defined($resultCallback))
    {
      my $data = undef;
      my $errorMsg = "account inactive";

      $resultCallback->($param, $data, $errorMsg);
    }
  }
  else
  {
    $param->{compress} = 0;
    $param->{doTrigger} = 1;
    $param->{callback} = \&FordpassAccount_RequestErrorHandling;
    
    $param->{resultCallback} = $resultCallback;
    $param->{retryCallback} = \&FordpassAccount_SendReceive;
    $param->{leftRetries} = $hash->{RETRIES};

    $hash->{helper}{WRITEMETHOD}          = $param->{method};
    $hash->{helper}{WRITEURL}             = $param->{url};
    $hash->{helper}{WRITEHEADER}          = $param->{header};
    $hash->{helper}{WRITEDATA}            = $param->{data};
    $hash->{helper}{WRITEHTTPVERSION}     = $param->{httpversion};
    $hash->{helper}{WRITEIGNOREREDIRECTS} = $param->{ignoreredirects};
    $hash->{helper}{WRITEKEEPALIVE}       = $param->{keepalive};

    FordpassAccount_UpdateInternals($hash);

    FordpassAccount_SendReceive($hash, $param);
  }
}

#####################################
# FordpassAccount_SendReceive( $hash, $param )
sub FordpassAccount_SendReceive($$)
{
  my ( $hash, $param ) = @_;
  my $name = $hash->{NAME};

  $param->{request_timestamp} = gettimeofday();
  $param->{leftRetries}--;

  my $request_id = $hash->{REQUESTID}++;
  
  if($request_id >= 65536)
  {
    $hash->{REQUESTID} = 0;
    $request_id = 0;
  }
  $param->{request_id} = $request_id;

  HttpUtils_NonblockingGet($param);
};

#####################################
# FordpassAccount_RequestErrorHandling( $param, $err, $data )
sub FordpassAccount_RequestErrorHandling($$$)
{
  my ( $param, $err, $data ) = @_;

  my $request_id  = $param->{request_id};
  my $leftRetries = $param->{leftRetries};
  my $retryCallback = $param->{retryCallback};
  my $resultCallback = $param->{resultCallback};

  my $response_timestamp = gettimeofday();
  my $request_timestamp = $param->{request_timestamp};
  my $requestResponse_timespan = $response_timestamp - $request_timestamp;
  my $errorMsg = "";

  my $hash  = $param->{hash};
  my $name  = $hash->{NAME};
  my $dhash = $hash;

  $dhash = $modules{GroheOndusSmartDevice}{defptr}{ $param->{"device_id"} }
    unless ( not defined( $param->{"device_id"} ) );

  my $dname = $dhash->{NAME};

  Log3($name, 4, "FordpassAccount_RequestErrorHandling($name) ");

  ### check error variable
  if ( defined($err) and 
    $err ne "" )
  {
    Log3($name, 3, "FordpassAccount_RequestErrorHandling($dname) - ErrorHandling[ID:$request_id]: Error: " . $err . " data: \"" . $data . "\"");
    
    $errorMsg = "error " . $err;
  }

  my $code = "none";
  
  ### check code
  if (exists( $param->{code} ) )
  {
    $code = "$param->{code}";

    if( $param->{code} == 200 ) ###
    {
    }
    elsif( $param->{code} == 302 ) ###
    {
    }
    elsif( $param->{code} == 403 ) ### Forbidden
    {
      #$errorMsg = "wrong password";
      #$leftRetries = 0; # no retry
    }
    elsif( $param->{code} == 429 ) ### To many requests
    {
      $errorMsg = "To many requests";
      $leftRetries = 0; # no retry
    }
    elsif( $param->{code} == 503 ) ### Service Unavailable
    {
      $errorMsg = "error " . $param->{code};
    }
    elsif( $param->{code} == -1 ) ### Debugging
    {
      $errorMsg = "DebuggingLeak";
    }
    elsif( $data eq "" )
    {
      $errorMsg = "error " . $param->{code};
    }
    else
    {
      # no error
    }
  }

  Log3($name, 5, "FordpassAccount_RequestErrorHandling($dname) - ErrorHandling[ID:$request_id]: Code: " . $code . " data: \"" . $data . "\"");

  ### no error: process response
  if($errorMsg eq "")
  {
    $hash->{helper}{RESPONSECOUNT_SUCCESS}++;
    $hash->{helper}{RESPONSETOTALTIMESPAN} += $requestResponse_timespan;
    $hash->{helper}{RESPONSEAVERAGETIMESPAN} = $hash->{helper}{RESPONSETOTALTIMESPAN} / $hash->{helper}{RESPONSECOUNT_SUCCESS};
    my $retrystring = "RESPONSECOUNT_RETRY_" . ($hash->{RETRIES} - $leftRetries);
    $hash->{helper}{$retrystring}++;

    FordpassAccount_UpdateInternals($hash);
  }
  ### error: retries left
  elsif(defined($retryCallback) and # is retryCallbeck defined
    $leftRetries > 0)               # are there any left retries
  {
    Log3($name, 5, "FordpassAccount_RequestErrorHandling($dname) - ErrorHandling[ID:$request_id]: retry " . $leftRetries . " Error: " . $errorMsg);

    ### call retryCallback with decremented number of left retries
    $retryCallback->($hash, $param);
    return; # resultCallback is handled in retry 
  }
  else
  {
    Log3($name, 3, "FordpassAccount_RequestErrorHandling($dname) - ErrorHandling[ID:$request_id]: no retries left Error: " . $errorMsg);

    $hash->{helper}{RESPONSECOUNT_ERROR}++;

    FordpassAccount_UpdateInternals($hash);

    readingsBeginUpdate($hash);
    readingsBulkUpdateIfChanged( $hash, "state", $errorMsg, 1 );
    readingsEndUpdate( $hash, 1 );
  }
  
    # is there a callback function?
  if(defined($resultCallback))
  {
    Log3($name, 4, "FordpassAccount_RequestErrorHandling($dname) - ErrorHandling[ID:$request_id]: calling lambda function");
    
    $resultCallback->($param, $data, $errorMsg);
  }
}

#####################################
# FordpassAccount_ProcessSetCookies( $hash, $header, $regex )
# find all "Set-Cookie" entries in header and put them as "Cookie:" entry in $hash->{helper}{cookie}.
# So cookies can easily added to new outgoing telegrams.
sub FordpassAccount_ProcessSetCookies($@)
{
  my ( $hash, $header, $regex ) = @_;

  # delete cookie
  delete $hash->{helper}{cookie}
    if ( defined( $hash->{helper}{cookie} )
    and $hash->{helper}{cookie} );

  # extract all Cookies and save them as string beginning with keyword "Cookie:"
  my $cookie          = "Cookie:";
  my $cookieseparator = " ";

  for ( split( "\r\n", $header ) )    # split header in lines
  {
    # regex: if current string begins with "Set-Cookie"
    if (/^Set-Cookie/)
    {
      my $currentLine    = $_;
      my $currentCookie  = "";
      my $currentVersion = "";
      my $currentPath    = "";

      for ( split( ";", $currentLine ) )    # split current line at ";"
      {
        # trim: remove white space from both ends of a string:
        $_ =~ s/^\s+|\s+$//g;

        my $currentPart = $_;
        $_ .= "DROPME";                     #endmarker to find empty path

        # if current part starts with "Set-Cookie"
        if (/^Set-Cookie/)
        {
          # cut string "Set-Cookie: "
          $currentPart =~ s/Set-Cookie: //;
          $currentCookie = $currentPart;
        }

        # if current part starts with "Version"
        elsif (/^Version/)
        {
          $currentVersion = '$' . $currentPart . '; ';
        }

        # if current part starts with "Path=/"
        elsif (/^Path=\/DROPME/)
        {
          #drop
        }

        # if current part starts with "Path"
        elsif (/^Path/)
        {
          $currentPath = '; $' . $currentPart;
        } else
        {
          #drop
        }
      }

      if ( !defined($regex)
        || $currentCookie =~ m/$regex/si )
      {
        $currentCookie = $currentVersion . $currentCookie . $currentPath;

        $cookie .= "$cookieseparator" . "$currentCookie";
        $cookieseparator = "; ";

        # Set cookie
        $hash->{helper}{cookie} = $cookie;
      }
    }
  }
}

#####################################
# FordpassAccount_Header_AddAuthorization( $hash, $param )
sub FordpassAccount_Header_AddAuthorization($$)
{
  my ( $hash, $param ) = @_;

  my $header = $param->{header};
  
  # if there is a token, put it in header
  if ( defined( $hash->{helper}{access_token} ) )
  {
    # newline needed?
    $header .= "\n"
      if($header ne "");

    $header .= "auth-token: " . $hash->{helper}{access_token};
    
    $param->{header} = $header;
  }
}

#####################################
# FordpassAccount_Header_AddAuthorization( $hash, $param )
sub FordpassAccount_Header_AddCountryCode($$)
{
  my ( $hash, $param ) = @_;

  my $header = $param->{header};
  
  # if there is a token, put it in header
  if ( defined( $hash->{helper}{header_countrycode} ) )
  {
    # newline needed?
    $header .= "\n"
      if($header ne "");

    $header .= "countrycode: " . $hash->{helper}{header_countrycode} . "\n";
    $header .= "country-code: " . $hash->{helper}{header_countrycode};
    
    $param->{header} = $header;
  }
}

#####################################
# FordpassAccount_Header_AddLocale($$)
sub FordpassAccount_Header_AddLocale($$)
{
  my ( $hash, $param ) = @_;

  my $header = $param->{header};
  
  # if there is a token, put it in header
  if (defined($hash->{helper}{header_locale}))
  {
    # newline needed?
    $header .= "\n"
      if($header ne "");

    $header .= "locale: " . $hash->{helper}{header_locale};
    
    $param->{header} = $header;
  }
}

#####################################
# FordpassAccount_Header_AddApplicationId($$)
sub FordpassAccount_Header_AddApplicationId($$)
{
  my ( $hash, $param ) = @_;

  my $header = $param->{header};
  
  # if there is a token, put it in header
  if (defined($hash->{helper}{header_applicationid}))
  {
    # newline needed?
    $header .= "\n"
      if($header ne "");

    $header .= "application-id: " . $hash->{helper}{header_applicationid};
    
    $param->{header} = $header;
  }
}

#####################################
# FordpassAccount_Header_AddUserAgent($$)
sub FordpassAccount_Header_AddUserAgent($$)
{
  my ($hash, $param) = @_;

  my $header = $param->{header};
  
  # if there is a token, put it in header
  if (defined( $hash->{helper}{header_useragent} ) )
  {
    # newline needed?
    $header .= "\n"
      if($header ne "");


    $header .= "user-agent: " . $hash->{helper}{header_useragent};
    
    $param->{header} = $header;
  }
}

#####################################
# FordpassAccount_Header_AddCookies( $hash, $param )
sub FordpassAccount_Header_AddCookies($$)
{
  my ( $hash, $param ) = @_;
  #my $hash = $param->{hash};

  my $header = $param->{header};
  
  # if there is a token, put it in header
  if ( defined( $hash->{helper}{cookie}) )
  {
    # newline needed?
    $header .= "\n"
      if($header ne "");

    $header .= "$hash->{helper}{cookie}";
    
    $param->{header} = $header;
  }
}

##################################
# FordpassAccount_RefreshReadingsFromObject($$$)
sub FordpassAccount_RefreshReadingsFromObject($$$)
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
      FordpassAccount_RefreshReadingsFromObject($hash, $currentName, $value);
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
      FordpassAccount_RefreshReadingsFromObject($hash, $currentName, $array[$index]);
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

#####################################
# FordpassAccount_StorePassword( $hash, $password )
sub FordpassAccount_StorePassword($$)
{
  my ( $hash, $password ) = @_;
  my $name = $hash->{NAME};
  my $index   = $hash->{TYPE} . "_" . $hash->{NAME} . "_passwd";
  my $key     = getUniqueId() . $index;
  my $enc_pwd = "";

  Log3($name, 5, "FordpassAccount_StorePassword($name)");

  if ( eval "use Digest::MD5;1" )
  {
    $key = Digest::MD5::md5_hex( unpack "H*", $key );
    $key .= Digest::MD5::md5_hex($key);
  }

  for my $char ( split //, $password )
  {
    my $encode = chop($key);
    $enc_pwd .= sprintf( "%.2x", ord($char) ^ ord($encode) );
    $key = $encode . $key;
  }

  my $err = setKeyValue( $index, $enc_pwd );

  return "error while saving the password - $err"
    if ( defined($err) );

  return "password successfully saved";
}

#####################################
# FordpassAccount_ReadPassword( $hash )
sub FordpassAccount_ReadPassword($)
{
  my ( $hash ) = @_;
  my $name   = $hash->{NAME};
  my $index  = $hash->{TYPE} . "_" . $hash->{NAME} . "_passwd";
  my $key    = getUniqueId() . $index;
  my ( $password, $err );

  Log3($name, 5, "FordpassAccount_ReadPassword($name)");

  ( $err, $password ) = getKeyValue($index);

  if ( defined($err) )
  {
    Log3($name, 3, "FordpassAccount_ReadPassword($name) - unable to read password from file: $err");
    return undef;
  }

  if ( defined($password) )
  {
    if ( eval "use Digest::MD5;1" )
    {
      $key = Digest::MD5::md5_hex( unpack "H*", $key );
      $key .= Digest::MD5::md5_hex($key);
    }

    my $dec_pwd = "";

    for my $char ( map { pack( "C", hex($_) ) } ( $password =~ /(..)/g ) )
    {
      my $decode = chop($key);
      $dec_pwd .= chr( ord($char) ^ ord($decode) );
      $key = $decode . $key;
    }

    return $dec_pwd;
  } 
  else
  {
    Log3($name, 3, "FordpassAccount_ReadPassword($name) - No password in file");
    return undef;
  }
}

#####################################
# FordpassAccount_DeletePassword( $hash )
sub FordpassAccount_DeletePassword($)
{
  my ( $hash ) = @_;
  my $name   = $hash->{NAME};

  setKeyValue( $hash->{TYPE} . "_" . $hash->{NAME} . "_passwd", undef );

  return undef;
}


=pod
=item device
=item summary module to communicate with the GroheOndusCloud
=begin html

  <a name="FordpassAccount"></a><h3>FordpassAccount</h3>
  <ul>
    In combination with the FHEM module <a href="#GroheOndusSmartDevice">GroheOndusSmartDevice</a> this module communicates with the <b>Grohe-Cloud</b>.<br>
    <br>
    You can get the configurations and measured values of the registered <b>Sense</b> und <b>SenseGuard</b> appliances 
    and i.E. open/close the valve of a <b>SenseGuard</b> appliance.<br>
    <br>
    Once the <b>FordpassAccount</b> is created the connected devices are recognized and created automatically in FHEM.<br>
    From now on the devices can be controlled and changes in the <b>GroheOndusAPP</b> are synchronized with the state and readings of the devices.
    <br>
    <br>
    <b>Notes</b>
    <ul>
      <li>This module communicates with the <b>Grohe-Cloud</b> - you have to be registered.
      </li>
      <li>Register your account directly at grohe - don't use "Sign in with Apple/Google/Facebook" or something else.
      </li>
      <li>There is a <b>debug-mode</b> you can enable/disable with the <b>attribute debug</b> to see more internals.
      </li>
    </ul>
    <br>
    <a name="FordpassAccount"></a><b>Define</b>
    <ul>
      <code><B>define &lt;name&gt; FordpassAccount</B></code>
      <br><br>
      Example:<br>
      <ul>
        <code>
        define Fordpass.Account FordpassAccount<br>
        <br>
        </code>
      </ul>
    </ul><br>
    <a name="FordpassAccount"></a><b>Set</b>
    <ul>
      <li><a name="FordpassAccountgroheOndusAccountPassword">groheOndusAccountPassword</a><br>
        Set the password and store it.
      </li>
      <br>
      <li><a name="FordpassAccountdeletePassword">deletePassword</a><br>
        Delete the password from store.
      </li>
      <br>
      <li><a name="FordpassAccountupdate">update</a><br>
        Login if needed and update all locations, rooms and appliances.
      </li>
      <br>
      <li><a name="FordpassAccountclearreadings">clearreadings</a><br>
        Clear all readings of the module.
      </li>
      <br>
      <b><i>Debug-mode</i></b><br>
      <br>
      <li><a name="FordpassAccountdebugGetDevicesState">debugGetDevicesState</a><br>
        If debug-mode is enabled:<br>
        get locations, rooms and appliances.
      </li>
      <br>
      <li><a name="FordpassAccountdebugLogin">debugLogin</a><br>
        If debug-mode is enabled:<br>
        login.
      </li>
      <br>
      <li><a name="FordpassAccountdebugSetLoginState">debugSetLoginState</a><br>
        If debug-mode is enabled:<br>
        set/reset internal statemachine to/from state "login" - if set all actions will be locked!.
      </li>
      <br>
      <li><a name="FordpassAccountdebugSetTokenExpired">debugSetTokenExpired</a><br>
        If debug-mode is enabled:<br>
        set the expiration timestamp of the login-token to now - next action will trigger a login.
      </li>
    </ul>
    <br>
    <a name="FordpassAccountattr"></a><b>Attributes</b><br>
    <ul>
      <li><a name="FordpassAccountusername">username</a><br>
        Your registered Email-address to login to the grohe clound.
      </li>
      <br>
      <li><a name="FordpassAccountautocreatedevices">autocreatedevices</a><br>
        If <b>enabled</b> (default) then GroheOndusSmartDevices will be created automatically.<br>
        If <b>disabled</b> then GroheOndusSmartDevices must be create manually.<br>
      </li>
      <br>
      <li><a name="FordpassAccountinterval">interval</a><br>
        Interval in seconds to poll for locations, rooms and appliances.
        The default value is 60 seconds.
      </li>
      <br>
      <li><a name="FordpassAccountdisable">disable</a><br>
        If <b>0</b> (default) then FordpassAccount is <b>enabled</b>.<br>
        If <b>1</b> then FordpassAccount is <b>disabled</b> - no communication to the grohe cloud will be done.<br>
      </li>
      <br>
      <li><a name="FordpassAccountdebug">debug</a><br>
        If <b>0</b> (default) debugging mode is <b>disabled</b>.<br>
        If <b>1</b> debugging mode is <b>enabled</b> - more internals and commands are shown.<br>
      </li>
      <br>
      <li><a name="FordpassAccountdebugJSON">debugJSON</a><br>
        If <b>0</b> (default)<br>
        If <b>1</b> if communication fails the json-payload of incoming telegrams is set to a reading.<br>
      </li>
    </ul><br>
    <a name="FordpassAccountreadings"></a><b>Readings</b>
    <ul>
      <li><a>count_appliance</a><br>
        Count of appliances.<br>
      </li>
      <br>
      <li><a>count_locations</a><br>
        Count of locations.<br>
      </li>
      <br>
      <li><a>count_rooms</a><br>
        Count of rooms.<br>
      </li>
    </ul><br>
    <a name="FordpassAccountinternals"></a><b>Internals</b>
    <ul>
      <li><a>DEBUG_IsDisabled</a><br>
        If <b>1</b> (default)<br>
        If <b>0</b> debugging mode is enabled - more internals and commands are shown.<br>
      </li>
    </ul><br>
    <br>
  </ul>
=end html

=for :application/json;q=META.json 73_FordpassAccount.pm
{
  "abstract": "Modul to communicate with the GroheCloud",
  "x_lang": {
    "de": {
      "abstract": "Modul zur Datenübertragung zur GroheCloud"
    }
  },
  "keywords": [
    "fhem-mod-device",
    "fhem-core",
    "Grohe",
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
        "HTML::Entities": 0,
        "JSON": 0
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
