# do not remove the { } from the top and bottom of this page!!!
{

 CHARSET =>   'ISO-8859-1',

   #----------
   # MAIN PAGE
   #----------

   PAGE_TITLE => 'Buscador de Genoma',

   SEARCH_INSTRUCTIONS => <<END,
Search using a sequence name, gene name,
locus%s, or other landmark. The wildcard
character * is allowed.
END

   NAVIGATION_INSTRUCTIONS => <<END,
To center on a location, click the ruler. Use the Scroll/Zoom buttons
to change magnification and position. To save this view,
<a href="%s">bookmark this link.</a>
END

   EDIT_INSTRUCTIONS => <<END,
Edit your uploaded annotation data here.
You may use tabs or spaces to separate fields,
but fields that contain whitespace must be contained in
double or single quotes.
END

   SHOWING_FROM_TO => 'Mostrando %s de %s, Posiciones %s a %s',

   INSTRUCTIONS      => 'Instrucciones',

   HIDE              => 'Esconde',

   SHOW              => 'Muestra',

   SHOW_INSTRUCTIONS => 'Muestra Instrucciones',

   LANDMARK => 'Punto o Region de Referencia',

   BOOKMARK => 'Marca esta Página',

   GO       => 'Ir',

   FIND     => 'Encontrar',

   SEARCH   => 'Buscar',

   DUMP     => 'Tirar',

   ANNOTATE     => 'Anotar',

   SCROLL   => 'Avanzar/Acercar',

   RESET    => 'Reiniciar',

   DOWNLOAD_FILE    => 'Bajar el Documento',

   DOWNLOAD_DATA    => 'Bajar los Datos',

   DOWNLOAD         => 'Bajar',

   DISPLAY_SETTINGS => 'Mostrar Configuraciones',

   TRACKS   => 'Pistas',

   EXTERNAL_TRACKS => '(Pistas Externas en Itálicas)',

   EXAMPLES => 'Ejemplos',

   HELP     => 'Ayuda',

   HELP_FORMAT => 'Ayuda con el Formato del Documento',

   CANCEL   => 'Cancelar',

   ABOUT    => 'Acerca de...',

   REDISPLAY   => 'Volver a Mostrar',

   CONFIGURE   => 'Configurar...',

   EDIT       => 'Editar Documento...',

   DELETE     => 'Borrar Documento',

   EDIT_TITLE => 'Insertar/Editar Datos de Anotación',

   IMAGE_WIDTH => 'Ancho de la Imagen',

   BETWEEN     => 'Entre',

   BENEATH     => 'Debajo',

   SET_OPTIONS => 'Definir Opciones para Pistas/Trayectoria...',

   UPDATE      => 'Actualizar Imagen',

   DUMPS       => 'Depósitos, Búsquedas y otras Operaciones',

   DATA_SOURCE => 'Fuente de Datos',

   UPLOAD_TITLE=> 'Subir tus Anotaciones',

   UPLOAD_FILE => 'Subir un Documento',

   KEY_POSITION => 'Posición de la Clave',

   BROWSE      => 'Buscar...',

   UPLOAD      => 'Subir',

   NEW         => 'Nuevo...',

   REMOTE_TITLE => 'Agregar Anotaciones Remotas',

   REMOTE_URL   => 'Insertar Anotación Remota -Localizador (URL)',

   UPDATE_URLS  => 'Actualizar URLs',

   PRESETS      => '-Seleccione URL pre-establecido--',

   FILE_INFO    => '%s Modificados por última vez.  Puntos de Referencia Anotados: %s',

   FOOTER_1     => <<END,
Note: This page uses cookie to save and restore preference information.
No information is shared.
END

   FOOTER_2    => 'Versión Genérica del Buscador de Genoma %s',

   #----------------------
   # MULTIPLE MATCHES PAGE
   #----------------------

   HIT_COUNT      => 'Las siguientes %d regiones coinciden con la que solicitaste.',

   MATCHES_ON_REF => 'Cantidad de regiones que coinciden en %s',

   SEQUENCE        => 'secuencia',

   SCORE           => 'valor=%s',

   NOT_APPLICABLE => 'n/a',

   BP             => 'pares de bases',

   #--------------
   # SETTINGS PAGE
   #--------------

   SETTINGS => 'Configuración para %s',

   UNDO     => 'Deshacer los Cambios',

   REVERT   => 'Revertir a la Configuración Pre-establecida',

   REFRESH  => 'Refrescar',

   CANCEL_RETURN   => 'Cancelar Cambios y Regresar...',

   ACCEPT_RETURN   => 'Aceptar Cambios y Regresar...',

   OPTIONS_TITLE => 'Seguir Opciones',

   SETTINGS_INSTRUCTIONS => <<END,
The <i>Show</i> checkbox turns the track on and off. The
<i>Compact</i> option forces the track to be condensed so that
annotations will overlap. The <i>Expand</i> and <i>Hyperexpand</i>
options turn on collision control using slower and faster layout
algorithms. The <i>Expand</i> &amp; <i>label</i> and <i>Hyperexpand
&amp; label</i> options force annotations to be labeled. If
<i>Auto</i> is selected, the collision control and label options will
be set automatically if space permits. To change the track order use
the <i>Change Track Order</i> popup menu to assign an annotation to a
track. To limit the number of annotations of this type shown, change
the value of the <i>Limit</i> menu.
END

   TRACK  => 'Pista',

   TRACK_TYPE => 'Tipo de Pista',

   SHOW => 'Mostrar',

   FORMAT => 'Formatear',

   LIMIT  => 'Limitar',

   ADJUST_ORDER => 'Ajustar el Orden',

   CHANGE_ORDER => 'Cambiar el Orden',

   AUTO => 'Auto',

   COMPACT => 'Compacto',

   EXPAND => 'Extender',

   EXPAND_LABEL => 'Extender & Etiquetar',

   HYPEREXPAND => 'Hiper-extender',

   HYPEREXPAND_LABEL =>'Hiper-extender & Etiquetar',

   NO_LIMIT    => 'Sin límite',

   #--------------
   # HELP PAGES
   #--------------

   CLOSE_WINDOW => 'Cerrar esta Ventana',

   TRACK_DESCRIPTIONS => 'Seguir la Pista de Descripciones & Citas',

   BUILT_IN           => 'Pistas Incluídas en este Servidor',

   EXTERNAL           => 'Pistas de Anotación Externas',

   ACTIVATE           => 'Favor de activar esta pista para ver sus contenidos.',

   NO_EXTERNAL        => 'Características externas no han sido cargadas.',

   NO_CITATION        => 'No existe información adicional.',

   #--------------
   # PLUGIN PAGES
   #--------------

 ABOUT_PLUGIN  => 'Acerca de %s',

 BACK_TO_BROWSER => 'Regresar al Buscador',

 PLUGIN_SEARCH_1   => '%s (por medio de búsqueda de %s)',

 PLUGIN_SEARCH_2   => '&lt;%s busca&gt;',

 CONFIGURE_PLUGIN   => 'Configurar',

 BORING_PLUGIN => 'Este accesorio no tiene configuraciones adicionales.',

   #--------------
   # ERROR MESSAGES
   #--------------

 NOT_FOUND => 'El punto de referencia denominado <i>%s</i> no es reconocido. Ver las páginas de ayuda para sugerencias.',

 TOO_BIG   => 'La vista detallada se limita a %s bases.  Pulsar en el esquema general para seleccionar una región de %s pares de bases de ancho.',

 PURGED    => "No puedo encontrar el documento denominado %s.  Tal vez ha sido eliminado?.",

 NO_LWP    => "Este servidor no esta configurado para importar URLs externos.",

 FETCH_FAILED  => "No pude importar %s: %s.",

 TOO_MANY_LANDMARKS => '%d puntos de referencia.  Demasiados para ennumerar.',

 SMALL_INTERVAL    => 'Ajustando el tamaño pequeño del intervalo a %s pares de bases',

};

