# do not remove the { } from the top and bottom of this page!!!
{

   #Dutch translation done by Marc Logghe <marcl@devgen.com>

   CHARSET =>   'ISO-8859-1',

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
Maak gebruik van de 'Scrollen/Inzoomen' knoppen om de vergroting of de positie te veranderen. 
Om de huidige pagina te bewaren, 
<a href="%s">voeg deze koppeling toe aan uw favorieten.</a>  
END

   EDIT_INSTRUCTIONS => <<END,
Geuploade annotatiegegeves kunnen hier aangepast worden.
Velden kunnen afgescheiden worden door tabs of spaties,
maar velden met witruimte dienen tussen enkelvoudige of dubbele
aanhalingstekens te staan
END

   SHOWING_FROM_TO => 'Weergave van %s van %s, posities %s tot %s',

   LANDMARK => 'Mijlpaal of Gebied',

   BOOKMARK => 'Toevoegen aan Favorieten',

   KEY_POSITION => 'Positie van Legende',

   BETWEEN   => 'Tussen',
 
   BENEATH   => 'Onder',

   LEFT        => 'Links',

   RIGHT       => 'Rechts',

   TRACK_NAMES => 'Lijst tracknamen',

   ALPHABETIC  => 'Alfabetisch',

   VARYING     => 'Willekeurig',

   SHOW_GRID => 'Toon grid',

   FLIP      => 'Omkeren',

   HIDE_HEADER => 'Koptekst Verbergen',

   HIDE_INSTRUCTIONS => 'Instructies Verbergen',

   HIGHLIGHT => 'Markeren',

   IMAGE_DESCRIPTION => <<END,
<p>
Om een ingebed plaatje van dit beeld te bekomen, knip en plak de
volgende URL in een HTML pagina:
</p>
<pre>
&lt;IMAGE src="%s" /&gt;
</pre>
<p>
Het plaatje zal er dan als volgt uitzien:
</p>
<p>
<img src="%s" />
</p>

<p>
Indien enkel het overzicht (chromosoom of contig) zichtbaar is, probeer
dan de regio te verkleinen
</p>
END

   IMAGE_LINK => 'Koppeling Beeld',

   POSSIBLE_TRUNCATION => 'Aantal resultaten is beperkt tot %d hits; lijst is mogelijks onvolledig', 

   SHOW_HEADER => 'Koptekst Tonen',

   SVG_DESCRIPTION => <<END,
<p>
Deze koppeling zal een beeldje genereren in het 'Scalable Vector Graphic'
(SVG) formaat. SVG beelden hebben verschillende voordelen in vergelijking met
rasterbeelden zoals jpeg of png.
</p>
<ul>
<li>grootte kan vrij aangepast worden zonder resolutieverlies
<li>elk individueel onderdeel kan opgemaakt worden in vector georiënteerde grafische applicaties
<li>kan, indien nodig, omgezet geworden in EPS formaat ter indiening van een publicatie
</ul>
<p>
Om SVG beelden te bekijken moet, ofwel je browser SVG ondersteunen, 
ofwel moet de Adobe SVG browser plugin, of andere SVG applicatie zoals Adobe Illustrator, geinstalleerd zijn. 
</p>
<p>
Adobe's SVG browser plugin: <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Macintosh">Macintosh</a>
| <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Windows">Windows</a>
<br />
Linux gebruikers kunnen eventueel de <a href="http://xml.apache.org/batik/">Batik SVG Viewer</a> uitproberen.
</p>
<p>
<a href="%s" target="_blank">Bekijk het SVG beeld in een nieuw venster</a></p>
<p>
Om dit plaatje op schijf te bewaren, CTRL-klik (Macintosh) of
rechts-klik (Windows) en selecteer de optie om op schijf bewaren.
</p>   
END

   SVG_LINK   => 'Beeld van Publicatiekwaliteit',

   TIMEOUT   => <<'END',
Uw vraag heeft de ingestelde blokkeertijd overschreden. Misschien heeft u een gebied geselecteerd dat te groot is om afgebeeld te worden.
Probeer opnieuw na het deselecteren van een aantal tracks of beperk uw selectie tot een kleiner gebied.
Indien dergelijke blokkeringen zich hardnekkig blijven manifesteren, gelieve op de rode "Reset" knop te drukken.
END

   GO       => 'Doorgaan',

   FIND     => 'Vinden',

   SEARCH   => 'Zoeken',

   DUMP     => 'Dumpen',

   ANNOTATE     => 'Annoteren',

   SCROLL   => 'Scrollen/Inzoomen',

   RESET    => 'Reset',

   DOWNLOAD_FILE    => 'Downloaden Bestand',

   DOWNLOAD_DATA    => 'Downloaden Gegevens',

   DOWNLOAD         => 'Downloaden',

   DISPLAY_SETTINGS => 'Weergave Instellingen',

   TRACKS   => 'Tracks',

   EXTERNAL_TRACKS => '(Externe tracks cursief)',

   EXAMPLES => 'Voorbeelden',

   REGION_SIZE => 'Lengte van het Gebied (bp)',

   HELP     => 'Hulp',

   HELP_FORMAT => 'Hulp met Bestandsformaat',

   CANCEL   => 'Annuleren',

   ABOUT    => 'Over...',

   REDISPLAY   => 'Nieuwe Weergave',

   CONFIGURE   => 'Configureren...',

   CONFIGURE_TRACKS   => 'Configuren tracks...',

   EDIT       => 'Aanpassen Bestand...',

   DELETE     => 'Wissen Bestand',

   EDIT_TITLE => 'Invoeren/Aanpassen Annotatie gegevens',

   IMAGE_WIDTH => 'Beeldbreedte',

   SET_OPTIONS => 'Trackinstellingen...',

   CLEAR_HIGHLIGHTING => 'Fluo Markering afzetten',

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

   FEATURES_TO_HIGHLIGHT => 'Fluo Markeren kenmerk(en) (kenmerk1 kenmerk2...)',

   REGIONS_TO_HIGHLIGHT => 'Fluo Markeren gebieden (gebied1:begin..einde gebied2:begin..einde)',

   FEATURES_TO_HIGHLIGHT_HINT => 'Tip: gebruik kenmerk@kleur om de kleur te selecteren, zoals in \'NUT21@lightblue\'',

   REGIONS_TO_HIGHLIGHT_HINT  => 'Tip: gebruik gebied@kleur om de kleur te selecteren, zoals in \'Chr1:10000..20000@lightblue\'',

   NO_TRACKS    => '*geen*',

   FILE_INFO    => 'Recentste veranderingen op %s.  Geannoteerde mijlpalen: %s',

   FOOTER_1     => <<END,
Opmerking: Deze pagina maakt gebruik van 'cookies' om voorkeurinformatie
te bewaren of terug op te halen.
Er wordt geen informatie gedeeld.
END

   FOOTER_2    => 'Generic genome browser versie %s',

   ALL_OFF => 'Alles uit',

   ALL_ON => 'Alles aan',

   ANALYSIS => 'Analyse',

   DETAILS => 'Details',

   GENERAL => 'Algemeen',

   REGION      => 'Gebied',

   OVERVIEW => 'Overzicht',

   OVERVIEW_TRACKS => 'Overzichtstracks',

   REGION_TRACKS => '<sup>**</sup>Gebiedstracks',

   UPLOAD_TRACKS => 'Upload tracks',


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

   OPTIONS_TITLE => 'Trackinstellingen',

   SETTINGS_INSTRUCTIONS => <<END,
De <i>Toon</i> checkbox zet een track aan of uit. In de <i>Formaat</i> kolom kan via de 
<i>Compact</i> optie de track gecondenseerd worden, zodat 
annotaties elkaar overlappen. De <i>Uitgeklapt</i> en <i>Extra Uitgeklapt</i>
opties zetten de 'botsingscontrole' aan, gebruik makend van tragere en snellere layout 
algorithmen. De <i>Uitgeklapt</i> &amp; <i>Label</i> en <i>Extra Uitgeklapt
&amp; Label</i> opties zorgen ervoor dat de annotaties daarbij ook nog worden gelabeled. Bij de
selectie van <i>Auto</i>, gebeuren de 'botsingscontrole' en label opties automatisch,
enkel indien voldoende ruimte voorhanden is. Om de volgorde van de tracks te veranderen
gebruik het <i>Volgorde Veranderen</i> popup menu waar een annotatie kan toegekend worden
aan een track. Om het aantal getoonde annotaties van dit type te beperken, verander
de waarde via het <i>Grens</i> menu.
END

   TRACK  => 'Track',

   TRACK_TYPE => 'Tracktype',

   SHOW => 'Tonen',

   SHOW_INSTRUCTIONS => 'Instructies Tonen',

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

   TRACK_DESCRIPTIONS => 'Trackbeschrijvingen & referenties',

   BUILT_IN           => 'Tracks in deze server ingebouwd',

   EXTERNAL           => 'Tracks met externe annotaties',

   ACTIVATE           => 'Gelieve deze track te activeren om de informatie te kunnen bekijken.',

   NO_EXTERNAL        => 'Geen externe kenmerken geladen.',

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

 NO_SOURCES        => 'Er zijn geen leesbare gegevensbronnen geconfigureerd. Misschien heeft u geen toestemming om deze te bekijken.',

 ADD_YOUR_OWN_TRACKS => 'Voeg uw eigen tracks toe',

 INVALID_SOURCE    => 'De bron %s is ongeldig.',

 BACKGROUND_COLOR  => 'Vulkleur',

 FG_COLOR          => 'Lijnkleur',

 HEIGHT           => 'Hoogte',

 PACKING          => 'Packing',

 GLYPH            => 'Vorm',

 LINEWIDTH        => 'Lijn dikte',

 DEFAULT          => '(standaard)',

 DYNAMIC_VALUE    => 'Dynamisch berekend',

 CHANGE           => 'Verandering',

 DRAGGABLE_TRACKS  => 'Sleepbare tracks',

 CACHE_TRACKS      => 'Cache tracks',

 SHOW_TOOLTIPS     => 'Toon tips',

 OPTIONS_RESET     => 'Alle pagina instellingen zijn terug op hun standaardwaarden gezet.',

 OPTIONS_UPDATED   => 'De website is geherconfigureerd; alle pagina instelling zijn op hun standaardwaarden gezet.',

 SEND_TO_GALAXY    => 'Stuur deze region naar Galaxy',

 NO_DAS            => 'Installatiefout: de Bio::Das module moet geinstalleerd zijn als u gebruik wil maken van DAS URLs. Gelieve de webmaster te contacteren.',

 CONFIGURE_THIS_TRACK => '<b>Klik om track settings te veranderen.</b>',

 OK => 'OK',

 PDF_LINK => 'PDF link',

 PLUGIN_SEARCH => 'Zoek plugin',

 SHARE => 'Deel %s',

 SHARE_ALL => 'Deel alles',

 SHARE_DAS_INSTRUCTIONS_ALL_TRACKS => <<END,
Om alle geselecteerde tracks te delen met een andere GBrowse genome browser
met behulp van het <a href="http://ww.biodas.org" target="_new">Distributed
Annotation System (DAS)</a>, copieer eerst de URL hieronder, ga dan naar de
andere browser en geef de URL in als een nieuwe DAS bron. <i>Quantitatieve
tracks ("wiggle" bestanden) en upgeloade bestanden kunnen niet gedeeld worden
met DAS.</i>
END

 SHARE_DAS_INSTRUCTIONS_ONE_TRACK => <<END,
Om deze track te delen met een andere GBrowse genome browser met behulp
van het <a href="http://ww.biodas.org" target="_new">Distributed Annotation 
System (DAS)</a>, copieer eerst de URL hieronder, ga dan naar de andere
browser en geef de URL in als een nieuwe DAS bron. <i>Quantitatieve tracks
("wiggle" bestanden) en upgeloade bestanden kunnen niet gedeeld worden met
DAS.</i>
END

 SHARE_INSTRUCTIONS_ALL_TRACKS => <<END,
Om alle geselecteerde tracks te delen met een andere GBrowse genome browser,
copieer eerst de URL hieronder, ga dan naar de andere GBrowse en
plak the URL in het "Enter Remote Annotation" veld onderaan de pagina.
Als een van deze tracks afkomstig is van een upgeloade file, let er dan op dat
het delen van deze URL met een andere gebruiker er kan toe leiden dat
<b>al</b> jouw upgeloade gegevens beschikbaar worden voor die gebruiken.
END

 SHARE_INSTRUCTIONS_ONE_TRACK => <<END,
Om deze track te delen met een andere GBrowse genome browser,
copieer eerst de URL hieronder, ga dan naar de andere GBrowse en
plak the URL in het "Enter Remote Annotation" veld onderaan de pagina.
Als deze track afkomstig is van een upgeloade file, let er dan op dat
het delen van deze URL met een andere gebruiker er kan toe leiden dat
<b>al</b> jouw upgeloade gegevens beschikbaar worden voor die gebruiken.
END

 SHARE_THIS_TRACK => '<b>Deel deze track</b>',

 SHOW_OR_HIDE_TRACK => '<b>Toon of verberg track</b>',

};
