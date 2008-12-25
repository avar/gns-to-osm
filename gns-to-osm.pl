#!/usr/bin/env perl
use strict;
use Pod::Usage ();
use Getopt::Long ();
use Locale::Country;

Getopt::Long::Parser->new(
	config => [ qw< bundling no_ignore_case no_require_order pass_through > ],
)->getoptions(
	'h|help'         => \my $help,
    'in=s'           => \my $in_gns,
    'out=s'          => \my $out_osm,
    'country-code=s' => \my $iso_country_code,
) or help();

my $country_name = code2country($iso_country_code); # e.g. is -> Iceland

help() unless $in_gns and $out_osm and $iso_country_code and $country_name;

=head1 NAME

gns-to-osm.pl - Reads a GNS Country file and converts it to a F<.osm> file.

=head1 OPTIONS

=over

=item -h, --help

Print a usage message listing all availible options

=item --in FILE

The input GNS file to use, e.g. F<ic.txt>.

=item --out FILE

The file to write the OSM data to, e.g. F<ic.osm>

=item --country-code CODE

The ISO-3166 country code to use in tags written to the OSM file. The
country name will also be written based on what
C<Locale::Country::code2country($country_code)> thinks the country is
called.

=back

=head1 DESCRIPTION

You can get individual country files or one big file for the whole world at

    L<http://earth-info.nga.mil/gns/html/namefiles.htm>

This is complete and working for the Philippines.

For other countries you will probably need to extend the &fdc2osm subroutine
which maps GNS 'DSG' Feature Designation Code to OSM tags.

You may also want to add regexp rules to code handling the ADM1 Feature Designation
Code to work out whether the place is a province, state, city or whatever.

(c) 2007 Michael Collinson - You may use this script for whatever purpose you like
without restriction and without payment of any fee or royalty.

=head1 GNS File Specification

=head2 Feature Classification:

Nine (9) major Geoname feature categories into which similar feature designations are grouped.

 A = Administrative region type feature  : states, provinces, big cities
 P = Populated place type feature    : towns, villages, ?hamlets
 V = Vegetation type feature, e.g. a forest
 L = Locality or area type feature
 U = Undersea type feature
 R = Streets, highways, roads, or railroad type feature
 T = Hypsographic type feature : hill(s), mountain(s), island(s), valley, spur, headland ...
 H = Hydrographic type feature
 S = Spot type feature

=head2  Features Designation Codes

http://www.oziexplorer3.com/namesearch/fd_cross_ref.html

ADM1 first-order administrative division (for example, a state in the USA or a province)
ADM2 A subdivision of a first-order administrative division, such as a county in the United States

  PPL        P       POPULATED PLACE
  PPLA       P       CAPTIAL OF A FIRST-ORDER ADMINISTRATIVE DIVISION
  PPLC       P       CAPTIAL OF A COUNTRY (PCLD, PCLF, PCLI, PCLS)
  PPLL       P       POPULATED LOCALITY
  PPLQ       P       ABANDONED POPULATED PLACE
  PPLR       P       RELIGIOUS POPULATED PLACE
  PPLS       P       POPULATED PLACES
  PPLW       P       DESTROYED POPULATED PLACE
  PPLX       P       SECTION OF POPULATED PLACE

Undersea Features Designation Codes and their Definitions
http://earth-info.nga.mil/gns/html/acuf/feature_designation_name.html

=head2 Name Type:

 C = Conventional name
 N = BGN Standard name
 NS = BGN Standard name in non-Roman script
 P = Provisional name
 PS = Provisional name in non-Roman script
 H = Historic name
 HS = Historic name in non-Roman script
 D = Not verified or daggered name
 DS = Not verified name in non-Roman script
 V = Variant or alternate name
 VS = Variant name in non-Roman script

=head1 What the output should look like

    <?xml version='1.0' encoding='UTF-8'?>
    <osm version='0.5' generator='JOSM'>
      <node id='-1' action='modify' visible='true' lat='0.5475095511261509' lon='166.9191543291018'>
        <tag k='name' v='MyName' />
        <tag k='is_in:country' v='Philippines' />
        <tag k='place' v='village' />
      </node>
    </osm>

=cut

#
# Do an initial read to find top level place names from ADM1 POIs
#
my %adm1_names = ();    # For resolving what top level province/city a POI is in
my $line;
open( GNSFILE, '<'.$in_gns ) || die "Cannot open file $in_gns .. [$!]";
while ($line = <GNSFILE>) {

    chomp $line;

    my (undef, undef, undef, undef, undef,undef,undef,undef,undef,
    undef, $feature_designation_code,
    undef,
    undef ,$adm1,$adm2,undef,undef,
    undef,$name_type,undef,
    undef,undef,undef,$full_name
    )        = split('\t',$line);


    if ($name_type =~ /V/i) {next;}  # Just ignore Variant names

    if ($feature_designation_code =~ /^ADM1/i)
    {
        # Capture the xxx, we can use this to resolve what province / city at populated place is in.
        $adm1_names{$adm1} = $full_name;

    }

}
close(GNSFILE);

#
# Now read for real
#

open( OSM_FILE, '>'.$out_osm ) || die "Cannot open file $out_osm .. [$!]";
print OSM_FILE "<?xml version='1.0' encoding='UTF-8'?>\n";
print OSM_FILE "<osm version='0.5' generator='GNS_Converter'>\n";

my $counter = 0;
my $id = 0;
open( TICKERS, '<'.$in_gns ) || die "Cannot open file $in_gns .. [$!]";
while ($line = <TICKERS>) {
        chomp $line;

        # Field definitions: http://earth-info.nga.mil/gns/html/gis_countryfiles.htm
        my ($rc, $ufi, $uni, $uni, $lat, $lon, $dms, $mgrs, $jog,
        $feature_classification, $feature_designation_code,
        $populated_place_classification,
        $primary_country_code,$adm1,$adm2,$population,$elevation,
        $secondary_country_code,$name_type,$language_code,
        $short_form_name,$generic_name,$sort_name, $full_name, $full_name_nd, $modify_date
        ) = split /\t/, $line;

        #unless ($feature_designation_code =~ /ADM2/i) {next;}

        if ($name_type =~ /V/i) {next;}  # Just ignore Variant names

        #unless ($secondary_country_code) {next;}

        # If we have got here, this is a POI we want to write an OSM node for

        $counter++;
        #if ($counter > 50) {next;}    # for testing


        #
        # Start generating the OSM tags for this POI
        #

        my %osm_tags = ();   # OSM tags to include for this node.

        $osm_tags{'name'} = $full_name;
        $osm_tags{'source'} = 'GNS';
        $osm_tags{'gns_uni'} = $uni;
        $osm_tags{'gns_classification'} = $feature_designation_code;
        $osm_tags{'is_in:country'} = $country_name;

        $osm_tags{'is_in:country_code'} = $iso_country_code;

        # Work out where it is
        if ($adm1 && $adm1_names{$adm1}) {

            # Look for province and city names
            if ($adm1_names{$adm1}=~ /^Province\s+?of\s+?(.*)/) {
                $osm_tags{'is_in:state'} = $adm1_names{$adm1};
            } elsif ($adm1_names{$adm1} =~ /\bcity\b/i) {
                $osm_tags{'is_in:city'} = $adm1_names{$adm1};
            } else {
                # Dunno
                $osm_tags{'is_in'} = $adm1_names{$adm1};
            }
        }

        if ($elevation) {$osm_tags{ele} = $elevation }   # Elevation in meters.
        if ($population) {$osm_tags{population} = $population }
        if ($populated_place_classification) {
            $osm_tags{gns_populated_place_classification} = $populated_place_classification;
        }


        # Create OSM tags depending on the GNS "Feature Classification Code", e.g. ADM1, CAVE ...
        unless (fdc2osm($feature_classification, $feature_designation_code,\%osm_tags))
        {
            # Unmatched code found:
            print ' fc='.$feature_classification.' fdc='.$feature_designation_code .
                ' nt='.$name_type.' adm1='.$adm1.' name='. $full_name."\n";
            next; # XXX
        }

        # NOT nt='.$name_type.' '
        # $adm2 not encountered

        print OSM_FILE "  <node id='".--$id."' action='modify' visible='true' lat='".$lat."' lon='".$lon."'>\n";
        foreach my $key (keys %osm_tags) {
            print OSM_FILE "    <tag k='".$key."' v='".$osm_tags{$key}."' />\n";
        }
        print OSM_FILE "  </node>\n";

}

print OSM_FILE "</osm>\n";
close(OSM_FILE);

exit;

=head2 fdc2osm

Maps GNS 'DSG' Feature Designation Code to OSM tags.

GNS 'DSG' Feature Designation Code is a two to five-character code used to identify
the type of Geoname feature a name is applied to.

 IN:  string - Feature Designation Code
      ref to hash - OSM tags
 OUT: void

=cut

sub fdc2osm {
    my $feature_classification = shift;
    my $fdc = shift;
    my $osm_tags_ref = shift;

    my $matched = 1;

    if    ($fdc =~ /^PCLI$/i )  {$$osm_tags_ref{'place'} = 'country' }
    elsif ($fdc =~ /^ADM1/i)
    {
        # Look for province and city names
        if ($$osm_tags_ref{'name'} =~ /^Province\s+?of\s+?(.*)/) {
            $$osm_tags_ref{'name'} = $1;
            $$osm_tags_ref{'place'} = 'state';
            #print '--->'.$osm_tags{'name'}."\n";
        } else {
            # Assume it is a city
            $$osm_tags_ref{'place'} = 'city';
        }

        next;

    }
    elsif ($fdc =~ /^ADM2$/i )  {$$osm_tags_ref{place} = 'town' }   # ? valid 'municipality'
    elsif ($fdc =~ /^PPLC$/i )  { }  # Capital city, assume already tagged
    elsif ($fdc =~ /^PPL$/i )   {$$osm_tags_ref{place} = 'village' }    # Hmm, could be a town, village, or hamlet - not possible to distingish
    elsif ($fdc =~ /^PPLX$/i )  {$$osm_tags_ref{place} = 'suburb' }
    elsif ($fdc =~ /^PPLQ$/i )  {$$osm_tags_ref{place} = 'locality' } # Abandoned populated place
    elsif ($fdc =~ /^LCTY$/i )  {$$osm_tags_ref{place} = 'locality' }
    elsif ($fdc =~ /^AREA$/i )  {$$osm_tags_ref{place} = 'region' }
    elsif ($fdc =~ /^RGN$/i )   {$$osm_tags_ref{place} = 'region' }
    elsif ($fdc =~ /^RGNE$/i )  {$$osm_tags_ref{place} = 'region' }
    elsif ($fdc =~ /^INDS$/i )  {$$osm_tags_ref{place} = 'suburb'; $$osm_tags_ref{landuse} = 'industrial';}  # Industrial area
    elsif ($fdc =~ /^PRK$/i )   {$$osm_tags_ref{place} = 'national_park' }    # Not a Map Features tag
    elsif ($fdc =~ /^PRT$/i )   {$$osm_tags_ref{place} = 'port' } # Not a Map Features tag
    elsif ($fdc =~ /^NVB$/i )   {$$osm_tags_ref{place} = 'locality'; $$osm_tags_ref{landuse} = 'military';}  # nAVAL Base
    elsif ($fdc =~ /^RES$/i )   {$$osm_tags_ref{place} = 'locality'; }  #   Reserve
    elsif ($fdc =~ /^RESA$/i )  {$$osm_tags_ref{place} = 'locality'; $$osm_tags_ref{landuse} = 'agriculture';}  #
    elsif ($fdc =~ /^RESF$/i )  {$$osm_tags_ref{natural} = 'wood' }
    elsif ($fdc =~ /^TRB$/i )   {$$osm_tags_ref{place} = 'locality'; }  #   Tribal Area
    elsif ($fdc =~ /^FRST$/i )  {$$osm_tags_ref{natural} = 'wood' }
    elsif ($fdc =~ /^RR$/i )    {$$osm_tags_ref{railway} = 'rail' }
    elsif ($fdc =~ /^RD$/i )    {$$osm_tags_ref{highway} = 'unclassified' }
    # Geographic land features
    elsif ($fdc =~ /^RK$/i )    {$$osm_tags_ref{place} = 'island' }  # Rock
    elsif ($fdc =~ /^RKS$/i )   {$$osm_tags_ref{place} = 'locality' }  # Rock
    elsif ($fdc =~ /^ATOL$/i )  {$$osm_tags_ref{place} = 'island' }
    elsif ($fdc =~ /^ISL/i )   {$$osm_tags_ref{place} = 'island' }
    elsif ($fdc =~ /^ISLS$/i )  {$$osm_tags_ref{place} = 'region' }
    elsif ($fdc =~ /^MT$/i )    {$$osm_tags_ref{natural} = 'peak' }
    elsif ($fdc =~ /^MTS$/i )   {$$osm_tags_ref{place} = 'region' }
    elsif ($fdc =~ /^HLL$/i )   {$$osm_tags_ref{natural} = 'peak' }
    elsif ($fdc =~ /^HLLS$/i )  {$$osm_tags_ref{place} = 'region' }
    elsif ($fdc =~ /^PK$/i )    {$$osm_tags_ref{natural} = 'peak' }
    elsif ($fdc =~ /^PKS$/i )   {$$osm_tags_ref{natural} = 'region' }
    elsif ($fdc =~ /^VLC$/i )   {$$osm_tags_ref{natural} = 'volcano' }
    elsif ($fdc =~ /^BCH$/i )   {$$osm_tags_ref{natural} = 'beach' }
    elsif ($fdc =~ /^CLF$/i )   {$$osm_tags_ref{natural} = 'cliff' }
    elsif ($fdc =~ /^PT$/i )    {$$osm_tags_ref{place} = 'locality' } # Headland
    elsif ($fdc =~ /^CNYN$/i )  {$$osm_tags_ref{place} = 'locality' } # Canyon
    elsif ($fdc =~ /^CAPE$/i )  {$$osm_tags_ref{place} = 'locality' } # Cape
    elsif ($fdc =~ /^DLTA$/i )  {$$osm_tags_ref{place} = 'locality'; $$osm_tags_ref{natural} = 'delta'; $$osm_tags_ref{geomorphology} = 'delta' } # Delta
    elsif ($fdc =~ /^DPR$/i )   {$$osm_tags_ref{place} = 'locality' } # Depression
    elsif ($fdc =~ /^GRGE$/i )  {$$osm_tags_ref{place} = 'locality' } # Gorge
    elsif ($fdc =~ /^PASS$/i )  {$$osm_tags_ref{place} = 'locality'; $$osm_tags_ref{mountain_pass} = 'yes'; } #  Pass
    elsif ($fdc =~ /^PEN$/i )   {$$osm_tags_ref{place} = 'region' } # Peninsula
    elsif ($fdc =~ /^PLAT$/i )  {$$osm_tags_ref{place} = 'region' } # Plateau
    elsif ($fdc =~ /^PLN$/i )   {$$osm_tags_ref{place} = 'region' } # Plain
    elsif ($fdc =~ /^HDLD$/i )  {$$osm_tags_ref{place} = 'locality' } # Headland
    elsif ($fdc =~ /^ISTH$/i )  {$$osm_tags_ref{place} = 'locality' } # Isthmus
    elsif ($fdc =~ /^PT$/i )    {$$osm_tags_ref{place} = 'locality' } # Headland
    elsif ($fdc =~ /^RDGE$/i )  {$$osm_tags_ref{place} = 'locality' } # Ridge
    elsif ($fdc =~ /^VAL$/i )   {$$osm_tags_ref{place} = 'locality' } # Valley
    elsif ($fdc =~ /^SDL$/i )   {$$osm_tags_ref{place} = 'locality' } # Saddle
    elsif ($fdc =~ /^SPUR$/i )  {$$osm_tags_ref{natural} = 'peak' } # Spur
    # Water
    elsif ($fdc =~ /^SEA$/i )  {$$osm_tags_ref{place} = 'sea' }  # Sea
    elsif ($fdc =~ /^AIRS$/i )  {$$osm_tags_ref{place} = 'locality' }  # Seaplane landing area
    elsif ($fdc =~ /^GULF$/i )  {$$osm_tags_ref{place} = 'locality' }  # Gulf
    elsif ($fdc =~ /^STRT$/i )  {$$osm_tags_ref{place} = 'locality' }  # Strait
    elsif ($fdc =~ /^ANCH$/i )  {$$osm_tags_ref{place} = 'locality' }  # Anchorage
    elsif ($fdc =~ /^DCKB$/i )  {$$osm_tags_ref{place} = 'locality' }  # Docking Basin
    elsif ($fdc =~ /^NRWS$/i )  {$$osm_tags_ref{place} = 'locality' }  # Narrows
    elsif ($fdc =~ /^RDST$/i )  {$$osm_tags_ref{place} = 'locality' }  # "Roadstead" marine
    elsif ($fdc =~ /^RPDS$/i )  {$$osm_tags_ref{place} = 'locality' }  # Rapids
    elsif ($fdc =~ /^SD$/i )    {$$osm_tags_ref{place} = 'locality' }  # Sound
    elsif ($fdc =~ /^BNK$/i )   {$$osm_tags_ref{natural} = 'bank' }  # Bank
    elsif ($fdc =~ /^CHNM$/i )  {$$osm_tags_ref{place} = 'locality' }  # Marine Channel
    elsif ($fdc =~ /^HBR$/i )   {$$osm_tags_ref{place} = 'port' }  # Harbour
    elsif ($fdc =~ /^SHOL$/i )  {$$osm_tags_ref{natural} = 'shoal' }  # Shoal
    elsif ($fdc =~ /^BAY$/i )   {$$osm_tags_ref{natural} = 'bay' }
    elsif ($fdc =~ /^COVE$/i )  {$$osm_tags_ref{natural} = 'bay' }
    elsif ($fdc =~ /^INLT$/i )  {$$osm_tags_ref{natural} = 'bay' }
    elsif ($fdc =~ /^RF/i )     {$$osm_tags_ref{natural} = 'reef' } # Reef - Not a Map Features tag
    elsif ($fdc =~ /^LGN$/i )   {$$osm_tags_ref{natural} = 'water' }  # Lagoon
    elsif ($fdc =~ /^LK$/i )    {$$osm_tags_ref{natural} = 'water' }   # Lake
    elsif ($fdc =~ /^LKI$/i )   {$$osm_tags_ref{natural} = 'water' }   # Intermittent Lake
    elsif ($fdc =~ /^LKS$/i )   {$$osm_tags_ref{natural} = 'water' }   # Lakes
    elsif ($fdc =~ /^RSV$/i )   {$$osm_tags_ref{natural} = 'water' }   # Reservoir
    elsif ($fdc =~ /^PND/i )    {$$osm_tags_ref{natural} = 'water' }   # Pond(s) - various types
    elsif ($fdc =~ /^MRSH$/i )  {$$osm_tags_ref{natural} = 'marsh' }   # Marsh
    elsif ($fdc =~ /^BOG$/i )  {$$osm_tags_ref{natural} = 'marsh' }   # Bog
    elsif ($fdc =~ /^SWMP$/i )  {$$osm_tags_ref{natural} = 'marsh' }   # Swamp
    elsif ($fdc =~ /^CNL$/i )   {$$osm_tags_ref{waterway} = 'canal' } # Canal
    elsif ($fdc =~ /^CNFL$/i )  {$$osm_tags_ref{waterway} = 'river' }  #  Confuence
    elsif ($fdc =~ /^CRKT$/i )  {$$osm_tags_ref{waterway} = 'river' } # Tidal Creek(s)
    elsif ($fdc =~ /^STM$/i )   {$$osm_tags_ref{waterway} = 'river' } # STM 'stream' appears to cover rivers and streams of all sizes
    elsif ($fdc =~ /^STMD$/i )  {$$osm_tags_ref{waterway} = 'river' } # Distributary(s)
    elsif ($fdc =~ /^STMI$/i )  {$$osm_tags_ref{waterway} = 'stream' }  # INtermittent river/stream
    elsif ($fdc =~ /^STMQ$/i )  {$$osm_tags_ref{waterway} = 'stream' }  # Abandoned water course
    elsif ($fdc =~ /^STMX$/i )  {$$osm_tags_ref{waterway} = 'river' }  # Section of river/stream
    elsif ($fdc =~ /^CHN$/i )   {$$osm_tags_ref{waterway} = 'stream' }  # Channel (CHECK COULD BE SEA NOT LAND
    elsif ($fdc =~ /^CHNL$/i )  {$$osm_tags_ref{waterway} = 'stream' }  # Lake Channel
    elsif ($fdc =~ /^STMM$/i )  {$$osm_tags_ref{waterway} = 'river' }   # River/stream mouth
    elsif ($fdc =~ /^SPNG$/i )  {$$osm_tags_ref{natural} = 'spring' }  # Spring
    elsif ($fdc =~ /^FLLS$/i )  {$$osm_tags_ref{natural} = 'waterfall' }  # Waterfall(s)
    # Spot Feature
    elsif ($fdc =~ /^AGR/i )    {$$osm_tags_ref{landuse} = 'farm' }  #
    elsif ($fdc =~ /^AIRB$/i )  {$$osm_tags_ref{aeroway} = 'airfield'; $$osm_tags_ref{landuse} = 'military'; $$osm_tags_ref{military} = 'airfield';}  #
    elsif ($fdc =~ /^AIRF$/i )  {$$osm_tags_ref{aeroway} = 'airfield' }  #
    elsif ($fdc =~ /^AIRP$/i )  {$$osm_tags_ref{aeroway} = 'airfield' }  #
    elsif ($fdc =~ /^AIRH$/i )  {$$osm_tags_ref{aeroway} = 'helipad' }  #  # Heliport
    elsif ($fdc =~ /^AIRQ$/i )  {$$osm_tags_ref{aeroway} = 'runway' }  #  # Abandoned
    elsif ($fdc =~ /^AIRS$/i )  {$$osm_tags_ref{aeroway} = 'runway' }  #  # Seaplane
    elsif ($fdc =~ /^CSTL$/i )  {$$osm_tags_ref{historic} = 'castle' }
    elsif ($fdc =~ /^CAVE$/i )  {$$osm_tags_ref{natural} = 'cave_mouth' }  #
    elsif ($fdc =~ /^CH$/i )    {$$osm_tags_ref{amenity} = 'place_of_worship'; $$osm_tags_ref{religion} = 'christian' }  # Church
    elsif ($fdc =~ /^MSQE$/i )  {$$osm_tags_ref{amenity} = 'place_of_worship'; $$osm_tags_ref{religion} = 'islam' }  # Mosque
    elsif ($fdc =~ /^TMPL$/i )  {$$osm_tags_ref{amenity} = 'place_of_worship' }  #
    elsif ($fdc =~ /^BTYD$/i )  {$$osm_tags_ref{waterway} = 'boatyard' }
    elsif ($fdc =~ /^CMP$/i )   {$$osm_tags_ref{place} = 'camp' }  #  (Non-leisure) Camp
    elsif ($fdc =~ /^CMPMN$/i ) {$$osm_tags_ref{place} = 'camp' }  #  Mining Camp
    elsif ($fdc =~ /^CMTY$/i )  {$$osm_tags_ref{amenity} = 'grave_yard' }  #
    elsif ($fdc =~ /^DAM$/i )   {$$osm_tags_ref{man_made} = 'dam' }  # Dam
    elsif ($fdc =~ /^HSE$/i )  {$$osm_tags_ref{building} = 'house' }
    elsif ($fdc =~ /^LDNG$/i )  {$$osm_tags_ref{waterway} = 'landing' }  #
    elsif ($fdc =~ /^EST$/i )   {$$osm_tags_ref{landuse} = 'farm' }  # Estate
    elsif ($fdc =~ /^ESTR$/i )  {$$osm_tags_ref{landuse} = 'farm';$$osm_tags_ref{produce} = 'rubber' }  # Estate
    elsif ($fdc =~ /^ESTY$/i )  {
        if ($feature_classification =~ /S/i) {
            $$osm_tags_ref{landuse} = 'farm'; #Estate of some sort
        } else {
            $$osm_tags_ref{waterway} = 'river'; # Estuary

        }
    }
    elsif ($fdc =~ /^RNCH$/i )  {$$osm_tags_ref{landuse} = 'farm' }  # Ranch
    elsif ($fdc =~ /^FRMT$/i )  {$$osm_tags_ref{landuse} = 'farm'; $$osm_tags_ref{building} = 'farm' }
    elsif ($fdc =~ /^FRM/i )  {$$osm_tags_ref{landuse} = 'farm'; }
    elsif ($fdc =~ /^FY$/i )    {$$osm_tags_ref{amenity} = 'ferry_terminal' }  #
    elsif ($fdc =~ /^BRKS$/i )  {$$osm_tags_ref{military} = 'barracks' }  # Fort
    elsif ($fdc =~ /^FT$/i )    {$$osm_tags_ref{landuse} = 'military' }  # Fort
    elsif ($fdc =~ /^INSM$/i )  {$$osm_tags_ref{landuse} = 'military' }  # "Military installation"
    elsif ($fdc =~ /^LTHSE$/i ) {$$osm_tags_ref{man_made} = 'lighthouse' }  #
    elsif ($fdc =~ /^BCN$/i )   {$$osm_tags_ref{man_made} = 'lighthouse' }
    elsif ($fdc =~ /^MFG$/i )   {$$osm_tags_ref{man_made} = 'factory' }  #
    elsif ($fdc =~ /^ML$/i )    {$$osm_tags_ref{man_made} = 'factory' }
    elsif ($fdc =~ /^MLSW$/i )  {$$osm_tags_ref{man_made} = 'factory' }
    elsif ($fdc =~ /^MN$/i )    {$$osm_tags_ref{man_made} = 'mine' }  #
    elsif ($fdc =~ /^MNAU$/i )  {$$osm_tags_ref{man_made} = 'mine';  $$osm_tags_ref{mine_ore} = 'gold';}  #
    elsif ($fdc =~ /^MNC$/i )   {$$osm_tags_ref{man_made} = 'mine';  $$osm_tags_ref{mine_ore} = 'coal';}
    elsif ($fdc =~ /^MNCR$/i )  {$$osm_tags_ref{man_made} = 'mine';  $$osm_tags_ref{mine_ore} = 'chrome';}
    elsif ($fdc =~ /^MNCU$/i )  {$$osm_tags_ref{man_made} = 'mine';  $$osm_tags_ref{mine_ore} = 'copper';}
    elsif ($fdc =~ /^MNFE$/i )  {$$osm_tags_ref{man_made} = 'mine';  $$osm_tags_ref{mine_ore} = 'iron';}
    elsif ($fdc =~ /^PRN$/i )   {$$osm_tags_ref{amenity} = 'prison' }  #
    elsif ($fdc =~ /^PP$/i )    {$$osm_tags_ref{amenity} = 'police_station' }  #
    elsif ($fdc =~ /^RSTN$/i )  {$$osm_tags_ref{railway} = 'station' }  #
    elsif ($fdc =~ /^RSTP$/i )  {$$osm_tags_ref{railway} = 'halt' }
    elsif ($fdc =~ /^RUIN$/i )  {$$osm_tags_ref{historic} = 'ruin' }  #
    elsif ($fdc =~ /^HSPL$/i )   {$$osm_tags_ref{amenity} = 'hospital' }
    elsif ($fdc =~ /^SCH$/i )   {$$osm_tags_ref{amenity} = 'school' }  #
    elsif ($fdc =~ /^SCHA$/i )   {$$osm_tags_ref{amenity} = 'college' }  #
    elsif ($fdc =~ /^SCHC$/i )   {$$osm_tags_ref{amenity} = 'college' }  #
    elsif ($fdc =~ /^SCHM$/i )   {$$osm_tags_ref{amenity} = 'college'; $$osm_tags_ref{landuse} = 'military';$$osm_tags_ref{military} = 'school'}  #
    elsif ($fdc =~ /^PS$/i )    {$$osm_tags_ref{man_made} = 'power_station' }  #
    elsif ($fdc =~ /^STNR$/i )  {$$osm_tags_ref{man_made} = 'radio_station' }  #  Radio Station
    elsif ($fdc =~ /^TRIG$/i )  {$$osm_tags_ref{man_made} = 'trig_point' }  #
    elsif ($fdc =~ /^WHRF$/i )  {$$osm_tags_ref{man_made} = 'wharf' }  #
    # Underwater
    elsif ($fdc =~ /^RFU/i )    {$$osm_tags_ref{subsea} = 'reef' }   # Not a Map Features tag
    elsif ($fdc =~ /^PLTU$/i )  {$$osm_tags_ref{subsea} = 'plateau' } # Not a Map Features tag
    else {$matched = 0;}

    return $matched;

}

sub help
{
    my %arg = @_;

    Pod::Usage::pod2usage(
        -verbose => $arg{ verbose },
        -exitval => $arg{ exitval } || 0,
    );
}
