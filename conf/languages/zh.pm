# do not remove the { } from the top and bottom of this page!!!
#Simple_Chinese language module by Li DaoFeng <lidaof@gmail.com>
#Modified from Tradition_Chinese version by Jack Chen <chenn@cshl.edu>
#translation updated 2008.06.02
{

 CHARSET =>   'Big5',

   #----------
   # MAIN PAGE
   #----------

   PAGE_TITLE => '��]���s����',

   SEARCH_INSTRUCTIONS => <<END,
�i�H�ϥΧǦC�W�A��]�W�A��Ǧ��I %s �Ψ䥦�аO�i��j���C���\�ϥγq�t�šC
END

   NAVIGATION_INSTRUCTIONS => <<END,
 �I���ФبϦ��I�~���C�ϥΨ���/�Y����s���ܩ�j���ƩM��m�C
END

   EDIT_INSTRUCTIONS => <<END,
�b���s��A�W�Ǫ��`���ƾڡC
�A�i�H�Q�Ψ���(tabs) �� �Ů���(spaces) �Ӥ���,
����_�ƾڤw�����ťհϰ�A�h�����γ�޸������޸��]�A���̡C
END

   SHOWING_FROM_TO => '�q%s ����� %s, ��m�q %s �� %s',

   INSTRUCTIONS      => '����',

   HIDE              => '����',

   SHOW              => '���',

   SHOW_INSTRUCTIONS => '��ܤ���',

   HIDE_INSTRUCTIONS => '���ä���',

   SHOW_HEADER       => '��ܼ��D',

   HIDE_HEADER       => '���ü��D',

   LANDMARK => '�Чөΰϰ�',

   BOOKMARK => '�K�[���ñ',

   IMAGE_LINK => '�Ϲ��챵',

   SVG_LINK   => '����qSVG�Ϲ�',

   SVG_DESCRIPTION => <<END,
<p>
�U�����챵�N����SVG�榡���Ϲ��CSVG�榡���jpg��png�榡���\�h�u�I�C
</p>
<ul>
<li>���v�T�Ϲ���q�����p�U���ܹϹ��j�p
<li>�i�H�δ��q�Ϲ��n��i��s��
<li>�p�G���ݭn�i�H�ഫ��EPS�榡�ѵo���ΡC
</ul>
<p>
�n���SVG�Ϲ�, �ݭn�s�������SVG, �Ҧp�i�H�ϥ�Adobe SVG �s��������, �Ϊ� Adobe Illustrator��SVG���d�ݩM�s��n��C
</p>
<p>
Adobe�� SVG �s��������: <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Macintosh">Macintosh</a>
| <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Windows">Windows</a>
<br />
Linux�Τ�i�H���� <a href="http://xml.apache.org/batik/">Batik SVG �d�ݾ�</a>.
</p>
<p>
<a href="%s" target="_blank">�b�s�s�������f���d��SVG�Ϲ�</a></p>
<p>
��control-click (Macintosh) ��
���Хk�� (Windows) �Z��ܾA��ﶵ�i�H�Ϲ��O�s��ϽL�C
</p>   
END

   IMAGE_DESCRIPTION => <<END,
<p>
�ͦ����O�_�������Ϲ�, �Ť��}�߶K�Ϲ���URL��HTML����:
</p>
<pre>
&lt;IMAGE src="%s" /&gt;
</pre>
<p>
�Ϲ��ݰ_�����ӬO�o��:
</p>
<p>
<img src="%s" />
</p>

<p>
�p�G�����ܷ��n (�V���� �� contig), �ɶq�Y�p�d�ݰϰ�C
</p>
END

   TIMEOUT  => <<'END',
�ШD�W�ɡC�z�����ܪ��ϰ�i��Ӥj�Ӥ�����ܡC
���������@�Ǽƾڳq�D �� ��ܵy�p���ϰ�.  �p�G���M�L�j�A�Ы����⪺ "���m" ���s�C
END

   GO       => '����',

   FIND     => '�M��',

   SEARCH   => '�d��',

   DUMP     => '���',

   HIGHLIGHT   => '���G',

   ANNOTATE     => '�`��',

   SCROLL   => '����/�Y��',

   RESET    => '���m',

   FLIP     => '�A��',

   DOWNLOAD_FILE    => '�U�����',

   DOWNLOAD_DATA    => '�U���ƾ�',

   DOWNLOAD         => '�U��',

   DISPLAY_SETTINGS => '��ܳ]�m',

   TRACKS   => '�ƾڳq�D',

   EXTERNAL_TRACKS => '<i>�~���ƾڳq�D�]����^</i>',

   OVERVIEW_TRACKS => '<sup>*</sup>�ƾڳq�D���n',

   REGION_TRACKS => '<sup>**</sup>�ƾڳq�D�ϰ�',

   EXAMPLES => '�S��',

   REGION_SIZE => '�ϰ�j�p (bp)',

   HELP     => '���U',

   HELP_FORMAT => '���U���榡',

   CANCEL   => '����',

   ABOUT    => '���_...',

   REDISPLAY   => '���s���',

   CONFIGURE   => '�t�m...',

   CONFIGURE_TRACKS   => '�t�m�ƾڳq�D...',

   EDIT       => '�s����...',

   DELETE     => '�R�����',

   EDIT_TITLE => '�i�J/�s�� �`���ƾ�',

   IMAGE_WIDTH => '�Ϲ��e��',

   BETWEEN     => '����',

   BENEATH     => '�U��',

   LEFT        => '����',

   RIGHT       => '�k��',

   TRACK_NAMES => '�ƾڳq�D�W�٪�',

   ALPHABETIC  => '�r��',

   VARYING     => '�ܤ�',

   SHOW_GRID    => '��ܺ���',

   SET_OPTIONS => '�]�w�ƾڳq�D�ﶵ...',

   CLEAR_HIGHLIGHTING => '�M�����G',

   UPDATE      => '��s�Ϲ�',

   DUMPS       => '�O�s�A�d�ߤΨ䥦���',

   DATA_SOURCE => '�ƾڨӷ�',

   UPLOAD_TRACKS=>'�W�Ǳz�ۤv���ƾڳq�D',

   UPLOAD_TITLE=> '�W�Ǳz�ۤv���`��',

   UPLOAD_FILE => '�W�Ǥ@�Ӥ��',

   KEY_POSITION => '�`����m',

   BROWSE      => '�s��...',

   UPLOAD      => '�W��',

   NEW         => '�s�W...',

   REMOTE_TITLE => '�K�[���{�`��',

   REMOTE_URL   => '��J���{�`�����}',

   UPDATE_URLS  => '��s���}',

   PRESETS      => '--��ܷ�e���}--',

   FEATURES_TO_HIGHLIGHT => '���G�S�� (�S��1 �S��2...)',

   REGIONS_TO_HIGHLIGHT => '���G�ϰ� (�ϰ�1:�_�l..���� �ϰ�2:�_�l..����)',

   FEATURES_TO_HIGHLIGHT_HINT => '����: �ίS��@color ����C��, �p \'NUT21@lightblue\'',

   REGIONS_TO_HIGHLIGHT_HINT  => '����: �ίS��@color ����C��, �p \'Chr1:10000..20000@lightblue\'',

   NO_TRACKS    => '*�ť�*',

   FILE_INFO    => '�̦Z�ק� %s.  �`���Ч�: %s',

   FOOTER_1     => <<END,
�`�N: �������ϥ�cookies�ӫO�s�M��_�Τ᰾�n�H���C
�Τ�H�����|�n�S�C
END

   FOOTER_2    => '�q�ΰ�]���s�������� %s',

   #----------------------
   # MULTIPLE MATCHES PAGE
   #----------------------

   HIT_COUNT      => '�U�C %d �ϰ�ŦX�z���n�D',

   POSSIBLE_TRUNCATION  => '�j�����G�i�୭�_ %d ��; ���G�C��i�ण�����C',

   MATCHES_ON_REF => '�ŦX�_ %s',

   SEQUENCE        => '�ǦC',

   SCORE           => '�o��=%s',

   NOT_APPLICABLE => '�L�� ',

   BP             => 'bp',

   #--------------
   # SETTINGS PAGE
   #--------------

   SETTINGS => '%s ���]�m',

   UNDO     => '�M�����',

   REVERT   => '�^�_���q�{��',

   REFRESH  => '��s',

   CANCEL_RETURN   => '�������}��^...',

   ACCEPT_RETURN   => '�������}��^...',

   OPTIONS_TITLE => '�ƾڳq�D�ﶵ',

   SETTINGS_INSTRUCTIONS => <<END,
<i>���</i> �_��إi�H����ƾڳq�D�����}�M�����C
<i>���Y</i> �ﶵ�j����Y�ƾڳq�D�A�ҥH���Ǫ`���|���|�C<i>�X�i</i> �M <i>�q�L�챵</i>
�ﶵ�Q�Χֳt�κC�t�W����k�}�ҸI����C<i>�X�i</i> �M <i>�аO</i> �H�� <i>�q�L�챵���X�i�M�аO </i> �ﶵ�j��`���Q�аO�C
�p�G��ܤF<i>�۰�</i> �ﶵ, �Ŷ����\������U�I������M�аO�ﶵ�N�|�]�m���۰ʡC
�n���ܼƾڳq�D�����ǥi�H�ϥ� <i>���ƾڳq�D����</i> �u�X��� �}���ƾڳq�D���t�@�Ӫ`��. �n����`�����ƥ�, ���
 <i>����</i> ��檺�ȡC
END

   TRACK  => '�ƾڳq�D',

   TRACK_TYPE => '�ƾڳq�D����',

   SHOW => '���',

   FORMAT => '�榡',

   LIMIT  => '����',

   ADJUST_ORDER => '���ǽվ�',

   CHANGE_ORDER => '���ƾڳq�D����',

   AUTO => '�۰�',

   COMPACT => '���Y',

   EXPAND => '�X�i',

   EXPAND_LABEL => '�X�i�}�аO',

   HYPEREXPAND => '�q�L�챵�X�i',

   HYPEREXPAND_LABEL =>'�q�L�챵�X�i�}�аO',

   NO_LIMIT    => '�L����',

   OVERVIEW    => '���n',

   EXTERNAL    => '�~����',

   ANALYSIS    => '���R',

   GENERAL     => '���n',

   DETAILS     => '�Ӹ`',

   REGION      => '�ϰ�',

   ALL_ON      => '�������}',

   ALL_OFF     => '��������',

   #--------------
   # HELP PAGES
   #--------------

   CLOSE_WINDOW => '�������f',

   TRACK_DESCRIPTIONS => '�ƾڳq�D���y�z�M�ޥ�',

   BUILT_IN           => '�o�ӪA�Ⱦ����b���ƾڳq�D',

   EXTERNAL           => '�~���`���ƾڳq�D',

   ACTIVATE           => '�пE�����ƾڳq�D�}�d�ݬ����H��',

   NO_EXTERNAL        => '�S�����J�~���S��',

   NO_CITATION        => '�S���B�~�������H��.',

   #--------------
   # PLUGIN PAGES
   #--------------

 ABOUT_PLUGIN  => '���_ %s',

 BACK_TO_BROWSER => '��^���s����',

 PLUGIN_SEARCH_1   => '%s (�q�L %s �j��)',

 PLUGIN_SEARCH_2   => '&lt;%s �d��&gt;',

 CONFIGURE_PLUGIN   => '�t�m',

 BORING_PLUGIN => '������L���B�~�]�m',

   #--------------
   # ERROR MESSAGES
   #--------------

 NOT_FOUND => '�L�k�ѧO�W�� <i>%s</i> ���ЧӡC �Ьd�����U�����C',

 TOO_BIG   => '�Ӹ`�d�ݭS�򭭨�b %s ج��C  �b���n���I����� %s �e���ϰ�.',

 PURGED    => "�䤣���� %s �C  �i��w�Q�R��?",

 NO_LWP    => "���A�Ⱦ����������~�����}",

 FETCH_FAILED  => "������� %s: %s.",

 TOO_MANY_LANDMARKS => '%d �ЧӡC �Ӧh�ӦC���X�ӡC',

 SMALL_INTERVAL    => '�N�ϰ��Y�p�� %s bp',

 NO_SOURCES        => '�S���t�m�iŪ�����ƾڷ�.  �Ϊ̱z�S���v���d�ݥ���',

# Missed Terms

ADD_YOUR_OWN_TRACKS => '�K�[�z�ۤv���ƾڳq�D',

BACKGROUND_COLOR  => '�I����R�C��',

 FG_COLOR          => '�e���u���C��',

CACHE_TRACKS      => '�w�s�ƾڳq�D',

CHANGE_DEFAULT  => '����q�{��',

 DEFAULT          => '(�q�{)',

 DYNAMIC_VALUE    => '�ʺA�p���',

 CHANGE           => '���',

 DRAGGABLE_TRACKS  => '�i�즲�ƾڳq�D',

 INVALID_SOURCE    => '�ӷ� %s ���X�z.',

 HEIGHT           => '����',

 PACKING          => '�]��',

 GLYPH            => '�˦�',

 LINEWIDTH        => '�u���e��',

 SHOW_TOOLTIPS     => '��ܤu�㴣��',

 OPTIONS_RESET     => '�Ҧ������]�m��_���q�{��',

 OPTIONS_UPDATED   => '�s�����I�t�m�ͮ�; �Ҧ������]�m�w��_���q�{��',
 
};
