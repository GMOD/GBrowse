# do not remove the { } from the top and bottom of this page!!!
{

 CHARSET =>   'ISO-8859-1',

   #----------
   # MAIN PAGE
   #----------

   PAGE_TITLE => 'Buscador de Genoma',

   SEARCH_INSTRUCTIONS => <<END,
Buscar usando el nombre de una secuencia, el nombre de un gen, locus%s, u otro punto o regi�n de referencia. El caracter
comod�n * est� permitido.
END

   NAVIGATION_INSTRUCTIONS => <<END,
Para concentrarse en una locaci�n, pulsar sobre la regla. Usar los botones Avanzar/Acercar
para cambiar la magnificaci�n y la posici�n. Para grabar tal imagen,
<a href="%s">marcar esta p�gina.</a>
END

   EDIT_INSTRUCTIONS => <<END,
Editar datos anotacdos que han sido subidos aqu�.
Puedes usar sangr�as (tabs) o espacios para separar campos,
pero campos que contengan espacios en blanco deben especificarse entre
comillas dobles o sencillas.
END

   SHOWING_FROM_TO => 'Mostrando %s de %s, Posiciones %s a %s',

   INSTRUCTIONS      => 'Instrucciones',

   HIDE              => 'Esconder',

   SHOW              => 'Mostrar',

   SHOW_INSTRUCTIONS => 'Mostrar Instrucciones',

   LANDMARK => 'Punto o Regi�n de Referencia',

   BOOKMARK => 'Marcar esta P�gina',

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

   EXTERNAL_TRACKS => '(Pistas Externas en It�licas)',

   EXAMPLES => 'Ejemplos',

   HELP     => 'Ayuda',

   HELP_FORMAT => 'Ayuda con el Formato del Documento',

   CANCEL   => 'Cancelar',

   ABOUT    => 'Acerca de...',

   REDISPLAY   => 'Volver a Mostrar',

   CONFIGURE   => 'Configurar...',

   EDIT       => 'Editar Documento...',

   DELETE     => 'Borrar Documento',

   EDIT_TITLE => 'Insertar/Editar Datos de Anotaci�n',

   IMAGE_WIDTH => 'Ancho de la Imagen',

   BETWEEN     => 'Entre',

   BENEATH     => 'Debajo',

   SET_OPTIONS => 'Definir Opciones para Pistas/Trayectoria...',

   UPDATE      => 'Actualizar Imagen',

   DUMPS       => 'Dep�sitos, B�squedas y otras Operaciones',

   DATA_SOURCE => 'Fuente de Datos',

   UPLOAD_TITLE=> 'Subir tus Anotaciones',

   UPLOAD_FILE => 'Subir un Documento',

   KEY_POSITION => 'Posici�n de la Clave',

   BROWSE      => 'Buscar...',

   UPLOAD      => 'Subir',

   NEW         => 'Nuevo...',

   REMOTE_TITLE => 'Agregar Anotaciones Remotas',

   REMOTE_URL   => 'Insertar Anotaci�n Remota -Localizador (URL)',

   UPDATE_URLS  => 'Actualizar URLs',

   PRESETS      => '-Seleccionar URL pre-establecido--',

   FILE_INFO    => '%s Modificados por �ltima vez.  Puntos de Referencia Anotados: %s',

   FOOTER_1     => <<END,
Nota: Esta p�gina usa "cookie" para grabar y restaurar informaci�n sobre preferencias.
Ninguna informaci�n es compartida.
END

   FOOTER_2    => 'Versi�n Gen�rica del Buscador de Genoma %s',

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

   SETTINGS => 'Configuraci�n para %s',

   UNDO     => 'Deshacer los Cambios',

   REVERT   => 'Revertir a la Configuraci�n Pre-establecida',

   REFRESH  => 'Refrescar',

   CANCEL_RETURN   => 'Cancelar Cambios y Regresar...',

   ACCEPT_RETURN   => 'Aceptar Cambios y Regresar...',

   OPTIONS_TITLE => 'Seguir Opciones',

   SETTINGS_INSTRUCTIONS => <<END,
La casilla de <i>Mostrar</i> enciende y apaga la pista. La
opci�n <i>Compactar</i> obliga a condensar la pista, de manera que
las anotaciones se sobrepondr�n. Las opciones <i>Expander</i> e^M <i>Hiperexpander</i> encienden el control de colisi�n usando algoritmos de dise�o m�s lentos y^M m�s r�pidos. Las opciones <i>Expander</i> &amp; <i>etiqueta</i> e <i>Hiperexpander &amp; etiqueta</i> obligan a las anotaciones a ser marcadas. Si
<i>Auto</i> es seleccionado, el control de colisi�n y las opciones de etiquetado ser�n
colocadas autom�ticamente si el espacio lo permite. Para cambiar el orden de las pistas usar
el men� emergente <i>Cambiar el Orden de las Pistas</i> para asignar una anotaci�n a una
pista. Para limitar el n�mero de anotaciones mostradas de este tipo, cambiar
el valor del men� de <i>L�mite</i>.
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

   NO_LIMIT    => 'Sin l�mite',

   #--------------
   # HELP PAGES
   #--------------

   CLOSE_WINDOW => 'Cerrar esta Ventana',

   TRACK_DESCRIPTIONS => 'Seguir la Pista de Descripciones & Citas',

   BUILT_IN           => 'Pistas Inclu�das en este Servidor',

   EXTERNAL           => 'Pistas de Anotaci�n Externas',

   ACTIVATE           => 'Favor de activar esta pista para ver sus contenidos.',

   NO_EXTERNAL        => 'Caracter�sticas externas no han sido cargadas.',

   NO_CITATION        => 'No existe informaci�n adicional.',

   #--------------
   # PLUGIN PAGES
   #--------------

 ABOUT_PLUGIN  => 'Acerca de %s',

 BACK_TO_BROWSER => 'Regresar al Buscador',

 PLUGIN_SEARCH_1   => '%s (por medio de b�squeda de %s)',

 PLUGIN_SEARCH_2   => '&lt;%s busca&gt;',

 CONFIGURE_PLUGIN   => 'Configurar',

 BORING_PLUGIN => 'Este accesorio no tiene configuraciones adicionales.',

   #--------------
   # ERROR MESSAGES
   #--------------

 NOT_FOUND => 'El punto de referencia denominado <i>%s</i> no es reconocido. Ver las p�ginas de ayuda para sugerencias.',

 TOO_BIG   => 'La vista detallada se limita a %s bases.  Pulsar en el esquema general para seleccionar una regi�n de %s pares de bases de ancho.',

 PURGED    => "No puedo encontrar el documento denominado %s.  Tal vez ha sido eliminado?.",

 NO_LWP    => "Este servidor no esta configurado para importar URLs externos.",

 FETCH_FAILED  => "No pude importar %s: %s.",

 TOO_MANY_LANDMARKS => '%d puntos de referencia.  Demasiados para ennumerar.',

 SMALL_INTERVAL    => 'Ajustando el tama�o peque�o del intervalo a %s pares de bases',

};

