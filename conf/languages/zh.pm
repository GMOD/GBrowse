# do not remove the { } from the top and bottom of this page!!!
#Simple_Chinese language module by Li DaoFeng <lidaof@gmail.com>
#Modified from Tradition_Chinese version by Jack Chen <chenn@cshl.edu>
#Updated by Lam Man Ting Melody <paladinoflab@yahoo.com.hk> and Hu Zhiliang <zhilianghu@gmail.com>
#translation updated 2009.03.29
{

 CHARSET =>   'Big5',

   #----------
   # MAIN PAGE
   #----------

   PAGE_TITLE => '��]���s����',

   SEARCH_INSTRUCTIONS => <<END,
<b>�j��:</b> �i�H�ϥΧǦC�W�A��]�W�A��Ǧ��I %s �Ψ䥦�аO�i��j���C���\�ϥγq�t��*�C
END

   NAVIGATION_INSTRUCTIONS => <<END,
 <br><b>����:</b> �I���ФبϦ��I�~���C�ϥΨ���/�Y����s���ܩ�j���ƩM��m�C
END

   EDIT_INSTRUCTIONS => <<END,
�b���s��A�W�Ǫ��`���ƾڡC
�A�i�H�Q�Ψ���(tabs) �� �Ů���(spaces) �Ӥ���,
�����ƾڤw�����ťհϰ�A�h�����γ�޸������޸��]�A���̡C
END

   SHOWING_FROM_TO => '��� %s �A�Ӧ� %s�A�q %s �� %s',

   INSTRUCTIONS      => '����',

   HIDE              => '����',

   SHOW              => '���',

   SHOW_INSTRUCTIONS => '��ܤ���',

   HIDE_INSTRUCTIONS => '���ä���',

   SHOW_HEADER       => '��ܼ��D',

   HIDE_HEADER       => '���ü��D',

   LANDMARK => '�ϰ�лx',

   BOOKMARK => '�K�[���ñ',

   IMAGE_LINK => '�Ϲ��챵',

   PDF_LINK=> '�U��PDF',

   SVG_LINK   => '����qSVG�Ϲ�',

   SVG_DESCRIPTION => <<END,
<p>
�I���U�����챵�N����SVG�榡���Ϲ��CSVG�榡��jpg��png�榡����h�u�I�C
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
Linux�Τ�i�H���ըϥ� <a href="http://xml.apache.org/batik/">Batik SVG �d�ݾ�</a>.
</p>
<p>
<a href="%s" target="_blank">�b�s�s�������f���d��SVG�Ϲ�</a></p>
<p>
��control-click (Macintosh) ��
���Хk�� (Windows) ���ܾA��ﶵ�i�H�N�Ϲ��O�s��q���ϽL�C
</p>   
END

   IMAGE_DESCRIPTION => <<END,
<p>
�ͦ����O��������Ϲ�, �Ť����߶K�Ϲ������}��HTML����:
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
�p�G�����ܷ��[ (�V���� �� contig), �кɶq�Y�p�d�ݰϰ�C
</p>
END

   TIMEOUT  => <<'END',
�ШD�W�ɡC�z�����ܪ��ϰ�i��Ӥj�Ӥ�����ܡC
���������@�Ǽƾڳq�D �� ��ܵy�p���ϰ�.  �p�G�����૵�ġA�Ы����⪺ "���m" ���s�C
END

   GO       => '����',

   FIND     => '�M��',

   SEARCH   => '�d��',

   DUMP     => '�ɦL',

   HIGHLIGHT   => '�j��',

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

   OVERVIEW_TRACKS => '<sup>*</sup>�ƾڳq�D���[',

   REGION_TRACKS => '<sup>**</sup>�ƾڳq�D�ϰ�',

   EXAMPLES => '�d��',

   REGION_SIZE => '�ϰ�j�p (bp)',

   HELP     => '���U',

   HELP_FORMAT => '���U���榡',

   CANCEL   => '����',

   ABOUT    => '����...',

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

   CLEAR_HIGHLIGHTING => '�M���j��',

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

   FEATURES_TO_HIGHLIGHT => '�j�կS�� (�S��1 �S��2...)',

   REGIONS_TO_HIGHLIGHT => '�j�հϰ� (�ϰ�1:�_�l..���� �ϰ�2:�_�l..����)',

   FEATURES_TO_HIGHLIGHT_HINT => '����: �ίS�x@color ����C��, �p \'NUT21@lightblue\'',

   REGIONS_TO_HIGHLIGHT_HINT  => '����: �ίS�x@color ����C��, �p \'Chr1:10000..20000@lightblue\'',

   NO_TRACKS    => '*�ť�*',

   FILE_INFO    => '�̫�ק�� %s.  �`���лx: %s',

   FOOTER_1     => <<END,
�`�N: �������ϥ�cookies�ӫO�s�M��_�Τ᰾�n�H���C
�Τ�H�����|�n�S�C
END

   FOOTER_2    => '�q�ΰ�]���s�������� %s',

   #----------------------
   # MULTIPLE MATCHES PAGE
   #----------------------

   HIT_COUNT      => '�U�C %d �ϰ�ŦX�z���n�D',

   POSSIBLE_TRUNCATION  => '�j�����G�G�j���� %d �۲ŵ��G�G�C�X�����G�i�ण����C',

   MATCHES_ON_REF => '�۲ŵ��G�G %s',

   SEQUENCE        => '�ǦC',

   SCORE           => '�o��=%s',

   NOT_APPLICABLE => '���A��',

   BP             => 'bp',

   #--------------
   # SETTINGS PAGE
   #--------------

   SETTINGS => '%s ���]�m',

   UNDO     => '�������',

   REVERT   => '��_��w�]��',

   REFRESH  => '��s',

   CANCEL_RETURN   => '�������ê�^...',

   ACCEPT_RETURN   => '�������ê�^...',

   OPTIONS_TITLE => '�ƾڳq�D�ﶵ',

   SETTINGS_INSTRUCTIONS => <<END,
<i>���</i> �_��إi�H���}�������ƾڳq�D�C
<i>²��</i> �ﶵ�j�����Y�ƾڳq�D�A�ҥH���Ǫ`���|���|�C<i>�X�i</i> �M <i>�q�L�챵�X�i</i>
��Χֳt�κC�t�W����k�ӱ���ɭ��ۮe�ʡC<i>�X�i</i> �M <i>�аO</i> �H�� <i>�q�L�챵���X�i�M�аO </i> �ﶵ�j��`���Q�аO�C
�p�G��ܤF<i>�۰�</i> �ﶵ, �Ŷ����\������U�ɭ��ۮe����M�аO�ﶵ�N�|�]�m���۰ʡC
�n���ܼƾڳq�D�����ǥi�H�ϥ� <i>���ƾڳq�D����</i> �u�X��� �ì��ƾڳq�D���t�@�Ӫ`��. �n����`�����ƥ�, �Ч��
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

   COMPACT => '²��', #���Y / ���Y',

   EXPAND => '�X�i',

   EXPAND_LABEL => '�X�i�üаO',

   HYPEREXPAND => '�q�L�챵�X�i',

   HYPEREXPAND_LABEL =>'�q�L�챵�X�i�üаO',

   NO_LIMIT    => '�L����',

   OVERVIEW    => '����',

   EXTERNAL    => '�~����',

   ANALYSIS    => '���R',

   GENERAL     => '�@��',

   DETAILS     => '�Ӹ`',

   REGION      => '�ϰ�',

   ALL_ON      => '���}',

   ALL_OFF     => '����',

   #--------------
   # HELP PAGES
   #--------------
   
   OK => '�T�w',

   CLOSE_WINDOW => '�������f',

   TRACK_DESCRIPTIONS => '�ƾڳq�D���y�z�M�ޥ�',

   BUILT_IN           => '�o�ӪA�Ⱦ����b���ƾڳq�D',

   EXTERNAL           => '�~���`���ƾڳq�D',

   ACTIVATE           => '�пE�����ƾڳq�D�ìd�ݬ����H��',

   NO_EXTERNAL        => '�S�����J�~���S��',

   NO_CITATION        => '�S���B�~�������H��.',

   #--------------
   # PLUGIN PAGES
   #--------------

 ABOUT_PLUGIN  => '���� %s',

 BACK_TO_BROWSER => '��^���s����',

 PLUGIN_SEARCH   => '%s (�q�L %s �j��)',

#PLUGIN_SEARCH   => 'search via the %s plugin',
#PLUGIN_SEARCH_1   => '%s (�q�L %s �j��)',
#PLUGIN_SEARCH_2   => '&lt;%s �d��&gt;',

 CONFIGURE_PLUGIN   => '�t�m',

 BORING_PLUGIN => '������L���B�~�]�m',

   #--------------
   # ERROR MESSAGES
   #--------------

 NOT_FOUND => '�L�k�ѧO�W�� <i>%s</i> ���лx�C �Ьd�����U�����C',

 TOO_BIG   => '�d�ݽd�򭭨�b %s ج�򪺲Ӹ`�C  �b�������I����� %s �e���ϰ�.',

 PURGED    => "�䤣���� %s �C  �i��w�Q�R��?",

 NO_LWP    => "���A�Ⱦ����������~�����}",

 FETCH_FAILED  => "������� %s: %s.",

 TOO_MANY_LANDMARKS => '%d �лx�A�лx�Ӧh���������ܡC',

 SMALL_INTERVAL    => '�N�ϰ��Y�p�� %s bp',

 NO_SOURCES        => '�S���t�m�iŪ�����ƾڷ�.  �Ϊ̱z�S���v���d�ݥ���',

# Missed Terms

 ADD_YOUR_OWN_TRACKS => '�K�[�z�ۤv���ƾڳq�D',
 
 INVALID_SOURCE    => '�ӷ� %s ���X�z.',

 BACKGROUND_COLOR  => '��R�C��',

 FG_COLOR          => '�u���C��',

 HEIGHT           => '����',

 PACKING          => '�]��',

 GLYPH            => '�˦�',

 LINEWIDTH        => '�u���e��',

 DEFAULT          => '(�w�])',

 DYNAMIC_VALUE    => '�ʺA�p���',

 CHANGE           => '���',

 DRAGGABLE_TRACKS  => '�i�즲�ƾڳq�D',

 CACHE_TRACKS      => '�w�s�ƾڳq�D',

 CHANGE_DEFAULT  => '���w�]��',

 SHOW_TOOLTIPS     => '��ܤu�㴣��',

 OPTIONS_RESET     => '�Ҧ������]�m��_��w�]��',

 OPTIONS_UPDATED   => '�s�����I�t�m�ͮ�; �Ҧ������]�m�w��_��w�]��',

 SEND_TO_GALAXY    => '�ǰe���ϰ��Galaxy',
#Galaxy http://main.g2.bx.psu.edu/

 NO_DAS            => '�w�˿��~: �������w��Bio::Das �Ҳդ~�����DAS ���}�C�гq�������޲z���C',

 SHOW_OR_HIDE_TRACK => '<b>��ܩ����æ��ƾڳq�D</b>',

 CONFIGURE_THIS_TRACK   => '<b>�������ƾڳq�D�]�w�C</b>',

 SHARE_THIS_TRACK   => '<b>���ɦ��ƾڳq�D</b>',

 SHARE_ALL          => '���ɳo�Ǽƾڳq�D',

 SHARE              => '���� %s',

 SHARE_INSTRUCTIONS_ONE_TRACK => <<END,
�p�����ɦ��ƾڳq�D����L�q�ΰ�]���s�����A���ƻs�H�U���}�A�M��e���t�~����]���s�����é󭶩���"��J���{�`��"���K�W�����}�C�Ъ`�N�G�Y���ƾڳq�D���ۤW���ɮ�,���ɥH�U���}����L�ϥΪ̥i������L�ϥΪ��[�ݤW���ɮפ�<b>����</b>���e�C
END

 SHARE_INSTRUCTIONS_ALL_TRACKS => <<END,
�p�����ɩҦ��w�蠟�ƾڳq�D����L�q�ΰ�]���s�����A���ƻs�H�U���}�A�M��e���t�~����]���s�����é󭶩���"��J���{�`��"���K�W�����}�C�Ъ`�N�G�Y����w�蠟�ƾڳq�D���ۤW���ɮ�,���ɥH�U���}����L�ϥΪ̥i������L�ϥΪ��[�ݤW���ɮפ�<b>����</b>���e�C
END

 SHARE_DAS_INSTRUCTIONS_ONE_TRACK => <<END,
�p���z�L<a href="http://www.biodas.org" target="_new">���G�������t��
(Distributed Annotation System, DAS)</a> ���ɦ��ƾڳq�D����L�q�ΰ�]���s�����A���ƻs�H�U���}�A�M��e���t�~����]���s�����é��J���s��DAS�ӷ��C<i>�w�q�ƾڳq�D ("wiggle"�ɮ�)�ΤW���ɮפ���HDAS���ɡC</i>
END

 SHARE_DAS_INSTRUCTIONS_ALL_TRACKS => <<END,
�p���z�L<a href="http://www.biodas.org" target="_new">���G�������t��
(Distributed Annotation System, DAS)</a> ���ɩҦ��w�蠟�ƾڳq�D����L�q�ΰ�]���s�����A���ƻs�H�U���}�A�M��e���t�~����]���s�����é��J���s��DAS�ӷ��C<i>�w�q�ƾڳq�D ("wiggle"�ɮ�)�ΤW���ɮפ���HDAS���ɡC</i>
END

};
