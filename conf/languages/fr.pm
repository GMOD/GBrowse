# do not remove the { } from the top and bottom of this page!!!
{
   #----------
   # MAIN PAGE
   #----------

 CHARSET =>   'ISO-8859-1',

   PAGE_TITLE => 'Genome browser',

   SEARCH_INSTRUCTIONS => <<END,
Vous pouvez faire une recherche en utilisant un
nom de séquence, un nom de gène, un locus %s,
ou un autre référentiel. Le caractère spécial * est
autorisé.
END

   NAVIGATION_INSTRUCTIONS => <<END,
Pour vous recentrer sur un emplacement, cliquez sur la règle. Utilisez
les boutons Défil./Zoom pour changer l'échelle et la position. Pour
sauvegarder cette vue, <a href="%s">ajoutez ce lien à vos favoris.</a>
END

   EDIT_INSTRUCTIONS => <<END,
Editez vos données d'annotations additionnelles ici. Vous pouvez
utiliser des tabulations ou des espaces pour séparer les champs,
mais les champs contenant des espaces doivent être contenus dans
des quotes (simples ou doubles).
END

   SHOWING_FROM_TO => 'Vue de %s depuis %s, positions %s à %s',

   LANDMARK => 'Référentiel ou Région',

   GO       => 'Aller à',

   FIND     => 'Trouver',

   DUMP     => 'Sortie',

   ANNOTATE     => 'Annoter',

   SCROLL   => 'Défil./Zoom',

   RESET    => 'Remise à zéro',

   DOWNLOAD_FILE    => 'Télécharger un fichier',

   DOWNLOAD_DATA    => 'Télécharger des données',

   DOWNLOAD         => 'Télécharger',

   DISPLAY_SETTINGS => 'Préférences d\'affichage',

   TRACKS   => 'Pistes',

   EXTERNAL_TRACKS => '(Pistes externes en italique)',

   EXAMPLES => 'Exemples',

   HELP     => 'Aide',

   HELP_FORMAT => 'Aide sur le format de fichiers',

   CANCEL   => 'Annuler',

   ABOUT    => 'A propos...',

   REDISPLAY   => 'Rafraichir l\'affichage',

   CONFIGURE   => 'Configurer...',

   EDIT       => 'Editer le fichier...',

   DELETE     => 'Effacer le fichier',

   EDIT_TITLE => 'Entrer/éditer des données d\'annotation',

 INSTRUCTIONS      => 'Instructions',

 HIDE              => 'Cacher',

 SHOW              => 'Montrer',

 SHOW_INSTRUCTIONS => 'Montrer les instructions',

 SEARCH  => 'Chercher',

 KEY_POSITION => 'Position clef',

 BETWEEN     => 'Entre',

 BENEATH     => 'Après',

   IMAGE_WIDTH => 'Largeur d\'image',

   SET_OPTIONS => 'Configurer les pistes...',

   UPDATE      => 'Mise à jour de l\'image',

   DUMPS       => 'Sorties, recherches et autres opérations',

   DATA_SOURCE => 'Source de données',

   UPLOAD_TITLE=> 'Ajouter vos propres annotations',

   UPLOAD_FILE => 'Ajouter un fichier',

   BROWSE      => 'Parcourir...',

   UPLOAD      => 'Ajouter',

   NEW         => 'Nouveau...',

   REMOTE_TITLE => 'Ajouter des annotations distantes',

   REMOTE_URL   => 'Entrer une URL pour des annotations distantes',

   UPDATE_URLS  => 'Mettre à jour les URLs',

   PRESETS      => "--Choix d'une URL prédéfinie--",

   FILE_INFO    => 'Dernière modif. %s.  Référentiel annoté : %s',

   FOOTER_1     => <<END,
NB: Cette page utilise un cookie pour sauver et restituer les informations
de configuration. Vos informations ne sont pas partagées.
END

   FOOTER_2    => 'Generic genome browser version %s',

   #----------------------
   # MULTIPLE MATCHES PAGE
   #----------------------

   HIT_COUNT      => 'Les  %d régions suivantes correspondent à votre requête.',

   MATCHES_ON_REF => 'Correspondance avec %s',

   SEQUENCE        => 'séquence',

   SCORE           => 'score=%s',

   NOT_APPLICABLE => 'n/a',

   BP             => 'pb',

   #--------------
   # SETTINGS PAGE
   #--------------

   SETTINGS => 'Paramètres pour %s',

   UNDO     => 'Annuler les modifications',

   REVERT   => 'Valeurs par défaut',

   REFRESH  => 'Rafraichir',

   CANCEL_RETURN   => 'Annuler les modifications et revenir...',

   ACCEPT_RETURN   => 'Accepter les modifications et revenir...',

   OPTIONS_TITLE => 'Options de pistes',

   SETTINGS_INSTRUCTIONS => <<END,
La boite <i>Voir</i> active ou désctive la piste. L'option
<i>Compacter</i> force la piste à être consensée pour que 
les annotations se chevauchent. Les options <i>'Etendre'</i>
et <i>Hyperétendre</i> activent un contrôle de collision qui
utilise des algorithmes de mise en page plus lents et plus rapides.
Les options <i>Etendre</i> &amp; <i>étiqueter</i> et <i>Hyperétendre</i>
&amp; <i>étiqueter</i> rend obligatoire l'étiquetage des annotations.
Si <i>Auto</i> est sélectionné, le contrôle de collision et les
options d'étiquetage seront réglées automatiquements si l'espace
le permet. Pour changer l'ordre des pistes, utilisez le menu 
<i>Changer l'ordre des pistes</i> pour assigner une annotation
à une piste. Pour limiter le nombre d'annotations de ce type
devant être affichées, il faut changer la valeur du menu
<i>Limite</i>.
END

   TRACK  => 'Piste',

   TRACK_TYPE => 'Type de Piste',

   SHOW => 'Voir',

   FORMAT => 'Format',

   LIMIT  => 'Limite',

   ADJUST_ORDER => 'Ajuster l\'ordre',

   CHANGE_ORDER => 'Changer l\'ordre des pistes',

   AUTO => 'Auto',

   COMPACT => 'Compacter',

   EXPAND => 'Etendre',

   EXPAND_LABEL => 'Etendre & étiqueter',

   HYPEREXPAND => 'Hyperétendre',

   HYPEREXPAND_LABEL =>'Hyperétendre & étiqueter',

   NO_LIMIT    => 'Pas de limite',

   #--------------
   # HELP PAGES
   #--------------

   CLOSE_WINDOW => 'Fermer cette fenêtre',

   TRACK_DESCRIPTIONS => 'Description de la piste citations',

   BUILT_IN           => 'Pistes disponibles sur ce serveur',

   EXTERNAL           => 'Pistes d\'annotation externes',

   ACTIVATE           => 'Veuillez activer cette piste pour voir ses informations.',

   NO_EXTERNAL        => 'Il n\'y a pas de caractéristiques externes chargées.',

   NO_CITATION        => 'Il n\'y a pas d\'informations supplémentaires disponibles.',

   #--------------
   # PLUGIN PAGES
   #--------------

 ABOUT_PLUGIN  => 'A propos de %s',

 BACK_TO_BROWSER => 'Retour au Browser',

 PLUGIN_SEARCH_1   => '%s (via la recherche %s)',

 PLUGIN_SEARCH_2   => '&lt; Recherche %s &gt;',

 CONFIGURE_PLUGIN   => 'Configurer',

 BORING_PLUGIN => "Ce module n'a pas de paramètres de configuration supplémentaires.",

   #--------------
   # ERROR MESSAGES
   #--------------

 NOT_FOUND => "Le référentiel <i>%s</i> n'est pas reconnu. Voyez l\'aide pour des suggestions.",

 TOO_BIG   => 'La vue détaillée est limitée à %s bases.  Cliquez sur la vue d\'ensemble pour sélectionner une région de largeur %s pb.',

 PURGED    => "Impossible de trouver le fichier nommé %s.  Peut être a-t-il été supprimé ?",

 NO_LWP    => "Ce serveur n\'est pas configuré pour ramener des URLs externes.",

 FETCH_FAILED  => "Je n\'ai pas pu retrouver %s: %s.",

 TOO_MANY_LANDMARKS => '%d référentiels.  La liste est trop grande.',

 SMALL_INTERVAL    => 'Redimmensionnement du petit intervalle à %s pb',

};
