# do not remove the { } from the top and bottom of this page!!!
{
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
Da qui è possibile modificare i dati di annotazione.
I campi possono essere separati mediante spazi semplici o tabulatori,
ma i campi contenenti spazi spazi devono essere delimitati
da virgolette o apostrofi.
END

   SHOWING_FROM_TO => 'Mappa di %s da %s, posizione %s - %s',

   LANDMARK => 'Elemento genomico o regione',

   GO       => 'Vai',

   FIND     => 'Cerca',

   DUMP     => 'Scarica',

   ANNOTATE     => 'Annota',

   SCROLL   => 'Sfoglia/Zoom',

   RESET    => 'Ripristina',

   DOWNLOAD_FILE    => 'Scarica File',

   DOWNLOAD_DATA    => 'Scarica dati',

   DOWNLOAD         => 'Scarica',

   DISPLAY_SETTINGS => 'Visualizza parametri',

   TRACKS   => 'Tracce',

   EXTERNAL_TRACKS => '(Tracce esterne in corsivo)',

   EXAMPLES => 'Esempi',

   HELP     => 'Guida',

   HELP_FORMAT => 'Aiuto con in formati dei files',

   CANCEL   => 'Annulla',

   ABOUT    => 'Informazioni...',

   REDISPLAY   => 'Rivisualizza',

   CONFIGURE   => 'Configura',

   EDIT       => 'Modifica file',

   DELETE     => 'Cancella file',

   EDIT_TITLE => 'Inserisci/modifica dati',

   IMAGE_WIDTH => 'Lunghezza immagine',

   SET_OPTIONS => 'Configura opzioni delle tracce...',

   UPDATE      => 'Aggiorna immagine',

   DUMPS       => 'Scaricamento, Ricerca e altre operazioni',

   DATA_SOURCE => 'Origine dei dati',

   UPLOAD_TITLE=> 'Carica le tue annotazioni',

   UPLOAD_FILE => 'Carica un file',

   BROWSE      => 'Sfoglia...',

   UPLOAD      => 'Carica',

   REMOTE_TITLE => 'Aggiungi annotazioni remote',

   REMOTE_URL   => 'Inserisci URL di annotazioni remote',

   UPDATE_URLS  => 'Aggiorna URLs',


   PRESETS      => '--Scegli URL predefinito--',

   FILE_INFO    => 'Ultima modifica %s. Oggetti annotati: $s',

   FOOTER_1     => <<END,
Nota: Questa pagina usa cookie per memorizzare e ripristinare configurazioni preferite.
Le informazioni non vengono ridistribuite.
END

   FOOTER_2    => 'Visualizzatore genomico generico versione %s',

   #----------------------
   # MULTIPLE MATCHES PAGE
   #----------------------

   HIT_COUNT      => 'Le seguenti %d regioni soddisfano la tua richiesta',

   MATCHES_ON_REF => 'Corrispondenza su %s',

   SEQUENCE        => 'sequenza',

   SCORE           => 'punteggio=%s',

   NOT_APPLICABLE => '..',

   BP             => 'bp',

   #--------------
   # SETTINGS PAGE
   #--------------

   SETTINGS => 'Configurazione per %s',

   UNDO     => 'Annulla modifiche',

   REVERT   => 'Torna alla configurazione standard',

   REFRESH  => 'Aggiorna',

   CANCEL_RETURN   => 'Annulla modifiche e torna indietro...',

   ACCEPT_RETURN   => 'Accetta le modifiche e torna indietro...',

   OPTIONS_TITLE => 'Opzioni di traccia',

   SETTINGS_INSTRUCTIONS => <<END,
Il pulsante <I>Mostra</I> attiva o disattiva la traccia. 
L' opzione <I>Compatto</I> forza la compressione delle tracce
sì che le annotazioni vengano sovrapposte.
Le opzioni <I>Espandi</I> e <I>Iper-espandi</I> attivano il controllo
di collisione utilizzando algoritmi di allineamento rispettivamente lenti o veloci.
Le opzioni <I>Espandi &amp; Etichetta</I> e <I>Iper-espandi &amp; Etichetta</I>
servono a contrassegnare le annotazioni.
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

   #--------------
   # HELP PAGES
   #--------------

   CLOSE_WINDOW => 'Chiudi la finestra',

   TRACK_DESCRIPTIONS => 'Descrizione delle tracce & Citazioni',

   BUILT_IN           => 'Tracce annotate su questo server', 

   EXTERNAL           => 'Tracce annotate esternamente',

   ACTIVATE           => 'Attivare questa traccia per visualizzare le relative informazioni.',

   NO_EXTERNAL        => 'Nessuna caratteristica esterna è caricata.',

   NO_CITATION        => 'Informazioni addizionali non disponibili.',

   #--------------
   # PLUGIN PAGES
   #--------------

 ABOUT_PLUGIN  => 'Informazioni su %s',

 BACK_TO_BROWSER => 'Torna al Visualizzatore',

 PLUGIN_SEARCH_1   => '%s (mediante ricerca %s)',

 PLUGIN_SEARCH_2   => '&lt;ricerca %s&gt;',

 CONFIGURE_PLUGIN   => 'Configura',

 BORING_PLUGIN => 'Questo plugin non ha alcuna configurazione extra.',

   #--------------
   # ERROR MESSAGES
   #--------------

 NOT_FOUND => "L'oggetto <I>%s</I> è sconosciuto. Vedi la pagina di aiuto per suggerimenti.",

 TOO_BIG   => "Visualizzazione dei dettagli limitata a %s basi. Fare clic sull'immagine per selezionare una regione di %s bp.",

 PURGED    => "Non trovo il file %s. Non sarà stato cancellato?.",

 NO_LWP    => "Questo server non è configurato per accedere ad URL esterni.",

 FETCH_FAILED  => "Non riesco a prelevare %s: %s.",

 TOO_MANY_LANDMARKS => '%d punti sono troppi per elencarli singolarmente.',

};
