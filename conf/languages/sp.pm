# do not remove the { } from the top and bottom of this page!!!
{

 CHARSET =>   'ISO-8859-1',

   #----------
   # MAIN PAGE
   #----------

   PAGE_TITLE => 'Buscador de Genoma',

   SEARCH_INSTRUCTIONS => <<END,
Buscar usando el nombre de una secuencia, el nombre de un gen, locus%s, u otro punto o región de referencia. El caracter
comodín * está permitido.
END

   NAVIGATION_INSTRUCTIONS => <<END,
Para concentrarse en una locación, pulsar sobre la regla. Usar los botones Avanzar/Acercar
para cambiar la magnificación y la posición. Para grabar tal imagen,
<a href="%s">marcar esta página.</a>
END

   EDIT_INSTRUCTIONS => <<END,
Editar datos anotacdos que han sido subidos aquí.
Puedes usar sangrías (tabs) o espacios para separar campos,
pero campos que contengan espacios en blanco deben especificarse entre
comillas dobles o sencillas.
END

   SHOWING_FROM_TO => 'Mostrando %s de %s, Posiciones %s a %s',

   INSTRUCTIONS      => 'Instrucciones',

   HIDE              => 'Esconder',

   SHOW              => 'Mostrar',

   SHOW_INSTRUCTIONS => 'Mostrar Instrucciones',

   LANDMARK => 'Punto o Región de Referencia',

   BOOKMARK => 'Marcar esta Página',

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

   PRESETS      => '-Seleccionar URL pre-establecido--',

   FILE_INFO    => '%s Modificados por última vez.  Puntos de Referencia Anotados: %s',

   FOOTER_1     => <<END,
Nota: Esta página usa "cookie" para grabar y restaurar información sobre preferencias.
Ninguna información es compartida.
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
La casilla de <i>Mostrar</i> enciende y apaga la pista. La
opción <i>Compactar</i> obliga a condensar la pista, de manera que
las anotaciones se sobrepondrán. Las opciones <i>Expander</i> e^M <i>Hiperexpander</i> encienden el control de colisión usando algoritmos de diseño más lentos y^M más rápidos. Las opciones <i>Expander</i> &amp; <i>etiqueta</i> e <i>Hiperexpander &amp; etiqueta</i> obligan a las anotaciones a ser marcadas. Si
<i>Auto</i> es seleccionado, el control de colisión y las opciones de etiquetado serán
colocadas automáticamente si el espacio lo permite. Para cambiar el orden de las pistas usar
el menú emergente <i>Cambiar el Orden de las Pistas</i> para asignar una anotación a una
pista. Para limitar el número de anotaciones mostradas de este tipo, cambiar
el valor del menú de <i>Límite</i>.
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

