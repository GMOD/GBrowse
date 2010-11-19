# translation from: Franck Aniere <aniere@genoscope.cns.fr>
# do not remove the { } from the top and bottom of this page!!!
{
   #----------
   # MAIN PAGE
   #----------

 CHARSET =>   'ISO-8859-1',

   PAGE_TITLE => 'Genome browser',

   SEARCH_INSTRUCTIONS => <<END,
Vous pouvez faire une recherche en utilisant un
nom de s�quence, un nom de g�ne, un locus %s,
ou un autre r�f�rentiel. Le caract�re sp�cial * est
autoris�.
END

   NAVIGATION_INSTRUCTIONS => <<END,
Pour vous recentrer sur un emplacement, cliquez sur la r�gle. Utilisez
les boutons D�fil./Zoom pour changer l'�chelle et la position. Pour
sauvegarder cette vue, <a href="%s">ajoutez ce lien � vos favoris.</a>
END

   EDIT_INSTRUCTIONS => <<END,
Editez vos donn�es d'annotations additionnelles ici. Vous pouvez
utiliser des tabulations ou des espaces pour s�parer les champs,
mais les champs contenant des espaces doivent �tre contenus dans
des quotes (simples ou doubles).
END

   SHOWING_FROM_TO => 'Vue de %s depuis %s, positions %s � %s',

   INSTRUCTIONS      => 'Instructions',

   HIDE              => 'Cacher',

   SHOW              => 'Montrer',

   SHOW_INSTRUCTIONS => 'Montrer les instructions',

   HIDE_INSTRUCTIONS => 'Cacher les instructions',

   SHOW_HEADER       => 'Montrer l\'en-t�te',

   HIDE_HEADER       => 'Cacher l\'en-t�te',

   LANDMARK => 'R�f�rentiel ou R�gion',

   BOOKMARK => 'Ajouter cet affichage � vos favoris',

   IMAGE_LINK => 'Lien vers une image de cet affichage',

   SVG_LINK   => 'Image haute qualit� pour les publications',

   SVG_DESCRIPTION => <<END,
<p>
Le lien suivant permet de g�n�rer une image au format Scalable Vector Graphic (SVG). Les images SVG disposent de certains avantages sur les images bitmap (jpeg or png for exampe).
</p>
<ul>
<li>Possibilit� de redimmensionner l'image sans perte de r�solution
<li>Edition objet par objet dans dans des applications de dessin vectoriel
<li>Conversion au format EPS (Encapsulated PostScript) si n�cessaire pour des soumissions de publications
</ul>
<p>
Pour voir des images SVG, vous devez disposer d'un navigateur qui sache les afficher, le plugin Adobe SVG, ou une application de visualisation/�dition SVG telle qu'Adobe Illustrator.
</p>
<p>
Plugin Adobe pour navigateurs : <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Macintosh">Macintosh</a>
| <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Windows">Windows</a>
<br />
Les utilisateurs de Linux peuvent regarder le <a href="http://xml.apache.org/batik/">Batik SVG Viewer</a>.
</p>
<p>
<a href="%s" target="_blank">Voir l'image SVG dans une nouvelle fen�tre du navigateur.</a></p>
<p>
Pour Sauver cette image sur votre disque, control-click (Macintosh) ou bouton-droit de la souris (windows) et choisisser l'option pour sauver le lien sur disque.
</p>
END

   IMAGE_DESCRIPTION => <<END,
<p>
Pour cr�er une image incrust�e de cet affichage, il faut copier et coller
cette URL dans une page HTML :
</p>
<pre>
&lt;IMAGE src="%s" /&gt;
</pre>
<p>
L'image ressemblera � ceci :
</p>
<p>
<img src="%s" />
</p>

<p>
Si seul l'aper�u (affichage d'un chromosome ou contig) est visible, il
faut essayer de r�duire la taille de la r�gion.
</p>
END

TIMEOUT  => <<'END',
Le d�lai allou� pour votre requ�te a expir�. Vous avez probablement choisi une
r�gion trop grande pour �tre affich�e. Vous pouvez d�cocher quelques pistes ou essayer une r�gion plus petite. Si le probl�me persiste, veuillez cliquer sur le bouton rouge ("Remise � z�ro").
END


   GO       => 'Lancer',

   FIND     => 'Trouver',

   SEARCH  => 'Chercher',

   DUMP     => 'Sortie',

   HIGHLIGHT   => 'Surligner',

   ANNOTATE     => 'Annoter',

   SCROLL   => 'D�fil./Zoom',

   RESET    => 'Remise � z�ro',

   FLIP     => 'Inversion',

   DOWNLOAD_FILE    => 'T�l�charger un fichier',

   DOWNLOAD_DATA    => 'T�l�charger des donn�es',

   DOWNLOAD         => 'T�l�charger',

   DISPLAY_SETTINGS => 'Pr�f�rences d\'affichage',

   TRACKS   => 'Pistes',

   EXTERNAL_TRACKS => '(Pistes externes en italique)',

   OVERVIEW_TRACKS => '<sup>*</sup>Piste d\'aper�u',

   REGION_TRACKS => '<sup>**</sup>Piste des r�gions',

   EXAMPLES => 'Exemples',

   REGION_SIZE => 'Taille de la r�gion (pb)',

   HELP     => 'Aide',

   HELP_FORMAT => 'Aide sur le format de fichiers',

   CANCEL   => 'Annuler',

   ABOUT    => 'A propos...',

   REDISPLAY   => 'Rafraichir l\'affichage',

   CONFIGURE   => 'Configurer...',

   CONFIGURE_TRACKS   => 'Configurer les pistes...',

   EDIT       => 'Editer le fichier...',

   DELETE     => 'Effacer le fichier',

   EDIT_TITLE => 'Entrer/�diter des donn�es d\'annotation',

   IMAGE_WIDTH => 'Largeur d\'image',

   BETWEEN     => 'Entre les pistes',

   BENEATH     => 'Sous l\'affichage',

   LEFT        => 'Left',

   RIGHT       => 'Right',

   TRACK_NAMES => 'Tableau des pistes',
 
   ALPHABETIC => 'Tri alphab�tique',

   VARYING => 'Pas de tri',

   SET_OPTIONS => 'Configurer les pistes...',

   CLEAR_HIGHLIGHTING => 'Supprimer le surlignage',

   UPDATE      => 'Mise � jour de l\'image',

   DUMPS       => 'Sorties, recherches et autres op�rations',

   DATA_SOURCE => 'Source de donn�es',

   UPLOAD_TRACKS =>'Ajouter vos propres pistes',

   UPLOAD_TITLE => 'Ajouter vos propres annotations',

   UPLOAD_FILE => 'Ajouter un fichier',

   KEY_POSITION => 'Position des l�gendes',

   BROWSE      => 'Parcourir...',

   UPLOAD      => 'Ajouter',

   NEW         => 'Nouveau...',

   REMOTE_TITLE => 'Ajouter des annotations distantes',

   REMOTE_URL   => 'Entrer une URL pour des annotations distantes',

   UPDATE_URLS  => 'Mettre � jour les URLs',

   PRESETS      => "--Choix d'une URL pr�d�finie--",

   FEATURES_TO_HIGHLIGHT => 'Surligner les informations (info1 info2...)',

   REGIONS_TO_HIGHLIGHT => 'Surligner les r�gions (r�gion1:d�but..fin r�gion2:d�but..fin)',

   FEATURES_TO_HIGHLIGHT_HINT => 'Astuce : utilisez information@couleur pour choisir la couleur, par exemple \'NUT21@lightblue\'',

   REGIONS_TO_HIGHLIGHT_HINT  => 'Astuce : utilisez r�gion@couleur pour choisir la couleur, par exemple \'Chr1:10000..20000@lightblue\'',
	    
   NO_TRACKS    => '*aucune*',

   FILE_INFO    => 'Derni�re modif. %s.  R�f�rentiel annot� : %s',

   FOOTER_1     => <<END,
NB: Cette page utilise un cookie pour sauver et restituer les informations
de configuration. Vos informations ne sont pas partag�es.
END

   FOOTER_2    => 'Generic genome browser version %s',

   #----------------------
   # MULTIPLE MATCHES PAGE
   #----------------------

   HIT_COUNT      => 'Les  %d r�gions suivantes correspondent � votre requ�te.',

   POSSIBLE_TRUNCATION => 'Les r�sultats de la recherche sont limit�s � %d hits ; la liste risque d\'�tre incompl�te.',

   MATCHES_ON_REF => 'Correspondance avec %s',

   SEQUENCE        => 's�quence',

   SCORE           => 'score=%s',

   NOT_APPLICABLE => 'n/a',

   BP             => 'pb',

   #--------------
   # SETTINGS PAGE
   #--------------

   SETTINGS => 'Param�tres pour %s',

   UNDO     => 'Annuler les modifications',

   REVERT   => 'Valeurs par d�faut',

   REFRESH  => 'Rafraichir',

   CANCEL_RETURN   => 'Annuler les modifications et revenir...',

   ACCEPT_RETURN   => 'Accepter les modifications et revenir...',

   OPTIONS_TITLE => 'Options de pistes',

   SETTINGS_INSTRUCTIONS => <<END,
La boite <i>Voir</i> active ou d�sctive la piste. L'option
<i>Compacter</i> force la piste � �tre consens�e pour que 
les annotations se chevauchent. Les options <i>'Etendre'</i>
et <i>Hyper�tendre</i> activent un contr�le de collision qui
utilise des algorithmes de mise en page plus lents et plus rapides.
Les options <i>Etendre</i> &amp; <i>�tiqueter</i> et <i>Hyper�tendre</i>
&amp; <i>�tiqueter</i> rend obligatoire l'�tiquetage des annotations.
Si <i>Auto</i> est s�lectionn�, le contr�le de collision et les
options d'�tiquetage seront r�gl�es automatiquements si l'espace
le permet. Pour changer l'ordre des pistes, utilisez le menu 
<i>Changer l'ordre des pistes</i> pour assigner une annotation
� une piste. Pour limiter le nombre d'annotations de ce type
devant �tre affich�es, il faut changer la valeur du menu
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

   EXPAND_LABEL => 'Etendre & �tiqueter',

   HYPEREXPAND => 'Hyper�tendre',

   HYPEREXPAND_LABEL =>'Hyper�tendre & �tiqueter',

   NO_LIMIT    => 'Pas de limite',

   OVERVIEW    => 'Aper�u',

   EXTERNAL    => 'Externe',

   ANALYSIS    => 'Analyse',

   GENERAL     => 'G�n�ral',

   DETAILS     => 'D�tails',

   REGION      => 'R�gion',

   ALL_ON      => 'Tout activer',

   ALL_OFF     => 'Tout d�sactiver',

   #--------------
   # HELP PAGES
   #--------------

   CLOSE_WINDOW => 'Fermer cette fen�tre',

   TRACK_DESCRIPTIONS => 'Description de la piste citations',

   BUILT_IN           => 'Pistes disponibles sur ce serveur',

   EXTERNAL           => 'Pistes d\'annotation externes',

   ACTIVATE           => 'Veuillez activer cette piste pour voir ses informations.',

   NO_EXTERNAL        => 'Il n\'y a pas de caract�ristiques externes charg�es.',

   NO_CITATION        => 'Il n\'y a pas d\'informations suppl�mentaires disponibles.',

   #--------------
   # PLUGIN PAGES
   #--------------

 ABOUT_PLUGIN  => 'A propos de %s',

 BACK_TO_BROWSER => 'Retour au Browser',

 PLUGIN_SEARCH_1   => '%s (via la recherche %s)',

 PLUGIN_SEARCH_2   => '&lt; Recherche %s &gt;',

 CONFIGURE_PLUGIN   => 'Configurer',

 BORING_PLUGIN => "Ce module n'a pas de param�tres de configuration suppl�mentaires.",

   #--------------
   # ERROR MESSAGES
   #--------------

 NOT_FOUND => "Le r�f�rentiel <i>%s</i> n'est pas reconnu. Voyez l\'aide pour des suggestions.",

 TOO_BIG   => 'La vue d�taill�e est limit�e � %s bases.  Cliquez sur la vue d\'ensemble pour s�lectionner une r�gion de largeur %s pb.',

 PURGED    => "Impossible de trouver le fichier nomm� %s.  Peut �tre a-t-il �t� supprim� ?",

 NO_LWP    => "Ce serveur n\'est pas configur� pour ramener des URLs externes.",

 FETCH_FAILED  => "Je n\'ai pas pu retrouver %s: %s.",

 TOO_MANY_LANDMARKS => '%d r�f�rentiels.  La liste est trop grande.',

 SMALL_INTERVAL    => 'Redimmensionnement du petit intervalle � %s pb',

 NO_SOURCES        => 'Vous n\'avez pas configur� de sources de donn�es. Peut-�tre n\'avez-vous pas les droits pour les voir.',

};
