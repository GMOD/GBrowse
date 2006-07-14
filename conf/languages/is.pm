# do not remove the { } from the top and bottom of this page!!!
{

#Icelandic translation done by Gudmundur A. Thorisson <mummi@cshl.edu>

#$Id: is.pm,v 1.7 2006-07-14 12:38:52 lstein Exp $

 CHARSET =>   'ISO-8859-1',

   #----------
   # MAIN PAGE
   #----------

   PAGE_TITLE => 'Genome browser',
   
   SEARCH_INSTRUCTIONS => <<END,
Leiti� a� nafni � r��, nafni � geni, l�kus e�a ��ru kennileiti. H�gt er a� nota * (e. wildcard) fyrir frj�lsa leit.
END

   NAVIGATION_INSTRUCTIONS => <<END,
Til a� mi�ja � sta�setningu, smelli� � stikuna. Noti� Skrun/Zoom takkana til a� breyta st�kkun og sta�setningu
END

   EDIT_INSTRUCTIONS => <<END,
H�r m� breyta vistu�um annoteringum. H�gt er a� nota innsl�ttart�kni� (e. tab) e�a stafabil til a� a�skilja reiti, en reitir sem innihalda stafabil �urfa a� vera innan einfaldra e�a tv�faldra g�salappa.
END

   SHOWING_FROM_TO => 'S�ni %s � %s,fr� %s til %s',

   INSTRUCTIONS      => 'Lei�beiningar',

   HIDE              => 'Fela',
   
   SHOW              => 'S�na',

   SHOW_INSTRUCTIONS => 'S�na lei�beiningar',

   HIDE_INSTRUCTIONS => 'Fela lei�beiningar',

   SHOW_HEADER       => 'S�na haus',

   HIDE_HEADER       => 'Fela haus',

   LANDMARK => 'Kennileiti e�a sv��i',

   BOOKMARK => 'Vista sem b�kamerki',

   IMAGE_LINK => 'F� vefsl�� � mynd',

   SVG_LINK   => 'Mynd sem hentar til birtingar',

   SVG_DESCRIPTION => <<END,
<p>
Eftirfarandi sl�� mynd b�r til �essa s�mu mynd � Scalable Vector Graphic (SVG) sni�i. SVG b��ur upp � nokkra umfram "raster"-bygg�ar myndir eins og jpeg e�a png.
</p>
<ul>
<li>h�gt a� breyta st�r� �n �ess a� tapa upplausn
<li>h�gt a� vinna me� myndirnar � myndvinnsluforritum sem h�ndla vector-graf�k, til d�mis f�ra til annoteringar ef vill
<li>ef nau�syn krefur er h�gt a� breyta yfir � EPS-sni� til a� senda til birtingar � v�sindaritum
</ul>
<p>
Til a� sko�a SVG-myndir �arftu a� hafa vafra sem sty�ur SVG-sni�i�, td. Adobe "plugin" fyrir vefvafra, e�a Adobe Illustrator myndvinnsluforriti�.
</p>
<p>
Adobe "plugin": <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Macintosh">Macintosh</a>
| <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Windows">Windows</a>
<br />
Linuxnotendur geta sko�a� �ennan h�r: <a href="http://xml.apache.org/batik/">Batik SVG Viewer</a>.
</p>
<p>
<a href="%s" target="_blank">Sko�a SVG-mynd � n�jum vafraglugga</a></p>
<p>
Til a� vista �essa mynd � har�a diskinn hj� ��r, Ctrl-klikka�u (Macintosh) e�a h�gri-klikka�u (Windows) og veldu "Save link to disk".
</p>   
END

   IMAGE_DESCRIPTION => <<END,
<p>
Til a� setja �essa mynd � heimas��u, afriti� �essa vefsl�� og setji� � HTML-k��ann svona:
</p>
<pre>
&lt;IMAGE src="%s" /&gt;
</pre>
<p>
Myndin mun l�ta svona �t:
</p>
<p>
<img src="%s" />
</p>

<p>
Ef a�eins yfirlitsmyndin  s�st a� ofan, reyni� a� minnka st�r�ina � sv��inu</p>
END

   TIMEOUT  => <<'END',
Fyrirspurn ��n t�k of langan t�ma. �� g�tir hafa vali� sv��i sem er of st�rt til a� s�na. Pr�fa�u a� sl�kkva � einhverjum brautanna, e�a minnka sv��i�. Ef �etta gerist trekk � trekk, vinsamlega �ttu � "Endursetja" takkann.
END

   GO       => 'Keyra',

   FIND     => 'Finna',

   SEARCH   => 'Leita',

   DUMP     => 'Vista',

   HIGHLIGHT => 'Merkja',

   ANNOTATE     => 'Annotera',

   SCROLL   => 'Skrun/Zoom',

   RESET    => 'Endursetja',

   FLIP     => 'Sn�a vi�',

   DOWNLOAD_FILE    => 'Vista skr�',

   DOWNLOAD_DATA    => 'Vista g�gn',

   DOWNLOAD         => 'Vista',

   DISPLAY_SETTINGS => 'Stillinga glugga',

   TRACKS   => 'Brautir',

   EXTERNAL_TRACKS => "(Utana�komandi brautir sk�letra�ar)<br><sup>*</sup>Yfirlitsbraut",

   OVERVIEW_TRACKS => '<sup>*</sup>Yfirlitsbraut',

   REGION_TRACKS  => '<sup>**</sup>Sv��isbraut',

   EXAMPLES => 'D�mi',

   REGION_SIZE  => 'St�r� sv��is (bp)',

   HELP     => 'Hj�lp',

   HELP_FORMAT => 'Hj�lp fyrir skj�sni�',

    CANCEL   => 'H�tta vi�',

   ABOUT    => 'Um...',

   REDISPLAY   => 'S�na aftur',

   CONFIGURE   => 'Stillingar...',

   EDIT       => 'Breyta skr�...',

   DELETE     => 'Ey�a skr�',

   EDIT_TITLE => 'B�ta vi� e�a breyta annoteringum',

   IMAGE_WIDTH => 'Breidd myndar',

   BETWEEN     => 'Milli',

   BENEATH     => 'Undir',

   LEFT        => 'Vinstri',

   RIGHT       => 'H�gri',

   TRACK_NAMES => 'Tafla yfir n�fn � brautum',

   ALPHABETIC  => 'Stafr�fsr��',

   VARYING     => 'Breytilegt',

   SET_OPTIONS => 'Breyta stillingum fyrir brautir...',

   UPDATE      => 'Uppf�ra mynd',

   DUMPS       => 'Dump, leitir og a�rar a�ger�ir',

   DATA_SOURCE => 'Gagnalind',

   UPLOAD_TRACKS  => 'B�ta vi� eigin brautum',

   UPLOAD_TITLE=> 'Vista eigin annoteringar � vef',

   UPLOAD_FILE => 'Vista eigin skr� � vef',

   KEY_POSITION => 'Sta�setning lykils',

   BROWSE      => 'Vafra...',

   UPLOAD      => 'Hla�a upp',

   NEW         => 'N�tt...',

   REMOTE_TITLE => 'B�ta vi� eigin annoteringum',

   REMOTE_URL   => 'Sl� inn vefsl�� fyrir utana�komandi annoteringar',

   UPDATE_URLS  => 'Uppf�ra vefsl��ir',

   PRESETS      => '--Velja fyrirfram uppsettar vefsl��ir--',

   FEATURES_TO_HIGHLIGHT  => 'Kennileiti sem merkja � (kennileiti1, kennileiti2...)',
     
   FEATURES_TO_HIGHLIGHT_HINT  => 'V�sbending: nota�u kennileiti@litur til a� velja litinn, t.d. \'NUT21@lightblue\' ',

   REGIONS_TO_HIGHLIGHT  => 'Merkja sv��i (sv��i1:start..end sv��i2:start..end)',
    
   REGIONS_TO_HIGHLIGHT_HINT  => 'V�sbending: nota�u sv��i@litur, t.d. \'Chr1:1000..2000@lightblue\'',

   NO_TRACKS  => '*engar*',

   FILE_INFO    => 'S��ast uppf�rt %s.  Annoteru� kennileiti: %s',

   FOOTER_1     => <<END,
ATH: �essi s��a notar "sm�k�kur" (e. cookies) til a� a� vista og endurheimta stillingar. Engum uppl�singum er deilt me� utana�komandi a�ilum
END

   FOOTER_2    => 'Generic genome browser version %s',

   #----------------------
   # MULTIPLE MATCHES PAGE
   #----------------------

   HIT_COUNT      => 'Eftirfarandi %d sv��i samsvara fyrirspurninni.',

   POSSIBLE_TRUNCATION  => 'Ni�urst��ur leitur eru takmarka�ir vi� %s atri�i; listinn er hugsanlega ekki t�mandi',

   MATCHES_ON_REF => ' Fundi� � %s',

   SEQUENCE        => 'r��;',

   SCORE           => 'skor=%s',

   NOT_APPLICABLE => 'n/a',

   BP             => 'bp',

   #--------------
   # SETTINGS PAGE
   #--------------

   SETTINGS => 'Stillingar fyrir %s',

   UNDO     => 'Afturkalla breytingar',

   REVERT   => 'Breyta yfir i sj�lfgefnar stillingar',

   REFRESH  => 'Hla�a s��u aftur',

   CANCEL_RETURN   => 'H�tta vi� breytingar og fara til baka...',

   ACCEPT_RETURN   => 'Virkja breytingar og fara til baka...',

   OPTIONS_TITLE => 'Brautarstillingar',

   SETTINGS_INSTRUCTIONS => <<END,
 <i>S�na</i> segir til um hvort braut er s�nileg e�a ekki.
 <I>Sam�jappa�</i> �jappar brautinni saman a eina l�nu
 �annig a� annoteringar munu skarast. 
<i>Brei�a �r</i> og <i>Brei�a meira �r</i>  hindra annoteringar � a� rekast
 hver � a�ra, me�  h�gvirkari og hra�virkari algorithmum
 <i>Brei�a �r & merkja</i> og  <i>Brei�a meira �r & mergja</i>  setur 
merki (e. labels) � allar annoteringar. Ef <i>Sj�lfvirkt</i> er vali� 
eru �rekstrar- og merkjastillingar settar eftir �v� sem pl�ss leyfir.
 Til a� breyta �v� hvernig brautirnar ra�ast upp, noti� <i>Breyta upp��un brauta</i>
 til a� setja tiltekna annoteringu � brautina. Til a� takmarka hversu margar 
annoteringar af tiltekinni tegund eru s�ndar, noti� 
<i>Takmarka fj�lda</i> valmyndina.
END

   TRACK  => 'Braut',

   TRACK_TYPE => 'Tegund brautar',

   SHOW => 'S�na',

   FORMAT => 'Sni�',

   LIMIT  => 'Takmarka fj�lda',

   ADJUST_ORDER => 'Stilla uppr��un brauta',

   CHANGE_ORDER => 'Breyta uppr��un brauta',

   AUTO => 'Sj�lfvirkt',

   COMPACT => 'Sam�jappa�',

   EXPAND => 'Brei�a �r',

   EXPAND_LABEL => 'Brei�a �r & merkja',

   HYPEREXPAND => 'Brei�a meira �r',

   HYPEREXPAND_LABEL =>'Brei�a meira �r & merkja',

   NO_LIMIT    => 'Engin takm�rkun',
       
   OVERVIEW  => 'Yfirlit',

  GENERAL => 'Almennt',

   DETAILS  => 'N�nar',

   ALL_OFF => 'Virkja allar',

   ALL_ON  => 'Afvirkja allar',

   ANALYSIS  => 'Greining',

   REGION  => 'Sv��i',
    

   #--------------
   # HELP PAGES
   #--------------

   CLOSE_WINDOW => 'Loka �essum glugga',

   TRACK_DESCRIPTIONS => 'L�singar og titlar � brautum',

   BUILT_IN           => 'Brautir innbygg�ar � �ennan vef�j�n',

   EXTERNAL           => 'Utana�komandi annoteringarbrautir',

   ACTIVATE           => 'Vinsamlega virkji� �essa braut til a� sj� hva� er � henni...',

   NO_EXTERNAL        => 'Engar utana�komandi annoteringar hla�nar inn.',

   NO_CITATION        => 'Engar frekari uppl�singar f�anlegar.',

   #--------------
   # PLUGIN PAGES
   #--------------

 ABOUT_PLUGIN  => 'Um %s',

 BACK_TO_BROWSER => 'Aftur til GBrowse',

 PLUGIN_SEARCH_1   => '%s (leit me� %s)',

 PLUGIN_SEARCH_2   => '&lt;%s leit&gt;',

 CONFIGURE_PLUGIN   => 'Stilla',

 BORING_PLUGIN => '�essi plugin hefur engar auka stillim�guleika.',

   #--------------
   # ERROR MESSAGES
   #--------------

 NOT_FOUND => 'Kennileiti� <i>%s</i> fannst ekki. Sj� hj�lpars��ur fyrir upp�stungur.',

 TOO_BIG   => 'N�nari s�n er takm�rku� vi� %s bp.  Smelli� � yfirlitsmyndina til velja sv��i
   sem er %s bp a� st�r�.',

 PURGED    => "Finn ekki skr�na %s. Hefur henni veri� hent?",

 NO_LWP    => "�essi vef�j�nn er ekki stilltur til a� n� � utana�komandi vefsl��ir",

 FETCH_FAILED  => "Gat ekki n�� � %s: %s.",

 TOO_MANY_LANDMARKS => '%d kennileiti.  Of m�rg til a� telja upp!.',

 SMALL_INTERVAL    => 'Breyti st�r� sv��is � %s bp',
          
CLEAR_HIGHLIGHTING  => 'Fjarl�gja merkingar',

CONFIGURE_TRACKS  => 'Stilla brautir...', 
     
NO_SOURCES  => 'Engar a�gengilegar gagnalindir stilltar. Kannske hefur �� ekki leyfi til a� sko�a ��r',

};

