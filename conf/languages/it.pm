# do not remove the { } from the top and bottom of this page!!!
# Translation by: Marco Mangone <mangone@cshl.edu>
# Revised by: Alessandra Bilardi <alessandra.bilardi@gmail.com>
{

 CHARSET =>   'ISO-8859-1',
   #----------
   # MAIN PAGE
   #----------

   PAGE_TITLE => 'Visualizzatore Genomico',

   SEARCH_INSTRUCTIONS => <<END,
Cerca utilizzando un nome di sequenza, nome di gene,
locus%s o altri punti di riferimento. Utilizzare *
per indicare un carattere qualsiasi.
END

   NAVIGATION_INSTRUCTIONS => <<END,
Per centrare su un punto, fare clic sul righello. Usare i pulsanti Sfoglia/Zoom
per cambiare la scala e la posizione. Per memorizzare questa videata,
<a href="%s">salvare questo collegamento tra i preferiti.</a>
END

   EDIT_INSTRUCTIONS => <<END,
Da qui e` possibile modificare i dati di annotazione.
I campi possono essere separati mediante spazi semplici o tabulatori,
ma i campi contenenti spazi devono essere delimitati
da virgolette o apostrofi.
END

   SHOWING_FROM_TO => 'Mappa di %s da %s, posizione %s - %s',

   INSTRUCTIONS    => 'Istruzioni',

   HIDE           => 'Nascondi',

   SHOW           => 'Mostra',
  
   SHOW_INSTRUCTIONS => 'Mostra Istruzioni',

   HIDE_INSTRUCTIONS => 'Nascondi Istruzioni',

   SHOW_HEADER       => 'Mostra banner',

   HIDE_HEADER       => 'Nascondi banner',

   LANDMARK => 'Elemento Genomico o Regione',

   BOOKMARK => 'Aggiungi ai Preferiti',

   IMAGE_LINK => "Vai all'Immagine",

   PDF_LINK   => 'Scarica il PDF',

   SVG_LINK   => 'Immagine ad Alta Risoluzione',
#ale#   SVG_LINK   => 'Immagine in qualita` di pubblicazione',
   SVG_DESCRIPTION => <<END,
<p>
Il seguente link ipertestuale generera` questa immagine in formato vettoriale scalabile (SVG). Il formato SVG offre molti vantaggi rispetto al formato jpeg oppure png.
</p>
<ul>
<li>e` completamente scalabile senza perdita di risoluzione
<li>e` completamente editabile usando i comuni programmi di grafica vettoriale 
<li>se necessario, puo` essere convertito in formato EPS per necessita` di pubblicazione
</ul>
<p>
Per poter vedere un'immagine in formato SVG e` necessario avere un browser compatibile e il plug-in di Adobe chiamato 'SVG browser' oppure un'applicazione che permette di leggere file con le estensioni .SVG come Adobe Illustrator.
</p>
<p>
<!--Adobe's SVG browser plugin: <a #ale#-->
plugin del Visualizzatore SVG di Adobe: <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Macintosh">Macintosh</a>
| <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Windows">Windows</a>
<br />
Gli utenti Linux possono utilizzare il  <a href="http://xml.apache.org/batik/">Visualizzatore SVG di Batik SVG</a>.
</p>
<p>
<a href="%s" target="_blank">Apri l'immagine in una nuova finestra</a></p>
<p>
Per salvare questa immagine nel disco rigido premi control (utenti Machintosh) oppure il tasto destro del mouse (utenti Windows) e seleziona l'opzione 'salva' su disco rigido.
</p>   
END





IMAGE_DESCRIPTION => <<END,
<p>
Per creare un'immagine allegata usando questa immagine 'taglia e incolla' questo Indirizzo Internet in una pagina ipertestuale:</p>
<pre>
&lt;IMAGE src="%s" /&gt;
</pre>
<p>
L'immagine che si otterra` e` la seguente:
<!--L'immagine rassomigliera` a questa: #ale#-->
</p>
<p>
<img src="%s" />
</p>

<p>
Se l'immagine mostrata (sia cromosomica o del contiguo) e` parziale o incompleta, prova a ridurre la grandezza della regione.
</p>
END



TIMEOUT  => <<'END',
La tua richiesta e` stata interrotta. Potresti aver selezionato una regione troppo grande da mostrare in una schermata. Puoi o de-selezionare alcune tracce oppure provare con una regione piu` piccola. Se il problema si ripropone, premere il pulsante rosso "Reset". #ale#
END



   GO       => 'Vai',

   FIND     => 'Cerca',

   SEARCH   => 'Cerca',

   DUMP     => 'Scarica',

   HIGHLIGHT   => 'Evidenzia',

   ANNOTATE     => 'Annota',

   SCROLL   => 'Sfoglia/Zoom',

   RESET    => 'Ripristina',

   FLIP     => 'Gira',

   DOWNLOAD_FILE    => 'Scarica File',

   DOWNLOAD_DATA    => 'Scarica dati',

   DOWNLOAD         => 'Scarica',

   DISPLAY_SETTINGS => 'Visualizza parametri',

   TRACKS   => 'Tracce',

   EXTERNAL_TRACKS => '<i>Tracce esterne in corsivo</i>',

   OVERVIEW_TRACKS => '<sup>*</sup>Tracce Panoramica',

   REGION_TRACKS => '<sup>**</sup>Tracce Regione',

   EXAMPLES => 'Esempi',

   REGION_SIZE => 'Dimensione Regione (bp)',

   HELP     => 'Guida',

   HELP_FORMAT => 'Guida ai formati dei file',
#ale#   HELP_FORMAT => 'Aiuto con in formati dei files',
   CANCEL   => 'Annulla',

   ABOUT    => 'Informazioni...',

   REDISPLAY   => 'Rivisualizza',

   CONFIGURE   => 'Configura...',

   CONFIGURE_TRACKS   => 'Configura tracce...',

   EDIT       => 'Modifica file',

   DELETE     => 'Cancella file',

   EDIT_TITLE => 'Inserisci/modifica dati',

   IMAGE_WIDTH => 'Lunghezza immagine',

   BETWEEN     => 'In Mezzo',

   BENEATH     => 'Sotto',

   LEFT        => 'Sinistra',

   RIGHT       => 'Destra',

   TRACK_NAMES => 'Ordina nomi tracce',
#ale#   TRACK_NAMES => 'Tavola nomi tracce',
   ALPHABETIC  => 'Alphabetico',

   VARYING     => 'Secondo Configurazione',
#ale# VARYING => 'Variazione', English:Varying->As Configuration
   SHOW_GRID    => 'Mostra griglia',   

   SET_OPTIONS => 'Configura opzioni delle tracce...',

   CLEAR_HIGHLIGHTING => 'Ritorna ai colori di configurazione',

   UPDATE      => 'Aggiorna immagine',

   DUMPS       => 'Scaricamento, Ricerca e altre operazioni',

   DATA_SOURCE => 'Origine dei dati',

   UPLOAD_TRACKS=>'Carica le tue tracce', 

   UPLOAD_TITLE=> 'Carica le tue annotazioni',

   UPLOAD_FILE => 'Carica un file',

   KEY_POSITION => 'Posizione nomi tracce',
#ale#   KEY_POSITION => 'Posizione tasto',
   BROWSE      => 'Sfoglia...',

   UPLOAD      => 'Carica',

   NEW         => 'Nuovo...',

   REMOTE_TITLE => 'Aggiungi annotazioni remote',

   REMOTE_URL   => 'Inserisci URL di annotazioni remote',

   UPDATE_URLS  => 'Aggiorna URL',

   PRESETS      => '--Scegli URL predefinito--',

   FEATURES_TO_HIGHLIGHT => 'Evidenzia tracce (traccia1 traccia2...)',

   REGIONS_TO_HIGHLIGHT => 'Evidenzia regioni (regione1:inizio..fine regione2:inizio..fine)',

   FEATURES_TO_HIGHLIGHT_HINT => 'Guida: usa traccia@colore per selezionare il colore, ad esempio \'NUT21@lightblue\'',

   REGIONS_TO_HIGHLIGHT_HINT  => 'Guida: usa regione@colore per selezionare il colore, ad esempio \'Chr1:10000..20000@lightblue\'',

   NO_TRACKS    => '*nessuna*', #ale# but I could need the specific context 

   FILE_INFO    => 'Ultima modifica %s. Oggetti annotati: %s',

   FOOTER_1     => <<END,
Nota: Questa pagina usa cookie per memorizzare e ripristinare configurazioni preferite.
Le informazioni non vengono redistribuite.
END

   FOOTER_2    => 'Visualizzatore genomico generico versione %s',

   #----------------------
   # MULTIPLE MATCHES PAGE
   #----------------------

   HIT_COUNT      => 'Le seguenti %d regioni soddisfano la tua richiesta',

   POSSIBLE_TRUNCATION  => 'I risultati della ricerca sono limitati a %d\' valori; La lista potrebbe essere incompleta',

   MATCHES_ON_REF => 'Corrispondenza su %s',

   SEQUENCE        => 'sequenza',

   SCORE           => 'punteggio=%s',

   NOT_APPLICABLE => 'n/a',

   BP             => 'bp',

   #--------------
   # SETTINGS PAGE
   #--------------

   SETTINGS => 'Configurazione per %s',

   UNDO     => 'Annulla modifiche',

   REVERT   => 'Torna alla configurazione iniziale',
#ale#   REVERT   => 'Torna alla configurazione standard',
   REFRESH  => 'Aggiorna',

   CANCEL_RETURN   => 'Annulla modifiche e torna indietro...',

   ACCEPT_RETURN   => 'Accetta le modifiche e torna indietro...',

   OPTIONS_TITLE => 'Opzioni di traccia',

   SETTINGS_INSTRUCTIONS => <<END,
Il pulsante <I>Mostra</I> attiva o disattiva la traccia. 
L'opzione <I>Compatto</I> forza la compressione delle tracce in modo che le annotazioni vengano sovrapposte.
Le opzioni <I>Espandi</I> e <I>Iper-espandi</I> attivano il controllo di collisione utilizzando algoritmi di allineamento rispettivamente lenti o veloci.
Le opzioni <I>Espandi &amp; Etichetta</I> e <I>Iper-espandi &amp; Etichetta</I> servono a contrassegnare le annotazioni.
Selezionando <I>Automatico<I>, il controllo di collisione e le opzioni di etichettatura
vengono attivate automaticamente, spazio consentendo.
Per cambiare l'ordine delle tracce, usare il menu <I>Cambia ordine delle tracce<I>
per assegnare un'annotazione ad una traccia.
Per limitare il numero di annotazioni di questo tipo visualizzate,
cambiare il valore del menu <I>Limiti</I>.
END


   TRACK  => 'Traccia',

   TRACK_TYPE => 'Tipo traccia',

   SHOW => 'Mostra',

   FORMAT => 'Formato',

   LIMIT  => 'Limiti',

   ADJUST_ORDER => 'Riordina',

   CHANGE_ORDER => 'Cambia l\'ordine delle tracce',

   AUTO => 'Automatico',

   COMPACT => 'Compatto',

   EXPAND => 'Espandi',

   EXPAND_LABEL => 'Espandi & Etichetta',

   HYPEREXPAND => 'Iper-espandi',

   HYPEREXPAND_LABEL =>'Iper-espandi & Etichetta',

   NO_LIMIT    => 'Senza limiti',

   OVERVIEW   => 'Panoramica',

   EXTERNAL  => 'Esterna',

   ANALYSIS  => 'Analisi',

   GENERAL  =>  'Generale',

   DETAILS  => 'Dettagli',

   REGION => 'Regione',

   ALL_ON   => 'Mostra tutto',

   ALL_OFF  => 'Nascondi tutto',

   #--------------
   # HELP PAGES
   #--------------

   OK                 => 'OK',

   CLOSE_WINDOW => 'Chiudi la finestra',

   TRACK_DESCRIPTIONS => 'Descrizione delle tracce & Citazioni',

   BUILT_IN           => 'Tracce annotate su questo server', 

   EXTERNAL           => 'Tracce annotate esternamente',

   ACTIVATE           => 'Attivare questa traccia per visualizzare le relative informazioni.',

   NO_EXTERNAL        => 'Nessuna caratteristica esterna e` caricata.',

   NO_CITATION        => 'Informazioni addizionali non disponibili.',

   #--------------
   # PLUGIN PAGES
   #--------------

 ABOUT_PLUGIN  => 'Informazioni su %s',

 BACK_TO_BROWSER => 'Torna al Visualizzatore',

 PLUGIN_SEARCH   => 'ricerca con il plugin %s',

 CONFIGURE_PLUGIN   => 'Configura',

 BORING_PLUGIN => 'Questo plugin non ha alcuna configurazione extra.',

   #--------------
   # ERROR MESSAGES
   #--------------

 NOT_FOUND => "L'oggetto <I>%s</I> è sconosciuto. Per suggerimenti, consulta la pagina di aiuto.",
#ale# NOT_FOUND => "L'oggetto <I>%s</I> è sconosciuto. Vedi la pagina di aiuto per suggerimenti.",
 TOO_BIG   => "Visualizzazione dei dettagli limitata a %s basi. Fare clic sull'immagine per selezionare una regione di %s bp.",

 PURGED    => "Non trovo il file %s. Non sarà stato cancellato?.",

 NO_LWP    => "Questo server non è configurato per accedere ad URL esterni.",

 FETCH_FAILED  => "Non riesco a prelevare %s: %s.",

 TOO_MANY_LANDMARKS => '%d punti sono troppi per elencarli singolarmente.',

 SMALL_INTERVAL    => 'Computazione piccolo intervallo a %s bp',

 NO_SOURCES   =>'I dati delle fonti (source) configurate non sono leggibili oppure non hai il permesso di vederli',
#ale# NO_SOURCES   =>'input dati non e` stato configurato oppure non hai il permesso di vederli',
 ADD_YOUR_OWN_TRACKS => 'Aggiungi le tue tracce',

 INVALID_SOURCE => 'Il nome della fonte (source) %s non e` valida',

 BACKGROUND_COLOR => 'Colore di sfondo',

 FG_COLOR => 'Colore della linea',

 HEIGHT => 'Altezza',

 PACKING => 'Formato',

 GLYPH => 'Figura',

 LINEWIDTH => 'Larghezza linea',

 DEFAULT => '(opzione predefinita)',

 DYNAMIC_VALUE => 'Calcolato dinamicamente',

 CHANGE => 'Modifica',

 DRAGGABLE_TRACKS => 'Tracce da trascinare',

 CACHE_TRACKS => 'Tracce in memoria',

 SHOW_TOOLTIPS => 'Mostra suggerimenti',

 OPTIONS_RESET => 'Tutte le pagine di configurazione saranno resettate ai valori predefiniti',

 OPTIONS_UPDATED => 'E\' in vigore una nuova configurazione; tutte le pagine di configurazione saranno resettate ai valori predefiniti',
 
 SEND_TO_GALAXY    => 'Invia questa regione a Galaxy',

 NO_DAS            => 'Errore di installazione: il modulo Bio::Das deve essere installato perche\' gli URL di DAS lavorino. Informare l\'amministratore di questo sito.',

 SHOW_OR_HIDE_TRACK => '<b>Mostra o nascondi questa traccia</b>',

 CONFIGURE_THIS_TRACK   => '<b>Clicca per cambiare l\'impostazione della traccia.</b>',

 SHARE_THIS_TRACK   => '<b>Condividi questa traccia</b>',

 SHARE_ALL          => 'Condividi queste tracce',

 SHARE              => 'Condividi %s',

 SHARE_INSTRUCTIONS_ONE_TRACK => <<END,
Per condividere questa traccia con un altro visualizzatore genomico GBrowse,
copia l\'URL sottostante, vai nell\'altro GBrowse e incolla l\'URL nel campo
"Inserisci URL di annotazioni" in fondo alla pagina. Se questa traccia
deriva da un file caricato, e viene condiviso l\'URL con un altro 
utente, con <b>tutti<\b> i permessi, i dati caricati saranno 
visibili da questo utente.
END

 SHARE_INSTRUCTIONS_ALL_TRACKS => <<END,
Per condividere queste tracce con un altro visualizzatore genomico GBrowse,
copia l\'URL sottostante, vai nell\'altro GBrowse e incolla l\'URL nel campo
"Inserisci URL di annotazioni" in fondo alla pagina. Se queste tracce
derivano da un file caricato, e viene condiviso l\'URL con un altro 
utente, con <b>tutti<\b> i permessi, i dati caricati saranno 
visibili da questo utente.
END

 SHARE_DAS_INSTRUCTIONS_ONE_TRACK => <<END,
Per condividere questa traccia con un altro visualizzatore genomico usando
<a href="http://www.biodas.org" target="_new">Distributed Annotation System
 (DAS)</a>, copia l\'URL sottostante, vai nell\'altro visualizzatore e 
inserisci l\'URL come una nuova sorgente DAS.
<i>Tracce quantitative (file "wiggle") e file caricati non possono essere
condivisi usando DAS.</i>
END

 SHARE_DAS_INSTRUCTIONS_ALL_TRACKS => <<END,
Per condividere queste tracce con un altro visualizzatore genomico usando
<a href="http://www.biodas.org" target="_new">Distributed Annotation System
 (DAS)</a>, copia l\'URL sottostante, vai nell\'altro visualizzatore e 
inserisci l\'URL come una nuova sorgente DAS.
<i>Tracce quantitative (file "wiggle") e file caricati non possono essere
condivisi usando DAS.</i>
END

};





