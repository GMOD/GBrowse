# do not remove the { } from the top and bottom of this page!!!
{
   #----------
   # MAIN PAGE
   #----------

   PAGE_TITLE   => 'Genome browser',

   INSTRUCTIONS => 'Instructies',

   HIDE         => 'Verbergen',

   SEARCH_INSTRUCTIONS => <<END,
Zoek met behulp van de naam van een sequentie, gen,
locus%s, of andere mijlpaal. Het jokerteken * is toegelaten.
END


   NAVIGATION_INSTRUCTIONS => <<END,
Klik op het lineaal om de figuur op de aangeduide plaats te centreren. 
Maak gebruik van de Scroll/Zoom knoppen om de vergroting of de positie te veranderen. 
Om de huidige pagina te bewaren, 
<a href="%s">voeg deze koppeling toe aan uw favorieten.</a>  
END

   EDIT_INSTRUCTIONS => <<END,
Geuploadede annotatiegegeves kunnen hier aangepast worden.
Velden kunnen afgescheiden worden door tabs of spaties,
maar velden met witruimte dienen tussen enkelvoudige of dubbele
aanhalingstekens te staan
END

   SHOWING_FROM_TO => 'Weergave van %s van %s, posities %s tot %s',

   LANDMARK => 'Mijlpaal of Gebied',

   KEY_POSITION => 'Positie van Legende',

   BETWEEN   => 'Tussen',
 
   BENEATH   => 'Onder',

   GO       => 'Doorgaan',

   FIND     => 'Zoeken',

   DUMP     => 'Dumpen',

   ANNOTATE     => 'Annoteren',

   SCROLL   => 'Scroll/Zoom',

   RESET    => 'Terugstellen',

   DOWNLOAD_FILE    => 'Downloaden Bestand',

   DOWNLOAD_DATA    => 'Downloaden Gegevens',

   DOWNLOAD         => 'Downloaden',

   DISPLAY_SETTINGS => 'Weergave Instellingen',

   TRACKS   => 'Banen',

   EXTERNAL_TRACKS => '(Externe banen cursief)',

   EXAMPLES => 'Voorbeelden',

   HELP     => 'Hulp',

   HELP_FORMAT => 'Hulp met Bestandsformaat',

   CANCEL   => 'Annuleren',

   ABOUT    => 'Over...',

   REDISPLAY   => 'Nieuwe Weergave',

   CONFIGURE   => 'Configureren...',

   EDIT       => 'Aanpassen Bestand...',

   DELETE     => 'Wissen Bestand',

   EDIT_TITLE => 'Invoeren/Aanpassen Annotatie gegevens',

   IMAGE_WIDTH => 'Beeldbreedte',

   SET_OPTIONS => 'Baaninstellingen...',

   UPDATE      => 'Beeld Vernieuwen',

   DUMPS       => 'Dumps, Zoekopdrachten en meer',

   DATA_SOURCE => 'Gegevensbron',

   UPLOAD_TITLE=> 'Uploaden eigen Annotaties',

   UPLOAD_FILE => 'Uploaden bestand',

   BROWSE      => 'Browse...',

   UPLOAD      => 'Uploaden',

   NEW         => 'Nieuw...',

   REMOTE_TITLE => 'Toevoegen Annotaties op afstand',

   REMOTE_URL   => 'Invoeren URL Annotaties op afstand',

   UPDATE_URLS  => 'Bijwerken URLs',

   PRESETS      => '--Kies Preset URL--',

   FILE_INFO    => 'Recentste veranderingen op %s.  Geannoteerde mijlpalen: %s',

   FOOTER_1     => <<END,
Opmerking: Deze pagina maakt gebruik van 'cookies' om voorkeurinformatie
te bewaren of terug op te halen.
Er wordt geen informatie gedeeld.
END

   FOOTER_2    => 'Generic genome browser versie %s',

   #----------------------
   # MULTIPLE MATCHES PAGE
   #----------------------

   HIT_COUNT      => 'De volgende %d gebieden voldoen aan uw aanvraag.',

   MATCHES_ON_REF => 'Matches op %s',

   SEQUENCE        => 'sequentie',

   SCORE           => 'score=%s',

   NOT_APPLICABLE => 'nvt',

   BP             => 'bp',

   #--------------
   # SETTINGS PAGE
   #--------------

   SETTINGS => 'Instellingen voor %s',

   UNDO     => 'Annuleren',

   REVERT   => 'Standaardwaarden',

   REFRESH  => 'Verversen',

   CANCEL_RETURN   => 'Annuleren en Terug...',

   ACCEPT_RETURN   => 'Aanvaarden en Terug...',

   OPTIONS_TITLE => 'Baaninstellingen',

   SETTINGS_INSTRUCTIONS => <<END,
De <i>Toon</i> checkbox zet een baan aan of uit. In de <i>Formaat</i> kolom kan via de 
<i>Compact</i> optie de baan gecondenseerd worden, zodat 
annotaties elkaar overlappen. De <i>Uitgeklapt</i> en <i>Extra Uitgeklapt</i>
opties zetten de 'botsingscontrole' aan, gebruik makend van tragere en snellere layout 
algorithmen. De <i>Uitgeklapt</i> &amp; <i>Label</i> en <i>Extra Uitgeklapt
&amp; Label</i> opties zorgen ervoor dat de annotaties daarbij ook nog worden gelabeled. Bij de
selectie van <i>Auto</i>, gebeuren de 'botsingscontrole' en label opties automatisch,
enkel indien voldoende ruimte voorhanden is. Om de volgorde van de banen te veranderen
gebruik het <i>Volgorde Veranderen</i> popup menu waar een annotatie kan toegekend worden
aan een baan. Om het aantal getoonde annotaties van dit type te beperken, verander
de waarde via het <i>Grens</i> menu.
END

   TRACK  => 'Baan',

   TRACK_TYPE => 'Baantype',

   SHOW => 'Toon',

   FORMAT => 'Formaat',

   LIMIT  => 'Grens',

   ADJUST_ORDER => 'Volgorde Bijstellen',

   CHANGE_ORDER => 'Volgorde Veranderen',

   AUTO => 'Auto',

   COMPACT => 'Compact',

   EXPAND => 'Uitgeklapt',

   EXPAND_LABEL => 'Uitgeklapt & Label',

   HYPEREXPAND => 'Extra Uitgeklapt',

   HYPEREXPAND_LABEL =>'Extra Uitgeklapt & Label',

   NO_LIMIT    => 'Geen Grens',

   #--------------
   # HELP PAGES
   #--------------

   CLOSE_WINDOW => 'Sluit dit venster',

   TRACK_DESCRIPTIONS => 'Baanbeschrijvingen & Citaties',

   BUILT_IN           => 'Banen in deze Server ingebouwd',

   EXTERNAL           => 'Banen met Externe Annotaties',

   ACTIVATE           => 'Gelieve deze baan te activeren om de informatie te kunnen bekijken.',

   NO_EXTERNAL        => 'Geen externe features geladen.',

   NO_CITATION        => 'Geen additionele informatie beschikbaar.',

   #--------------
   # PLUGIN PAGES
   #--------------

 ABOUT_PLUGIN  => 'Over %s',

 BACK_TO_BROWSER => 'Terug naar Browser',

 PLUGIN_SEARCH_1   => '%s (via %s zoeken)',

 PLUGIN_SEARCH_2   => '&lt;%s zoeken&gt;',

 CONFIGURE_PLUGIN   => 'Configuren',

 BORING_PLUGIN => 'Deze plugin heeft geen extra configuratie instellingen.',

   #--------------
   # ERROR MESSAGES
   #--------------

 NOT_FOUND => 'De mijlpaal met de naam <i>%s</i> werd niet gevonden. Zie eventueel de hulppagina\'s voor suggesties.',

 TOO_BIG   => 'Gedetailleerd beeld is beperkt tot %s basen.  Klik op het overzicht om een gebied te selecteren van %s breed.',

 PURGED    => "Het bestand %s kon niet gevonden worden.  Misschien werd het verwijderd ?.",

 NO_LWP    => "Deze server werd niet geconfigureerd om externe URL's op te halen.",

 FETCH_FAILED  => "Kon %s niet ophalen: %s.",

 TOO_MANY_LANDMARKS => '%d mijlpalen.  Te veel om op te lijsten.',

 SMALL_INTERVAL    => 'Grootte van klein interval bijgesteld tot %s bp',

};
