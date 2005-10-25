# do not remove the { } from the top and bottom of this page!!!
# Translation by Marcela Tello-Ruiz
{

 CHARSET =>   'ISO-8859-1',

   #----------
   # MAIN PAGE
   #----------

   PAGE_TITLE => 'Buscador de genoma',

   SEARCH_INSTRUCTIONS => <<END,
Buscar usando el nombre de una secuencia, el nombre de un gen, locus%s, u otro punto o regi�n de referencia. El caracter comod�n * est� permitido.
END

   NAVIGATION_INSTRUCTIONS => <<END,
Para concentrarse en una locaci�n, pulsar sobre la regla. Usar los botones Avanzar/Acercar para cambiar la magnificaci�n y la posici�n. Para grabar tal imagen,<a href="%s">marcar esta p�gina.</a>
END

   EDIT_INSTRUCTIONS => <<END,
Editar datos anotados que han sido subidos aqu�. Puedes usar sangr�as (tabs) o espacios para separar campos, pero campos que contengan espacios en blanco deben especificarse entre comillas dobles o sencillas.
END

   SHOWING_FROM_TO => 'Mostrando %s de %s, posiciones %s a %s',

   INSTRUCTIONS      => 'Instrucciones',

   HIDE              => 'Esconder',

   SHOW              => 'Mostrar',

   SHOW_INSTRUCTIONS => 'Mostrar instrucciones',

   HIDE_INSTRUCTIONS => 'Ocultar instrucciones',

   SHOW_HEADER       => 'Mostrar encabezado',

   HIDE_HEADER       => 'Ocultar encabezado',

   LANDMARK => 'Punto o regi�n de referencia',

   BOOKMARK => 'Marcar esta p�gina',

   IMAGE_LINK => 'Ligar a imagen',

   SVG_LINK   => 'Imagen de alta resoluci�n',

   SVG_DESCRIPTION => <<END,
<p>
La siguiente liga generar� esta imagen en un formato de Vector Escalable (SVG).  Imagenes SVG ofrecen varias ventajas sobre las im�genes basadas en raster, tales como los formatos jpeg o png.
</p>
<ul>
<li>totalmente escalable sin p�rdida en resoluci�n
<li>editable aspecto-por-aspecto en aplicaciones gr�ficas basadas en vectores
<li>si es necesario, puede ser convertido en EPS para ser inclu�do en una publicaci�n
</ul>
<p>
Para ver imagenes SVG, necesitas un buscador (browser) que sea capaz de aceptar SVG, el accesorio (plugin) para buscadores Adobe SVG, o una aplicaci�n para ver o editar SVG tal como Adobe Illustrator.
</p>
<p>
Accesorio (plugin) para buscadores Adobe SVG: <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Macintosh">Macintosh</a>
| <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Windows">Windows</a>
<br />
Usuarios de Linux pueden explorar el <a href="http://xml.apache.org/batik/">visualizador Batik SVG</a>.
</p>
<p>
<a href="%s" target="_blank">Ver imagen SVG en una ventana distinta</a></p>
<p>
para guardar esta imagen en tu disco, pulsa la tecla de control (Macintosh) o el bot�n de la derecha de tu rat�n (Windows) y selecciona la opci�n para guardar la liga correspondiente.
</p>   
END

   IMAGE_DESCRIPTION => <<END,
<p>
Para crear una imagen montada/incrustada de esta vista, corta y pega esta direcci�n (URL):
</p>
<pre>
&lt;IMAGE src="%s" /&gt;
</pre>
<p>
La imagen se ver� asi:
</p>
<p>
<img src="%s" />
</p>

<p>
Si s�lo aparece la vista global (cromosoma o contig), trata de reducir el tama�o de la regi�n.
</p>
END

   TIMEOUT  => <<'END',
Tu solicitud expir�.  Posiblemente seleccionaste una regi�n muy grande para ver.Puedes eliminar algunas de las pistas que seleccionaste antes o intentar ver una regi�n mas peque�a. Si esto te sucede continuamente, por favor presiona el bot�n rojo que dice "Reiniciar".
END

   GO       => 'Ir',

   FIND     => 'Encontrar',

   SEARCH   => 'Buscar',

   DUMP     => 'Depositar',

   HIGHLIGHT   => 'Resaltar',

   ANNOTATE     => 'Anotar',

   SCROLL   => 'Avanzar/Acercar',

   RESET    => 'Reiniciar',

   FLIP     => 'Dar la vuelta',

   DOWNLOAD_FILE    => 'Bajar el documento',

   DOWNLOAD_DATA    => 'Bajar los datos',

   DOWNLOAD         => 'Bajar',

   DISPLAY_SETTINGS => 'Mostrar configuraciones',

   TRACKS   => 'Pistas',

   EXTERNAL_TRACKS => '<i>Pistas externas en it�licas</i>',

   OVERVIEW_TRACKS => '<sup>*</sup>Resumen de pistas',

   REGION_TRACKS => '<sup>**</sup>Pistas en regi�n',

   EXAMPLES => 'Ejemplos',

   REGION_SIZE => 'Tama�o de la regi�n (en pares de bases)',

   HELP     => 'Ayuda',

   HELP_FORMAT => 'Ayuda con el formato del documento',

   CANCEL   => 'Cancelar',

   ABOUT    => 'Acerca de...',

   REDISPLAY   => 'Volver a mostrar',

   CONFIGURE   => 'Configurar...',

   CONFIGURE_TRACKS   => 'Configurar pistas...',

   EDIT       => 'Editar documento...',

   DELETE     => 'Borrar documento',

   EDIT_TITLE => 'Insertar/Editar datos de anotaci�n',

   IMAGE_WIDTH => 'Ancho de la imagen',

   BETWEEN     => 'Entre dos puntos de referencia',

   BENEATH     => 'Debajo',

   LEFT        => 'Izquierda',

   RIGHT       => 'Derecha',

   TRACK_NAMES => 'Nombres de las pistas',

   ALPHABETIC  => 'Alfab�tico',

   VARYING     => 'Variando/Variante',

   SET_OPTIONS => 'Definir Opciones para pistas...',

   CLEAR_HIGHLIGHTING => 'Eliminar resaltado',

   UPDATE      => 'Actualizar imagen',

   DUMPS       => 'Reportes &amp; an�lisis',

   DATA_SOURCE => 'Fuente de datos',

   UPLOAD_TRACKS=>'Agregar tus propias pistas',

   UPLOAD_TITLE=> 'Subir tus anotaciones',

   UPLOAD_FILE => 'Subir un documento',

   KEY_POSITION => 'Posici�n de la clave',

   BROWSE      => 'Buscar...',

   UPLOAD      => 'Subir',

   NEW         => 'Nuevo...',

   REMOTE_TITLE => 'Agregar anotaciones remotas',

   REMOTE_URL   => 'Insertar anotaci�n remota - Localizador (URL)',

   UPDATE_URLS  => 'Actualizar URLs',

   PRESETS      => '-Seleccionar URL pre-establecido--',

   FEATURES_TO_HIGHLIGHT => 'Resaltar propiedad(es) (propiedad1 propiedad2...)',

   REGIONS_TO_HIGHLIGHT => 'Resaltar regiones (region1:inicia..termina region2:inicia..termina)',

   FEATURES_TO_HIGHLIGHT_HINT => 'Idea: usar feature@color para seleccionar el color, como en \'NUT21@lightblue\'',

   REGIONS_TO_HIGHLIGHT_HINT  => 'Idea: usar region@color para seleccionar el color, como en \'Chr1:10000..20000@lightblue\'',

   NO_TRACKS    => '*Ninguna pista*',

   FILE_INFO    => '%s Modificados por �ltima vez.  Puntos de referencia anotados: %s',

   FOOTER_1     => <<END,
Nota: Esta p�gina usa "cookies" para grabar y restaurar informaci�n sobre preferencias. Ninguna informaci�n es compartida.
END

   FOOTER_2    => 'Versi�n gen�rica del buscador de genoma %s',

   #----------------------
   # MULTIPLE MATCHES PAGE
   #----------------------

   HIT_COUNT      => 'Las siguientes %d regiones coinciden con la que solicitaste.',

   POSSIBLE_TRUNCATION  => 'Resultados de b�squeda est�n limitados a %d aciertos; la lista puede ser incompleta.',

   MATCHES_ON_REF => 'Cantidad de regiones que coinciden (hits) en %s',

   SEQUENCE        => 'secuencia',

   SCORE           => 'valor=%s',

   NOT_APPLICABLE => 'n/a',

   BP             => 'pares de bases',

   #--------------
   # SETTINGS PAGE
   #--------------

   SETTINGS => 'Configuraci�n para %s',

   UNDO     => 'Deshacer los cambios',

   REVERT   => 'Revertir a la configuraci�n pre-establecida',

   REFRESH  => 'Refrescar',

   CANCEL_RETURN   => 'Cancelar cambios y regresar...',

   ACCEPT_RETURN   => 'Aceptar cambios y regresar...',

   OPTIONS_TITLE => 'Seguir la pista de opciones',

   SETTINGS_INSTRUCTIONS => <<END,
La casilla de <i>Mostrar</i> enciende y apaga la pista. La opci�n <i>Compactar</i> obliga a condensar la pista, de manera que las anotaciones se sobrepondr�n. Las opciones <i>Expander</i> e <i>Hiperexpander</i> encienden el control de colisi�n usando algoritmos de dise�o m�s lentos y m�s r�pidos. Las opciones <i>Expander</i> &amp; <i>etiqueta</i> e <i>Hiper-extender &amp; etiqueta</i> obligan a las anotaciones a ser marcadas. Si se selecciona <i>Auto</i>, el control de colisi�n y las opciones de etiquetado ser�n colocadas autom�ticamente si el espacio lo permite. Para cambiar el orden de las pistas usar el men� emergente <i>Cambiar el orden de las pistas</i> para asignar una anotaci�n a una pista. Para limitar el n�mero de anotaciones mostradas de este tipo, cambiar el valor del men� de <i>L�mite</i>.
END

   TRACK  => 'Pista',

   TRACK_TYPE => 'Tipo de pista',

   SHOW => 'Mostrar',

   FORMAT => 'Formatear',

   LIMIT  => 'Limitar',

   ADJUST_ORDER => 'Ajustar el orden',

   CHANGE_ORDER => 'Cambiar el orden',

   AUTO => 'Auto',

   COMPACT => 'Compacto',

   EXPAND => 'Extender',

   EXPAND_LABEL => 'Extender & etiquetar',

   HYPEREXPAND => 'Hiper-extender',

   HYPEREXPAND_LABEL =>'Hiper-extender & etiquetar',

   NO_LIMIT    => 'Sin l�mite',

   OVERVIEW    => 'Resumen',

   EXTERNAL    => 'Externo',

   ANALYSIS    => 'An�lisis',

   GENERAL     => 'General',

   DETAILS     => 'Detalles',

   REGION      => 'Regi�n',

   ALL_ON      => 'Todo encendido',

   ALL_OFF     => 'Todo apagado',

   #--------------
   # HELP PAGES
   #--------------

   CLOSE_WINDOW => 'Cerrar esta ventana',

   TRACK_DESCRIPTIONS => 'Seguir la pista de descripciones & citas',

   BUILT_IN           => 'Pistas inclu�das en este servidor',

   EXTERNAL           => 'Pistas de anotaci�n externas',

   ACTIVATE           => 'Favor de activar esta pista para ver sus contenidos.',

   NO_EXTERNAL        => 'Caracter�sticas externas no han sido cargadas.',

   NO_CITATION        => 'No existe informaci�n adicional.',

   #--------------
   # PLUGIN PAGES
   #--------------

 ABOUT_PLUGIN  => 'Acerca de %s',

 BACK_TO_BROWSER => 'Regresar al buscador',

 PLUGIN_SEARCH_1   => '%s (por medio de %s b�squeda)',

 PLUGIN_SEARCH_2   => '&lt;%s busca&gt;',

 CONFIGURE_PLUGIN   => 'Configurar',

 BORING_PLUGIN => 'Este accesorio no tiene configuraciones adicionales.',

   #--------------
   # ERROR MESSAGES
   #--------------

 NOT_FOUND => 'El punto de referencia denominado <i>%s</i> no es reconocido. Ver las p�ginas de ayuda para sugerencias.',

 TOO_BIG   => 'La vista detallada se limita a %s bases.  Pulsar en el esquema general para seleccionar una regi�n de %s pares de bases de ancho.',

 PURGED    => "No puedo encontrar el documento denominado %s.  Tal vez ha sido eliminado?.",

 NO_LWP    => "Este servidor no est� configurado para importar URLs externos.",

 FETCH_FAILED  => "No pude importar %s: %s.",

 TOO_MANY_LANDMARKS => '%d puntos de referencia.  Demasiados para ennumerar.',

 SMALL_INTERVAL    => 'Ajustando el tama�o peque�o del intervalo a %s pares de bases',

 NO_SOURCES        => 'No hay fuentes de datos legibles configuradas. Es posible que no tengas permiso para verlas.',

};
